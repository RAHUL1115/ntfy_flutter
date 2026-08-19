import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/retention.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('defaults to Never and supports every finite duration', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);

    expect((await store.loadRetention()).global, RetentionPeriod.never);
    expect(RetentionPeriod.values, [
      RetentionPeriod.never,
      RetentionPeriod.oneHour,
      RetentionPeriod.threeHours,
      RetentionPeriod.sixHours,
      RetentionPeriod.twelveHours,
      RetentionPeriod.oneDay,
      RetentionPeriod.threeDays,
      RetentionPeriod.tenDays,
      RetentionPeriod.thirtyDays,
    ]);
  });

  for (final period in RetentionPeriod.values.where(
    (period) => period != RetentionPeriod.never,
  )) {
    test('${period.label} uses a strict controlled-time cutoff', () async {
      final store = await _openMemoryStore();
      addTearDown(store.close);
      final subscription = await store.add(url: 'https://ntfy.sh/cutoff');
      final now = DateTime.utc(2026, 6, 1, 12);
      final cutoff = now.subtract(period.duration);

      await _ingest(
        store,
        subscription.id,
        'expired',
        cutoff.subtract(const Duration(milliseconds: 1)),
      );
      await _ingest(store, subscription.id, 'at-cutoff', cutoff);
      await _ingest(
        store,
        subscription.id,
        'current',
        cutoff.add(const Duration(milliseconds: 1)),
      );
      await store.executeRetention(SetGlobalRetention(period, now: now));

      expect(
        (await store.loadFeed(subscription.id)).messages
            .map((message) => message.eventId),
        ['current', 'at-cutoff'],
      );
    });
  }

  test('topic inheritance and overrides clean independently', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final inherited = await store.add(url: 'https://ntfy.sh/inherited');
    final kept = await store.add(url: 'https://ntfy.sh/kept');
    final longer = await store.add(url: 'https://ntfy.sh/longer');
    final now = DateTime.utc(2026, 6, 1, 12);
    final twoHoursAgo = now.subtract(const Duration(hours: 2));
    for (final subscription in [inherited, kept, longer]) {
      await _ingest(
        store,
        subscription.id,
        'old-${subscription.id}',
        twoHoursAgo,
      );
    }

    await store.executeRetention(
      SetTopicRetention(kept.id, RetentionPeriod.never, now: now),
    );
    await store.executeRetention(
      SetTopicRetention(longer.id, RetentionPeriod.threeHours, now: now),
    );
    await store.executeRetention(
      SetGlobalRetention(RetentionPeriod.oneHour, now: now),
    );

    expect((await store.loadFeed(inherited.id)).messages, isEmpty);
    expect((await store.loadFeed(kept.id)).messages, hasLength(1));
    expect((await store.loadFeed(longer.id)).messages, hasLength(1));
    expect(
      (await store.loadRetention(subscriptionId: inherited.id)).override,
      isNull,
    );
    expect(
      (await store.loadRetention(subscriptionId: inherited.id)).effective,
      RetentionPeriod.oneHour,
    );
    expect(
      (await store.loadRetention(subscriptionId: kept.id)).override,
      RetentionPeriod.never,
    );
    expect(
      (await store.loadRetention(subscriptionId: longer.id)).effective,
      RetentionPeriod.threeHours,
    );
  });

  test(
    'clearing an override restores global inheritance immediately',
    () async {
      final store = await _openMemoryStore();
      addTearDown(store.close);
      final subscription = await store.add(url: 'https://ntfy.sh/override');
      final now = DateTime.utc(2026, 6, 1, 12);
      await _ingest(
        store,
        subscription.id,
        'old',
        now.subtract(const Duration(hours: 2)),
      );
      await store.executeRetention(
        SetTopicRetention(subscription.id, RetentionPeriod.never, now: now),
      );
      await store.executeRetention(
        SetGlobalRetention(RetentionPeriod.oneHour, now: now),
      );
      expect((await store.loadFeed(subscription.id)).messages, hasLength(1));

      await store.executeRetention(
        SetTopicRetention(subscription.id, null, now: now),
      );

      expect((await store.loadFeed(subscription.id)).messages, isEmpty);
      expect(
        (await store.loadRetention(subscriptionId: subscription.id)).override,
        isNull,
      );
    },
  );

  test(
    'cleanup is idempotent and preserves subscriptions and cursors',
    () async {
      final store = await _openMemoryStore();
      addTearDown(store.close);
      final subscription = await store.add(url: 'https://ntfy.sh/idempotent');
      final now = DateTime.utc(2026, 6, 1, 12);
      await _ingest(
        store,
        subscription.id,
        'expired-cursor',
        now.subtract(const Duration(days: 2)),
      );
      await store.executeRetention(
        SetGlobalRetention(RetentionPeriod.oneDay, now: now),
      );
      await store.executeRetention(RunRetentionCleanup(now));
      await store.executeRetention(RunRetentionCleanup(now));

      final snapshot = await store.loadFeed(subscription.id);
      expect(snapshot.messages, isEmpty);
      expect(snapshot.cursor, 'expired-cursor');
      expect((await store.all()).single.id, subscription.id);
    },
  );

  test('session cleans automatically while ingestion remains active', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final subscription = await store.add(url: 'https://ntfy.sh/automatic');
    final now = DateTime.utc(2026, 6, 1, 12);
    await store.executeRetention(
      SetGlobalRetention(RetentionPeriod.oneHour, now: now),
    );
    await _ingest(
      store,
      subscription.id,
      'expired',
      now.subtract(const Duration(hours: 2)),
    );
    final session = RetentionSession(
      store,
      cleanupInterval: const Duration(milliseconds: 10),
      now: () => now,
    );
    addTearDown(session.close);

    session.start();
    await _until(
      () async => (await store.loadFeed(subscription.id)).messages.isEmpty,
    );
    await _ingest(store, subscription.id, 'current', now);
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(
      (await store.loadFeed(subscription.id)).messages.single.eventId,
      'current',
    );
  });

  test(
    'cleanup and ingestion overlap without losing current messages',
    () async {
      final store = await _openMemoryStore();
      addTearDown(store.close);
      final subscription = await store.add(url: 'https://ntfy.sh/concurrent');
      final now = DateTime.utc(2026, 6, 1, 12);
      await store.executeRetention(
        SetGlobalRetention(RetentionPeriod.oneHour, now: now),
      );
      await _ingest(
        store,
        subscription.id,
        'expired',
        now.subtract(const Duration(hours: 2)),
      );

      for (var index = 0; index < 10; index++) {
        await Future.wait([
          store.executeRetention(RunRetentionCleanup(now)),
          _ingest(store, subscription.id, 'current-$index', now),
        ]);
      }

      final snapshot = await store.loadFeed(subscription.id);
      expect(snapshot.messages.map((message) => message.eventId), [
        for (var index = 9; index >= 0; index--) 'current-$index',
      ]);
      expect(snapshot.cursor, 'current-9');
      expect((await store.all()).single.id, subscription.id);
    },
  );

  test('automatic cleanup retries after a recoverable failure', () async {
    final repository = _FailOnceRetentionRepository();
    final session = RetentionSession(
      repository,
      cleanupInterval: const Duration(milliseconds: 10),
      now: () => DateTime.utc(2026),
    );
    addTearDown(session.close);
    var changes = 0;
    final subscription = session.changes.listen((_) => changes++);
    addTearDown(subscription.cancel);

    session.start();
    await _until(() async => repository.attempts >= 2 && changes >= 1);

    expect(repository.failures, 1);
    expect(repository.attempts, greaterThanOrEqualTo(2));
  });

  test(
    'cleanup remains safe after closing and reopening the database',
    () async {
      final directory = await Directory.systemTemp.createTemp('ntfy_retention');
      final path = '${directory.path}/ntfy.db';
      addTearDown(() => directory.delete(recursive: true));
      final now = DateTime.utc(2026, 6, 1, 12);

      final firstStore = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      final subscription = await firstStore.add(url: 'https://ntfy.sh/restart');
      await _ingest(
        firstStore,
        subscription.id,
        'expired',
        now.subtract(const Duration(days: 2)),
      );
      await firstStore.executeRetention(
        SetGlobalRetention(RetentionPeriod.oneDay, now: now),
      );
      await firstStore.close();

      final reopened = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(reopened.close);
      await reopened.executeRetention(RunRetentionCleanup(now));

      expect((await reopened.loadFeed(subscription.id)).messages, isEmpty);
      expect((await reopened.loadRetention()).global, RetentionPeriod.oneDay);
    },
  );

  test('migrates version 2 data to Never with topic inheritance', () async {
    final directory = await Directory.systemTemp.createTemp('ntfy_store_v2');
    final path = '${directory.path}/ntfy.db';
    addTearDown(() => directory.delete(recursive: true));
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE subscriptions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              url TEXT NOT NULL UNIQUE,
              display_name TEXT,
              last_message_id TEXT
            )
          ''');
          await database.execute('''
            CREATE TABLE messages (
              local_id INTEGER PRIMARY KEY AUTOINCREMENT,
              subscription_id INTEGER NOT NULL,
              event_id TEXT NOT NULL,
              event_time INTEGER NOT NULL,
              message TEXT NOT NULL,
              title TEXT,
              priority INTEGER NOT NULL,
              tags TEXT NOT NULL,
              UNIQUE(subscription_id, event_id),
              FOREIGN KEY(subscription_id) REFERENCES subscriptions(id) ON DELETE CASCADE
            )
          ''');
          await database.insert('subscriptions', {
            'url': 'https://ntfy.sh/existing',
            'display_name': 'Existing',
            'last_message_id': 'saved',
          });
          await database.insert('messages', {
            'subscription_id': 1,
            'event_id': 'saved',
            'event_time': DateTime.utc(2020).millisecondsSinceEpoch,
            'message': 'Preserved',
            'priority': 3,
            'tags': '[]',
          });
        },
      ),
    );
    await oldDatabase.close();

    final store = await SubscriptionStore.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(store.close);

    final settings = await store.loadRetention(subscriptionId: 1);
    expect(settings.global, RetentionPeriod.never);
    expect(settings.override, isNull);
    await store.executeRetention(RunRetentionCleanup(DateTime.utc(2030)));
    expect((await store.loadFeed(1)).messages.single.message, 'Preserved');
  });
}

Future<SubscriptionStore> _openMemoryStore() => SubscriptionStore.open(
  factory: databaseFactoryFfi,
  path: inMemoryDatabasePath,
);

Future<void> _until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _FailOnceRetentionRepository implements RetentionRepository {
  var attempts = 0;
  var failures = 0;

  @override
  Future<RetentionSettings> loadRetention({int? subscriptionId}) async =>
      const RetentionSettings(global: RetentionPeriod.never);

  @override
  Future<void> executeRetention(RetentionCommand command) async {
    attempts++;
    if (attempts == 1) {
      failures++;
      throw StateError('temporary database failure');
    }
  }
}

Future<void> _ingest(
  SubscriptionStore store,
  int subscriptionId,
  String eventId,
  DateTime time,
) async {
  await store.ingest(
    subscriptionId,
    IncomingMessage(eventId: eventId, time: time, message: eventId),
  );
}
