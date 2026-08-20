import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/app_settings.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/notifications.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:ntfy_flutter/topic_feed.dart';

void main() {
  test(
    'subscription check verifies and then reuses Basic credentials',
    () async {
      final expectedAuthorization =
          'Basic ${base64Encode(utf8.encode('rahul:secret'))}';
      final seenAuthorization = <String?>[];
      final seenQueries = <Map<String, String>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final authorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        seenAuthorization.add(authorization);
        seenQueries.add(request.uri.queryParameters);
        if (authorization != expectedAuthorization) {
          request.response.statusCode = HttpStatus.forbidden;
        } else {
          request.response.headers.contentType = ContentType(
            'application',
            'x-ndjson',
            charset: 'utf-8',
          );
        }
        await request.response.close();
      });
      final settings = AppSettingsStore(
        preferences: _MemoryPreferences(),
        secrets: _MemorySecrets(),
      );
      final checker = HttpSubscriptionAccessChecker(settings);
      final origin = 'http://${server.address.address}:${server.port}';
      final topicUrl = '$origin/alerts';
      const username = 'rahul';
      const password = 'secret';
      final account = ServerAccount(
        baseUrl: origin,
        username: username,
        password: password,
      );

      expect(
        await checker.check(topicUrl: topicUrl),
        SubscriptionAccess.authenticationRequired,
      );
      expect(
        await checker.check(topicUrl: topicUrl, account: account),
        SubscriptionAccess.allowed,
      );
      await settings.saveAccount(account);
      expect(
        await checker.check(topicUrl: topicUrl),
        SubscriptionAccess.allowed,
      );
      expect(seenAuthorization, [
        null,
        expectedAuthorization,
        expectedAuthorization,
      ]);
      expect(seenQueries, [
        {'poll': '1'},
        {'poll': '1'},
        {'poll': '1'},
      ]);
    },
  );

  test('subscription check rejects a non-ntfy service', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>Not ntfy</html>');
      await request.response.close();
    });
    final checker = HttpSubscriptionAccessChecker(
      AppSettingsStore(
        preferences: _MemoryPreferences(),
        secrets: _MemorySecrets(),
      ),
    );

    await expectLater(
      checker.check(
        topicUrl: 'http://${server.address.address}:${server.port}/alerts',
      ),
      throwsA(
        isA<SubscriptionAccessException>().having(
          (error) => error.message,
          'message',
          'This URL does not appear to be an ntfy server.',
        ),
      ),
    );
  });

  test('subscription check reports an unreachable server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final address = server.address.address;
    final port = server.port;
    await server.close(force: true);
    final checker = HttpSubscriptionAccessChecker(
      AppSettingsStore(
        preferences: _MemoryPreferences(),
        secrets: _MemorySecrets(),
      ),
    );

    await expectLater(
      checker.check(topicUrl: 'http://$address:$port/alerts'),
      throwsA(
        isA<SubscriptionAccessException>().having(
          (error) => error.message,
          'message',
          'Could not reach this server. Check the address and try again.',
        ),
      ),
    );
  });

  test('parser accepts normal fields and ignores non-message input', () {
    final parsed = parseNtfyLine(
      jsonEncode({
        'event': 'message',
        'topic': 'alerts',
        'id': 'abc',
        'time': 1700000000,
        'message': 'Disk full',
        'title': 'Server',
        'priority': 5,
        'tags': ['warning', 'computer'],
        'attachment': {
          'name': 'report.txt',
          'url': 'https://ntfy.sh/file/report.txt',
          'type': 'text/plain',
          'size': 42,
          'expires': 1700003600,
        },
      }),
      'https://ntfy.sh/alerts',
    );

    expect(parsed?.eventId, 'abc');
    expect(
      parsed?.time,
      DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
    );
    expect(parsed?.message, 'Disk full');
    expect(parsed?.title, 'Server');
    expect(parsed?.priority, 5);
    expect(parsed?.tags, ['warning', 'computer']);
    expect(parsed?.attachment?.name, 'report.txt');
    expect(parsed?.attachment?.size, 42);

    for (final line in [
      '{bad json',
      '[]',
      jsonEncode({'event': 'keepalive', 'topic': 'alerts'}),
      jsonEncode({'event': 'future', 'topic': 'alerts'}),
      jsonEncode({
        'event': 'message',
        'topic': 'other',
        'id': 'x',
        'time': 1,
        'message': 'wrong',
      }),
      jsonEncode({
        'event': 'message',
        'topic': 'alerts',
        'id': 4,
        'time': 1,
        'message': 'bad',
      }),
    ]) {
      expect(parseNtfyLine(line, 'https://ntfy.sh/alerts'), isNull);
    }
  });

  test(
    'parser preserves advanced fields, decodes bytes, and accepts controls',
    () {
      final parsed = parseNtfyLine(
        jsonEncode({
          'event': 'message',
          'topic': 'alerts',
          'id': 'update-2',
          'sequence_id': 'deploy',
          'time': 1700000000,
          'message': base64Encode(utf8.encode('Hello 🐧')),
          'encoding': 'base64',
          'content_type': 'text/markdown',
          'click': 'https://example.com/details',
          'icon': 'https://example.com/icon.png',
          'actions': [
            {
              'id': 'open',
              'action': 'view',
              'label': 'Open',
              'clear': true,
              'url': 'https://example.com',
              'headers': {'X-Test': 'one'},
              'extras': {'result': 'ok'},
            },
          ],
        }),
        'https://ntfy.sh/alerts',
      );

      expect(parsed?.sequenceId, 'deploy');
      expect(parsed?.decodedMessage, 'Hello 🐧');
      expect(parsed?.messageBytes, utf8.encode('Hello 🐧'));
      expect(parsed?.contentType, 'text/markdown');
      expect(parsed?.click, 'https://example.com/details');
      expect(parsed?.icon, 'https://example.com/icon.png');
      expect(parsed?.actions.single.label, 'Open');
      expect(parsed?.actions.single.headers, {'X-Test': 'one'});

      for (final entry in const [
        ('message_clear', MessageEventType.clear),
        ('message_delete', MessageEventType.delete),
      ]) {
        final control = parseNtfyLine(
          jsonEncode({
            'event': entry.$1,
            'topic': 'alerts',
            'id': 'control',
            'sequence_id': 'deploy',
            'time': 1700000001,
          }),
          'https://ntfy.sh/alerts',
        );
        expect(control?.event, entry.$2);
        expect(control?.sequenceId, 'deploy');
        expect(control?.message, '');
      }
    },
  );

  test(
    'controller tolerates bad lines, dedupes, and reconnects from cursor',
    () async {
      final repository = _MemoryMessageRepository();
      final client = _SequenceClient([
        [
          '{bad',
          jsonEncode({'event': 'keepalive', 'topic': 'alerts'}),
          _line('one', 2, 'Later'),
          _line('one', 2, 'Duplicate'),
        ],
        [_line('two', 1, 'Earlier')],
      ]);
      final controller = TopicFeedController(
        repository: repository,
        subscription: const Subscription(id: 7, url: 'https://ntfy.sh/alerts'),
        client: client,
        retryDelays: const [Duration.zero],
      );
      addTearDown(controller.close);

      unawaited(controller.start());
      await _until(() => controller.state.messages.length == 2);

      expect(client.cursors.take(2), [null, 'one']);
      expect(controller.state.messages.map((message) => message.eventId), [
        'one',
        'two',
      ]);
      expect(repository.ingested.map((message) => message.message), [
        'Later',
        'Earlier',
      ]);

      final deleted = await controller.deleteMessage(
        controller.state.messages.first.localId,
      );
      expect(controller.state.messages.single.message, 'Earlier');

      await controller.restoreMessage(deleted!);
      expect(controller.state.messages.map((message) => message.message), [
        'Later',
        'Earlier',
      ]);

      final requestCount = client.cursors.length;
      await controller.clearMessages();
      expect(client.cursors, hasLength(requestCount));
      expect(controller.state.messages, isEmpty);
      expect(controller.state.cursor, 'two');
    },
  );

  test('empty successful streams continue bounded backoff', () async {
    final client = _EofClient();
    final controller = TopicFeedController(
      repository: _MemoryMessageRepository(),
      subscription: const Subscription(id: 7, url: 'https://ntfy.sh/alerts'),
      client: client,
      retryDelays: const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 200),
      ],
    );
    addTearDown(controller.close);

    unawaited(controller.start());
    await _until(() => client.connections == 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(client.connections, 2);
  });

  test('valid keepalive resets reconnect backoff', () async {
    final client = _SequenceClient([
      const [],
      [
        jsonEncode({'event': 'keepalive', 'topic': 'alerts'}),
      ],
      const [],
    ]);
    final controller = TopicFeedController(
      repository: _MemoryMessageRepository(),
      subscription: const Subscription(id: 7, url: 'https://ntfy.sh/alerts'),
      client: client,
      retryDelays: const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 200),
      ],
    );
    addTearDown(controller.close);

    unawaited(controller.start());
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(client.cursors.length, greaterThanOrEqualTo(3));
  });

  test(
    'duplicate ingestion reloads a message won by another runtime',
    () async {
      final repository = _DuplicateWinningRepository();
      final controller = TopicFeedController(
        repository: repository,
        subscription: const Subscription(id: 7, url: 'https://ntfy.sh/alerts'),
        client: _SequenceClient([
          [_line('shared', 1, 'Stored by background runtime')],
        ]),
        retryDelays: const [Duration(days: 1)],
      );
      addTearDown(controller.close);

      unawaited(controller.start());
      await _until(() => controller.state.messages.length == 1);

      expect(controller.state.messages.single.eventId, 'shared');
      expect(controller.state.cursor, 'shared');
    },
  );

  test('visible runtime alerts when it wins backgrounded ingestion', () async {
    final platform = _RecordingNotificationPlatform();
    final controller = TopicFeedController(
      repository: _MemoryMessageRepository(),
      subscription: const Subscription(id: 7, url: 'https://ntfy.sh/alerts'),
      client: _SequenceClient([
        [_line('winner', 1, 'Won by visible runtime')],
      ]),
      notifications: MessageNotificationSession(platform),
      retryDelays: const [Duration(days: 1)],
    );
    addTearDown(controller.close);

    unawaited(controller.start());
    await _until(() => platform.requests.length == 1);

    expect(platform.requests.single.eventId, 'winner');
  });

  test('refresh cannot resurrect a concurrently deleted message', () async {
    final repository = _DelayedLoadRepository()
      ..messages.add(
        StoredMessage(
          localId: 1,
          subscriptionId: 7,
          eventId: 'old',
          time: DateTime.utc(2026),
          message: 'Old',
        ),
      )
      ..cursor = 'old';
    final controller = TopicFeedController(
      repository: repository,
      subscription: const Subscription(id: 7, url: 'https://ntfy.sh/alerts'),
      client: _SequenceClient(const []),
      retryDelays: const [Duration.zero],
    );
    addTearDown(controller.close);
    unawaited(controller.start());
    await _until(() => controller.state.messages.length == 1);

    final refresh = controller.refreshLocalMessages();
    await repository.refreshStarted.future;
    final deletion = controller.deleteMessage(1);
    repository.releaseRefresh.complete();
    await Future.wait([refresh, deletion]);

    expect(controller.state.messages, isEmpty);
    expect(repository.messages, isEmpty);
    expect(controller.state.cursor, 'old');
  });
}

