import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/app_database.dart';
import 'package:ntfy_flutter/models.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  sqflite.databaseFactory = databaseFactoryFfi;

  late AppDatabase database;

  setUp(() async {
    final sqlite = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    database = AppDatabase(database: sqlite);
    await database.initialize();
  });

  tearDown(() => database.close());

  test(
    'initial import is read and event application dedupes with cursor',
    () async {
      var subscription = await database.addSubscription(
        'https://ntfy.sh',
        'news',
        initialEvents: [_event('first', 'old message')],
      );

      var summaries = await database.readSummaries();
      expect(summaries.single.unreadCount, 0);
      expect(summaries.single.latestMessage?.isRead, isTrue);
      expect(subscription.lastEventId, 'first');

      final next = _event('second', 'new message', second: 2);
      final inserted = await database.applyEvents(subscription, [next, next]);

      expect(inserted, hasLength(1));
      expect(inserted.single.eventId, 'second');
      expect(inserted.single.id, isPositive);
      final messages = await database.listMessages(subscription.id);
      expect(messages, hasLength(2));
      expect(messages.first.message, 'new message');
      summaries = await database.readSummaries();
      expect(summaries.single.unreadCount, 1);
      expect(summaries.single.latestMessage?.eventId, 'second');
      subscription = (await database.readSubscriptions()).single;
      expect(subscription.lastEventId, 'second');
    },
  );

  test('deletes one message or clears a topic without unsubscribing', () async {
    final subscription = await database.addSubscription(
      'https://ntfy.sh',
      'news',
    );
    await database.applyEvents(subscription, [
      _event('one', 'first'),
      _event('two', 'second', second: 1),
    ]);

    final messages = await database.listMessages(subscription.id);
    await database.deleteMessage(messages.first.id);
    expect(
      (await database.listMessages(subscription.id))
          .map((message) => message.eventId),
      ['one'],
    );

    await database.clearMessages(subscription.id);
    expect(await database.listMessages(subscription.id), isEmpty);
    expect(await database.readSubscriptions(), hasLength(1));
  });

  test('applies global retention with per-topic overrides', () async {
    final inherited = await database.addSubscription('https://ntfy.sh', 'news');
    final neverDelete = await database.addSubscription(
      'https://ntfy.sh',
      'alerts',
    );
    final oldTime = DateTime.utc(2025, 1, 1);
    final recentTime = DateTime.utc(2025, 1, 1, 4, 30);
    await database.applyEvents(inherited, [
      _eventAt('news-old', 'old', 'news', oldTime),
      _eventAt('news-new', 'new', 'news', recentTime),
    ]);
    await database.applyEvents(neverDelete, [
      _eventAt('alerts-old', 'old', 'alerts', oldTime),
      _eventAt('alerts-new', 'new', 'alerts', recentTime),
    ]);

    await database.setGlobalRetentionSeconds(
      const Duration(hours: 1).inSeconds,
    );
    await database.setSubscriptionRetentionSeconds(neverDelete.id, 0);
    final deleted = await database.deleteExpiredMessages(
      now: DateTime.utc(2025, 1, 1, 5),
    );

    expect(deleted, hasLength(1));
    expect(
      (await database.listMessages(inherited.id))
          .map((message) => message.eventId),
      ['news-new'],
    );
    expect(await database.listMessages(neverDelete.id), hasLength(2));
    expect(await database.readGlobalRetentionSeconds(), 3600);
    expect(
      (await database.readSubscriptions())
          .singleWhere((subscription) => subscription.id == neverDelete.id)
          .retentionSeconds,
      0,
    );

    await database.setSubscriptionRetentionSeconds(
      neverDelete.id,
      const Duration(hours: 3).inSeconds,
    );
    await database.deleteExpiredMessages(
      subscriptionId: neverDelete.id,
      now: DateTime.utc(2025, 1, 1, 5),
    );
    expect(
      (await database.listMessages(neverDelete.id))
          .map((message) => message.eventId),
      ['alerts-new'],
    );
  });

  test('migrates a version 1 database to retention settings', () async {
    final directory = await Directory.systemTemp.createTemp('ntfy-migration-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}legacy.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE subscriptions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              base_url TEXT NOT NULL,
              topic TEXT NOT NULL,
              last_event_id TEXT,
              created_at INTEGER NOT NULL,
              UNIQUE(base_url, topic)
            )
          ''');
          await database.execute('''
            CREATE TABLE messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              subscription_id INTEGER NOT NULL,
              event_id TEXT NOT NULL,
              event_time INTEGER NOT NULL,
              message TEXT NOT NULL,
              title TEXT,
              priority INTEGER NOT NULL,
              tags TEXT NOT NULL,
              is_read INTEGER NOT NULL,
              UNIQUE(subscription_id, event_id),
              FOREIGN KEY(subscription_id) REFERENCES subscriptions(id)
                ON DELETE CASCADE
            )
          ''');
        },
      ),
    );
    await legacy.insert('subscriptions', {
      'base_url': 'https://ntfy.sh',
      'topic': 'legacy',
      'created_at': DateTime.utc(2025).millisecondsSinceEpoch,
    });
    await legacy.close();

    final migrated = AppDatabase(path: path);
    await migrated.initialize();
    addTearDown(migrated.close);

    var subscription = (await migrated.readSubscriptions()).single;
    expect(subscription.retentionSeconds, isNull);
    expect(subscription.displayName, isNull);
    expect(await migrated.readGlobalRetentionSeconds(), 0);
    await migrated.setGlobalRetentionSeconds(3600);
    await migrated.setDisplayName(subscription.id, ' Legacy alerts ');
    subscription = (await migrated.readSubscriptions()).single;
    expect(await migrated.readGlobalRetentionSeconds(), 3600);
    expect(subscription.displayName, 'Legacy alerts');
    expect(subscription.displayNameOrTopic, 'Legacy alerts');
  });

  test('control events advance only the matching cursor', () async {
    final subscription = await database.addSubscription(
      'https://ntfy.sh',
      'news',
    );

    final inserted = await database.applyEvents(subscription, [
      _event('wrong', '', topic: 'other', event: 'keepalive'),
      _event('control', '', event: 'keepalive'),
    ]);

    expect(inserted, isEmpty);
    expect(await database.listMessages(subscription.id), isEmpty);
    expect((await database.readSubscriptions()).single.lastEventId, 'control');
  });

  test(
    'summaries, mark read, uniqueness, and unsubscribe cascade work',
    () async {
      final subscription = await database.addSubscription(
        'https://ntfy.sh',
        'alerts',
      );
      await database.applyEvents(subscription, [
        _event('one', 'first', topic: 'alerts'),
        _event('two', 'second', topic: 'alerts', second: 1),
      ]);

      var summary = (await database.readSummaries()).single;
      expect(summary.unreadCount, 2);
      expect(summary.latestMessage?.message, 'second');

      await database.markRead(subscription.id);
      summary = (await database.readSummaries()).single;
      expect(summary.unreadCount, 0);

      await expectLater(
        database.addSubscription('https://ntfy.sh', 'alerts'),
        throwsA(anything),
      );

      await database.unsubscribe(subscription.id);
      expect(await database.readSubscriptions(), isEmpty);
      expect(await database.listMessages(subscription.id), isEmpty);
      expect(
        await database.hasSubscriptionsForBase('https://ntfy.sh'),
        isFalse,
      );
    },
  );
}

NtfyEvent _eventAt(String id, String message, String topic, DateTime time) =>
    NtfyEvent(
      id: id,
      time: time,
      event: 'message',
      topic: topic,
      message: message,
    );

NtfyEvent _event(
  String id,
  String message, {
  String topic = 'news',
  int second = 0,
  String event = 'message',
}) => NtfyEvent(
  id: id,
  time: DateTime.utc(2025, 1, 1, 0, 0, second),
  event: event,
  topic: topic,
  message: message,
);
