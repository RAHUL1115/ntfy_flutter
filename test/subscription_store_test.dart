import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/notification_policy.dart';
import 'package:ntfy_flutter/retention.dart';
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

  test('registers and unregisters a stable UnifiedPush endpoint', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);

    final first = await store.registerUnifiedPush(
      application: 'com.example.connector',
      token: 'connector-token',
      baseUrl: 'https://ntfy.sh',
    );
    final repeated = await store.registerUnifiedPush(
      application: 'com.example.connector',
      token: 'connector-token',
      baseUrl: 'https://ntfy.sh',
    );

    expect(repeated.endpoint, first.endpoint);
    expect(
      first.endpoint,
      matches(r'^https://ntfy\.sh/up[A-Za-z0-9]{12}\?up=1$'),
    );
    final subscription = (await store.all()).single;
    expect(subscription.unifiedPushApp, 'com.example.connector');
    expect(subscription.unifiedPushToken, 'connector-token');
    await expectLater(
      store.registerUnifiedPush(
        application: 'com.example.other',
        token: 'connector-token',
        baseUrl: 'https://ntfy.sh',
      ),
      throwsStateError,
    );

    final removed = await store.unregisterUnifiedPush('connector-token');
    expect(removed?.application, 'com.example.connector');
    expect(await store.all(), isEmpty);
  });

  test('renames locally and tracks unread messages until viewed', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final saved = await store.add(url: 'https://ntfy.sh/alerts');

    await store.ingest(
      saved.id,
      IncomingMessage(
        eventId: 'unread',
        time: DateTime.utc(2026),
        message: 'New alert',
      ),
    );
    expect((await store.all()).single.unreadCount, 1);

    final renamed = await store.rename(saved.id, '  Production  ');
    expect(renamed.displayName, 'Production');
    expect(renamed.url, saved.url);
    expect(renamed.unreadCount, 1);

    await store.markRead(saved.id);
    expect((await store.all()).single.unreadCount, 0);
    expect(
      (await store.loadFeed(saved.id)).messages.single.message,
      'New alert',
    );
  });

  test(
    'notification policy inherits globally and overrides per topic',
    () async {
      final store = await _openMemoryStore();
      addTearDown(store.close);
      final saved = await store.add(url: 'https://ntfy.sh/policy');
      const global = NotificationPolicy(
        mutedUntilEpochSeconds: 1234,
        minimumPriority: 4,
        insistentMaxPriority: true,
        attachmentDownloadMaxBytes: 5 * 1024 * 1024,
      );
      await store.setGlobalNotificationPolicy(global);

      expect(
        (await store.loadNotificationPolicy(subscriptionId: saved.id))
            .minimumPriority,
        4,
      );
      const topic = NotificationPolicy(
        minimumPriority: 2,
        subscriptionIconPath: 'managed/icon.png',
        dedicatedChannel: true,
      );
      await store.setTopicNotificationPolicy(saved.id, topic);
      final overridden = await store.loadNotificationPolicy(
        subscriptionId: saved.id,
      );
      expect(overridden.minimumPriority, 2);
      expect(overridden.mutedUntilEpochSeconds, 0);
      expect(overridden.subscriptionIconPath, 'managed/icon.png');
      expect(overridden.dedicatedChannel, isTrue);

      await store.setTopicNotificationPolicy(saved.id, null);
      expect(
        await store.loadNotificationPolicy(subscriptionId: saved.id),
        isA<NotificationPolicy>()
            .having((policy) => policy.minimumPriority, 'minimumPriority', 4)
            .having(
              (policy) => policy.insistentMaxPriority,
              'insistentMaxPriority',
              isTrue,
            )
            .having(
              (policy) => policy.attachmentDownloadMaxBytes,
              'attachmentDownloadMaxBytes',
              5 * 1024 * 1024,
            ),
      );
    },
  );

  test('per-topic policy fields keep independent global inheritance', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final saved = await store.add(url: 'https://ntfy.sh/policy-fields');
    await store.setGlobalNotificationPolicy(
      const NotificationPolicy(
        mutedUntilEpochSeconds: 100,
        minimumPriority: 4,
        insistentMaxPriority: false,
      ),
    );
    await store.setTopicNotificationPolicyOverrides(
      saved.id,
      const TopicNotificationPolicyOverrides(minimumPriority: 2),
    );
    await store.setGlobalNotificationPolicy(
      const NotificationPolicy(
        mutedUntilEpochSeconds: 200,
        minimumPriority: 5,
        insistentMaxPriority: true,
      ),
    );

    final resolved = await store.loadNotificationPolicy(
      subscriptionId: saved.id,
    );
    expect(resolved.minimumPriority, 2);
    expect(resolved.mutedUntilEpochSeconds, 200);
    expect(resolved.insistentMaxPriority, isTrue);
    final overrides = await store.loadTopicNotificationPolicyOverrides(
      saved.id,
    );
    expect(overrides.minimumPriority, 2);
    expect(overrides.mutedUntilEpochSeconds, isNull);
    expect(overrides.insistentMaxPriority, isNull);
  });

  test('per-topic background delivery persists independently', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final first = await store.add(url: 'https://ntfy.sh/first');
    final second = await store.add(url: 'https://ntfy.sh/second');

    final disabled = await store.setTopicBackgroundEnabled(first.id, false);

    expect(disabled.backgroundEnabled, isFalse);
    final subscriptions = await store.all();
    expect(
      subscriptions
          .singleWhere((item) => item.id == first.id)
          .backgroundEnabled,
      isFalse,
    );
    expect(
      subscriptions
          .singleWhere((item) => item.id == second.id)
          .backgroundEnabled,
      isTrue,
    );
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
    expect(await store.loadBackgroundListening(), isFalse);
  });

  test('persists the background-listening opt-in', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ntfy_background_setting',
    );
    final path = '${directory.path}/ntfy.db';
    addTearDown(() => directory.delete(recursive: true));

    final firstStore = await SubscriptionStore.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    expect(await firstStore.loadBackgroundListening(), isFalse);
    await firstStore.setBackgroundListening(true);
    await firstStore.close();

    final reopenedStore = await SubscriptionStore.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(reopenedStore.close);
    expect(await reopenedStore.loadBackgroundListening(), isTrue);
  });

  test('persists messages newest first with all supported fields', () async {
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
        sequenceId: 'deployment',
        click: 'https://example.com/details',
        icon: 'https://example.com/icon.png',
        contentType: 'text/markdown',
        encoding: 'base64',
        actions: const [
          MessageAction(
            id: 'copy',
            action: 'copy',
            label: 'Copy',
            value: 'value',
          ),
        ],
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
    expect(snapshot.messages, [later, earlier]);
    expect(snapshot.messages.first.title, 'Later title');
    expect(snapshot.messages.first.priority, 5);
    expect(snapshot.messages.first.tags, ['warning', 'server']);
    expect(snapshot.messages.first.sequenceId, 'deployment');
    expect(snapshot.messages.first.click, 'https://example.com/details');
    expect(snapshot.messages.first.icon, 'https://example.com/icon.png');
    expect(snapshot.messages.first.contentType, 'text/markdown');
    expect(snapshot.messages.first.encoding, 'base64');
    expect(snapshot.messages.first.actions.single.value, 'value');
    expect(snapshot.cursor, 'earlier');
  });

  test('clear and delete events apply to every matching sequence', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final subscription = await store.add(url: 'https://ntfy.sh/updates');
    for (final eventId in const ['first', 'second']) {
      await store.ingest(
        subscription.id,
        IncomingMessage(
          eventId: eventId,
          sequenceId: 'deployment',
          time: DateTime.utc(2026),
          message: eventId,
        ),
      );
    }
    await store.ingest(
      subscription.id,
      IncomingMessage(
        eventId: 'other',
        time: DateTime.utc(2026),
        message: 'other',
      ),
    );

    await store.ingest(
      subscription.id,
      IncomingMessage(
        eventId: 'clear-control',
        sequenceId: 'deployment',
        event: MessageEventType.clear,
        time: DateTime.utc(2026),
        message: '',
      ),
    );
    expect((await store.all()).single.unreadCount, 1);

    await store.ingest(
      subscription.id,
      IncomingMessage(
        eventId: 'delete-control',
        sequenceId: 'deployment',
        event: MessageEventType.delete,
        time: DateTime.utc(2026),
        message: '',
      ),
    );
    final snapshot = await store.loadFeed(subscription.id);
    expect(snapshot.messages.map((message) => message.eventId), ['other']);
    expect(snapshot.cursor, 'delete-control');
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
      attachment: const MessageAttachment(
        name: 'report.txt',
        url: 'https://ntfy.sh/file/report.txt',
        size: 42,
      ),
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
    expect(firstFeed.messages.single.attachment, original.attachment);
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
      'First B',
      'First A',
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
    expect(
      (await store.all()).map((item) => item.id),
      unorderedEquals([first.id, second.id]),
    );
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

    expect((await store.all()).single.id, second.id);
    await expectLater(store.loadFeed(first.id), throwsStateError);
    expect((await store.loadFeed(second.id)).messages, hasLength(1));
  });

  test('persists and removes a managed attachment file on clear', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final subscription = await store.add(url: 'https://ntfy.sh/files');
    final saved = await store.ingest(
      subscription.id,
      IncomingMessage(
        eventId: 'file',
        time: DateTime.utc(2026),
        message: 'Report',
        attachment: const MessageAttachment(
          name: 'report.txt',
          url: 'https://example.com/report.txt',
        ),
      ),
    );
    final directory = await Directory.systemTemp.createTemp('ntfy-file-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/report.txt');
    await file.writeAsString('report');

    await store.setAttachmentLocalPath(
      subscription.id,
      saved!.localId,
      file.path,
    );
    expect(
      (await store.loadFeed(subscription.id))
          .messages
          .single
          .attachment!
          .localPath,
      file.path,
    );

    await store.clearMessages(subscription.id);
    expect(await file.exists(), isFalse);
  });

  test('deleting one message removes its managed attachment file', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final subscription = await store.add(url: 'https://ntfy.sh/files');
    final saved = await store.ingest(
      subscription.id,
      IncomingMessage(
        eventId: 'single-file',
        time: DateTime.utc(2026),
        message: 'Report',
        attachment: const MessageAttachment(
          name: 'report.txt',
          url: 'https://example.com/report.txt',
        ),
      ),
    );
    final directory = await Directory.systemTemp.createTemp('ntfy-file-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/report.txt');
    await file.writeAsString('report');
    await store.setAttachmentLocalPath(
      subscription.id,
      saved!.localId,
      file.path,
    );

    await store.deleteMessage(subscription.id, saved.localId);

    expect(await file.exists(), isFalse);
  });

  test('retention cleanup removes managed attachment files', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final subscription = await store.add(url: 'https://ntfy.sh/files');
    final saved = await store.ingest(
      subscription.id,
      IncomingMessage(
        eventId: 'expired-file',
        time: DateTime.utc(2026),
        message: 'Report',
        attachment: const MessageAttachment(
          name: 'report.txt',
          url: 'https://example.com/report.txt',
        ),
      ),
    );
    final directory = await Directory.systemTemp.createTemp('ntfy-file-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/report.txt');
    await file.writeAsString('report');
    await store.setAttachmentLocalPath(
      subscription.id,
      saved!.localId,
      file.path,
    );

    await store.executeRetention(
      SetGlobalRetention(
        RetentionPeriod.oneHour,
        now: DateTime.utc(2026, 1, 2),
      ),
    );

    expect((await store.loadFeed(subscription.id)).messages, isEmpty);
    expect(await file.exists(), isFalse);
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
    const policy = NotificationPolicy(
      mutedUntilEpochSeconds: 4567,
      minimumPriority: 4,
      insistentMaxPriority: true,
      subscriptionIconPath: 'managed/restart.png',
      dedicatedChannel: true,
    );
    await firstStore.setTopicNotificationPolicy(original.id, policy);
    await firstStore.close();

    final reopenedStore = await SubscriptionStore.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(reopenedStore.close);

    expect(await reopenedStore.all(), [original]);
    expect(
      await reopenedStore.loadNotificationPolicy(subscriptionId: original.id),
      isA<NotificationPolicy>()
          .having(
            (value) => value.mutedUntilEpochSeconds,
            'mutedUntilEpochSeconds',
            4567,
          )
          .having((value) => value.minimumPriority, 'minimumPriority', 4)
          .having(
            (value) => value.subscriptionIconPath,
            'subscriptionIconPath',
            'managed/restart.png',
          )
          .having(
            (value) => value.dedicatedChannel,
            'dedicatedChannel',
            isTrue,
          ),
    );
  });

  test(
    'versioned backup restores subscriptions and notification history',
    () async {
      final source = await _openMemoryStore();
      addTearDown(source.close);
      final subscription = await source.add(
        url: 'https://ntfy.sh/backup',
        displayName: 'Backup topic',
      );
      await source.ingest(
        subscription.id,
        IncomingMessage(
          eventId: 'backed-up',
          time: DateTime.utc(2026),
          message: 'Preserved',
          tags: const ['warning'],
          sequenceId: 'backup-sequence',
          click: 'https://example.com',
          icon: 'https://example.com/icon.png',
          contentType: 'text/markdown',
          encoding: 'base64',
          actions: const [
            MessageAction(
              id: 'broadcast',
              action: 'broadcast',
              label: 'Send',
              intent: 'com.example.ACTION',
              extras: {'value': 'one'},
            ),
          ],
        ),
      );
      final backup = await source.exportBackup();
      final target = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(target.close);

      await target.restoreBackup(backup);

      final restored = (await target.all()).single;
      expect(restored.displayName, 'Backup topic');
      final message = (await target.loadFeed(restored.id)).messages.single;
      expect(message.message, 'Preserved');
      expect(message.sequenceId, 'backup-sequence');
      expect(message.click, 'https://example.com');
      expect(message.icon, 'https://example.com/icon.png');
      expect(message.contentType, 'text/markdown');
      expect(message.encoding, 'base64');
      expect(message.actions.single.intent, 'com.example.ACTION');
    },
  );

  test('invalid backup leaves the existing database untouched', () async {
    final store = await _openMemoryStore();
    addTearDown(store.close);
    final original = await store.add(url: 'https://ntfy.sh/original');
    final backup = await store.exportBackup();
    final subscriptions = List<Object?>.of(backup['subscriptions']! as List);
    backup['subscriptions'] = subscriptions;
    subscriptions.add({'url': 'not a URL'});

    await expectLater(store.restoreBackup(backup), throwsA(anything));

    expect(await store.all(), [original]);
  });

  test('backup restore discards untrusted attachment file paths', () async {
    final source = await _openMemoryStore();
    addTearDown(source.close);
    final subscription = await source.add(url: 'https://ntfy.sh/backup-file');
    await source.ingest(
      subscription.id,
      IncomingMessage(
        eventId: 'file',
        time: DateTime.utc(2026),
        message: 'File',
        attachment: const MessageAttachment(
          name: 'report.txt',
          url: 'https://example.com/report.txt',
        ),
      ),
    );
    final backup = await source.exportBackup();
    final messages = backup['messages']! as List;
    final attachment = Map<String, Object?>.from(
      (messages.single as Map)['attachment'] as Map,
    );
    final directory = await Directory.systemTemp.createTemp('ntfy-sentinel-');
    addTearDown(() => directory.delete(recursive: true));
    final sentinel = File('${directory.path}/keep.txt');
    await sentinel.writeAsString('keep');
    attachment['localPath'] = sentinel.path;
    (messages.single as Map)['attachment'] = attachment;
    final target = await _openMemoryStore();
    addTearDown(target.close);

    await target.restoreBackup(backup);
    final restored = (await target.all()).single;
    expect(
      (await target.loadFeed(restored.id))
          .messages
          .single
          .attachment!
          .localPath,
      isNull,
    );
    await target.clearMessages(restored.id);
    expect(await sentinel.exists(), isTrue);
  });
}

Future<SubscriptionStore> _openMemoryStore() => SubscriptionStore.open(
  factory: databaseFactoryFfi,
  path: inMemoryDatabasePath,
);