String _line(String id, int time, String message) => jsonEncode({
  'event': 'message',
  'topic': 'alerts',
  'id': id,
  'time': time,
  'message': message,
});

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _EofClient implements NtfyStreamClient {
  int connections = 0;

  @override
  Future<FeedConnection> connect({
    required String topicUrl,
    String? cursor,
  }) async {
    connections++;
    return FeedConnection(lines: const Stream.empty());
  }
}

class _MemoryPreferences implements PreferencesBackend {
  final values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }
}

class _MemorySecrets implements SecretBackend {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _RecordingNotificationPlatform implements NotificationPlatform {
  final requests = <MessageNotification>[];

  @override
  Stream<NotificationTarget> get taps => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<bool> show(MessageNotification notification) async {
    requests.add(notification);
    return true;
  }

  @override
  Future<bool> isSubscriptionVisible(int subscriptionId) async => false;

  @override
  Future<void> setVisibleSubscription(int? subscriptionId) async {}

  @override
  Future<void> close() async {}
}

class _SequenceClient implements NtfyStreamClient, AbortableNtfyStreamClient {
  _SequenceClient(this.responses);

  final List<List<String>> responses;
  final cursors = <String?>[];
  var index = 0;
  StreamController<String>? pending;

  @override
  Future<FeedConnection> connect({
    required String topicUrl,
    String? cursor,
  }) async {
    cursors.add(cursor);
    if (index < responses.length) {
      return FeedConnection(
        lines: Stream<String>.fromIterable(responses[index++]),
      );
    }
    pending = StreamController<String>();
    return FeedConnection(lines: pending!.stream, onClose: pending!.close);
  }

