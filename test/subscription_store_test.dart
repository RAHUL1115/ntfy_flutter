import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('adds a normalized subscription with a local display name', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);

    final saved = await store.add(
      url: '  HTTPS://Ntfy.SH/alerts/  ',
      displayName: '  Production alerts  ',
    );

    expect(saved.url, 'https://ntfy.sh/alerts');
    expect(saved.displayName, 'Production alerts');
    expect(await store.all(), [saved]);
  });

  test('rejects malformed and unsupported topic URLs', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);

    await expectLater(
      store.add(url: 'ntfy.sh/alerts'),
      throwsA(
        isA<SubscriptionException>().having(
          (error) => error.message,
          'message',
          contains('complete topic URL'),
        ),
      ),
    );
    await expectLater(
      store.add(url: 'ftp://ntfy.sh/alerts'),
      throwsA(
        isA<SubscriptionException>().having(
          (error) => error.message,
          'message',
          contains('HTTP or HTTPS'),
        ),
      ),
    );
    await expectLater(
      store.add(url: 'https://ntfy.sh'),
      throwsA(
        isA<SubscriptionException>().having(
          (error) => error.message,
          'message',
          contains('include a topic'),
        ),
      ),
    );
    await expectLater(
      store.add(url: 'https://ntfy.sh/not a topic'),
      throwsA(
        isA<SubscriptionException>().having(
          (error) => error.message,
          'message',
          contains('letters, numbers, hyphens, and underscores'),
        ),
      ),
    );
    await expectLater(
      store.add(url: "https://ntfy.sh/${List.filled(65, 'a').join()}"),
      throwsA(isA<SubscriptionException>()),
    );
  });

  test('rejects canonical duplicates regardless of display name', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);

    await store.add(
      url: 'http://EXAMPLE.com:80/alerts/',
      displayName: 'First name',
    );

    await expectLater(
      store.add(
        url: 'http://example.com/alerts',
        displayName: 'Different name',
      ),
      throwsA(
        isA<SubscriptionException>().having(
          (error) => error.message,
          'message',
          contains('already subscribed'),
        ),
      ),
    );
    final saved = await store.all();
    expect(saved.single.displayName, 'First name');
    expect(saved.single.url, 'http://example.com/alerts');
  });

  test('migrates the shipped schema without losing subscriptions', () async {
    final directory = await Directory.systemTemp.createTemp('ntfy_store_v1');
    final path = '${directory.path}/ntfy.db';
    addTearDown(() => directory.delete(recursive: true));
    final oldDatabase = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE subscriptions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              url TEXT NOT NULL UNIQUE,
              display_name TEXT
            )
          ''');
          await database.insert('subscriptions', {
            'url': 'https://ntfy.sh/existing',
            'display_name': 'Existing',
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

    expect((await store.all()).single.displayName, 'Existing');
    expect((await store.loadFeed(1)).messages, isEmpty);
  });

  test('persists messages oldest first with all supported fields', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final subscription = await store.add(url: 'https://ntfy.sh/alerts');

    final later = await store.ingest(
      subscription.id,
      IncomingMessage(
        eventId: 'later',
        time: DateTime.utc(2026, 1, 2, 3, 4),
        message: 'Later body',
        title: 'Later title',
        priority: 5,
        tags: const ['warning', 'server'],
      ),
    );
    final earlier = await store.ingest(
      subscription.id,
      IncomingMessage(
        eventId: 'earlier',
        time: DateTime.utc(2026, 1, 1, 2, 3),
        message: 'Earlier body',
      ),
    );

    final snapshot = await store.loadFeed(subscription.id);
    expect(snapshot.messages, [earlier, later]);
    expect(snapshot.messages.last.title, 'Later title');
    expect(snapshot.messages.last.priority, 5);
    expect(snapshot.messages.last.tags, ['warning', 'server']);
    expect(snapshot.cursor, 'earlier');
  });

  test('deduplicates per subscription without moving the cursor', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final first = await store.add(url: 'https://ntfy.sh/first');
    final second = await store.add(url: 'https://ntfy.sh/second');
    final original = IncomingMessage(
      eventId: 'same-id',
      time: DateTime.utc(2026),
      message: 'Original',
    );

    expect(await store.ingest(first.id, original), isNotNull);
    expect(
      await store.ingest(
        first.id,
        IncomingMessage(
          eventId: 'same-id',
          time: DateTime.utc(2027),
          message: 'Replay changed the body',
        ),
      ),
      isNull,
    );
    expect(await store.ingest(second.id, original), isNotNull);

    final firstFeed = await store.loadFeed(first.id);
    expect(firstFeed.messages.single.message, 'Original');
    expect(firstFeed.cursor, 'same-id');
    expect((await store.loadFeed(second.id)).messages, hasLength(1));
  });

  test('deletes and clears messages only within the selected topic', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final first = await store.add(url: 'https://ntfy.sh/first');
    final second = await store.add(url: 'https://ntfy.sh/second');
    final firstMessage = await store.ingest(
      first.id,
      IncomingMessage(
        eventId: 'first-a',
        time: DateTime.utc(2026),
        message: 'First A',
      ),
    );
    await store.ingest(
      first.id,
      IncomingMessage(
        eventId: 'first-b',
        time: DateTime.utc(2026, 1, 2),
        message: 'First B',
      ),
    );
    await store.ingest(
      second.id,
      IncomingMessage(
        eventId: 'second-a',
        time: DateTime.utc(2026),
        message: 'Second A',
      ),
    );

    await store.deleteMessage(second.id, firstMessage!.localId);
    expect((await store.loadFeed(first.id)).messages, hasLength(2));

    await store.deleteMessage(first.id, firstMessage.localId);
    expect((await store.loadFeed(first.id)).messages.single.message, 'First B');

    await expectLater(
      store.restoreMessage(second.id, firstMessage),
      throwsArgumentError,
    );
    await store.restoreMessage(first.id, firstMessage);
    final restored = await store.loadFeed(first.id);
    expect(restored.messages.map((message) => message.message), [
      'First A',
      'First B',
    ]);
    expect(restored.cursor, 'first-b');

    await store.clearMessages(first.id);
    final cleared = await store.loadFeed(first.id);
    expect(cleared.messages, isEmpty);
    expect(cleared.cursor, 'first-b');
    expect(
      (await store.loadFeed(second.id)).messages.single.message,
      'Second A',
    );
    expect(await store.all(), [first, second]);
  });

  test('removing a subscription cascades only its local history', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final first = await store.add(url: 'https://ntfy.sh/first');
    final second = await store.add(url: 'https://ntfy.sh/second');
    for (final subscription in [first, second]) {
      await store.ingest(
        subscription.id,
        IncomingMessage(
          eventId: 'message-${subscription.id}',
          time: DateTime.utc(2026),
          message: subscription.url,
        ),
      );
    }

    await store.remove(first.id);

    expect(await store.all(), [second]);
    await expectLater(store.loadFeed(first.id), throwsStateError);
    expect((await store.loadFeed(second.id)).messages, hasLength(1));
  });

  test('recovers saved subscriptions after reopening the database', () async {
    final directory = await Directory.systemTemp.createTemp('ntfy_store_test');
    final path = '${directory.path}/ntfy.db';
    addTearDown(() => directory.delete(recursive: true));

    final firstStore = await SubscriptionStore.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final original = await firstStore.add(url: 'https://ntfy.sh/restart');
    await firstStore.close();

    final reopenedStore = await SubscriptionStore.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(reopenedStore.close);

    expect(await reopenedStore.all(), [original]);
  });
}

Future<SubscriptionStore> _openMemoryStore() => SubscriptionStore.open(
  factory: databaseFactoryFfi,
  path: inMemoryDatabasePath,
);
