import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