  @override
  Future<void> abort() async => pending?.close();
}

class _DuplicateWinningRepository extends _MemoryMessageRepository {
  @override
  Future<StoredMessage?> ingest(
    int subscriptionId,
    IncomingMessage message,
  ) async {
    if (messages.isEmpty) {
      messages.add(
        StoredMessage(
          localId: 1,
          subscriptionId: subscriptionId,
          eventId: message.eventId,
          time: message.time,
          message: message.message,
          title: message.title,
          priority: message.priority,
          tags: message.tags,
        ),
      );
      cursor = message.eventId;
    }
    return null;
  }
}

class _DelayedLoadRepository extends _MemoryMessageRepository {
  var loadCount = 0;
  final refreshStarted = Completer<void>();
  final releaseRefresh = Completer<void>();

  @override
  Future<FeedSnapshot> loadFeed(int subscriptionId) async {
    loadCount++;
    if (loadCount == 1) return super.loadFeed(subscriptionId);
    final snapshot = FeedSnapshot(messages: messages, cursor: cursor);
    refreshStarted.complete();
    await releaseRefresh.future;
    return snapshot;
  }
}

class _MemoryMessageRepository implements MessageRepository {
  final messages = <StoredMessage>[];
  final ingested = <IncomingMessage>[];
  String? cursor;

  @override
  Future<FeedSnapshot> loadFeed(int subscriptionId) async =>
      FeedSnapshot(messages: messages, cursor: cursor);

  @override
  Future<void> deleteMessage(int subscriptionId, int localId) async {
    messages.removeWhere((message) => message.localId == localId);
  }

  @override
  Future<void> restoreMessage(int subscriptionId, StoredMessage message) async {
    if (messages.every((stored) => stored.eventId != message.eventId)) {
      messages.add(message);
    }
  }

  @override
  Future<void> clearMessages(int subscriptionId) async => messages.clear();

  @override
  Future<StoredMessage?> ingest(
    int subscriptionId,
    IncomingMessage message,
  ) async {
    if (messages.any((stored) => stored.eventId == message.eventId)) {
      return null;
    }
    ingested.add(message);
    final stored = StoredMessage(
      localId: messages.length + 1,
      subscriptionId: subscriptionId,
      eventId: message.eventId,
      time: message.time,
      message: message.message,
      title: message.title,
      priority: message.priority,
      tags: message.tags,
    );
    messages.add(stored);
    cursor = message.eventId;
    return stored;
  }
}
