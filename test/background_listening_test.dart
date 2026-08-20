import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/app_settings.dart';
import 'package:ntfy_flutter/background_listening.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/notifications.dart';
import 'package:ntfy_flutter/retention.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:ntfy_flutter/topic_feed.dart';

void main() {
  test('saved server login delivers background notifications', () async {
    final expectedAuthorization =
        'Basic ${base64Encode(utf8.encode('rahul:secret'))}';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          expectedAuthorization) {
        request.response.statusCode = HttpStatus.forbidden;
      } else {
        request.response.headers.contentType = ContentType(
          'application',
          'x-ndjson',
          charset: 'utf-8',
        );
        request.response.writeln(
          jsonEncode({
            'event': 'message',
            'topic': 'alerts',
            'id': 'authenticated-message',
            'time': 1,
            'message': 'Private alert',
          }),
        );
      }
      await request.response.close();
    });
    final origin = 'http://${server.address.address}:${server.port}';
    final settings = AppSettingsStore(
      preferences: _MemoryPreferences(),
      secrets: _MemorySecrets(),
    );
    await settings.saveAccount(
      ServerAccount(baseUrl: origin, username: 'rahul', password: 'secret'),
    );
    final repository = _MemoryRepository()..enabled = true;
    final subscription = await repository.add(url: '$origin/alerts');
    final platform = _RecordingNotificationPlatform();
    final runtime = BackgroundListenerRuntime(
      repository,
      clientFactory: (_) => HttpNtfyStreamClient(profiles: settings),
      notifications: MessageNotificationSession(platform),
      retryDelays: const [Duration(days: 1)],
    );
    addTearDown(runtime.stop);

    expect(await runtime.start(), isTrue);
    await _until(() async => platform.requests.isNotEmpty);

    expect(platform.requests.single.subscriptionId, subscription.id);
    expect(platform.requests.single.body, 'Private alert');
  });

  test(
    'enabling and disabling persists intent and controls the host',
    () async {
      final repository = _MemoryRepository();
      final host = _RecordingHost();
      final session = BackgroundListeningSession(repository, host);

      expect((await session.load()).enabled, isFalse);

      await session.execute(const SetBackgroundListening(true));
      expect(repository.enabled, isTrue);
      expect(host.permissionRequests, 1);
      expect(host.starts, 1);

      await session.execute(const RefreshBackgroundListener());
      expect(host.starts, 2);

      await session.execute(const SetBackgroundListening(false));
      expect(repository.enabled, isFalse);
      expect(host.stops, 1);
    },
  );

  test('failed enable rolls the persisted setting back', () async {
    final repository = _MemoryRepository();
    final host = _RecordingHost(failStartCount: 1);
    final session = BackgroundListeningSession(repository, host);

    await expectLater(
      session.execute(const SetBackgroundListening(true)),
      throwsStateError,
    );

    expect(repository.enabled, isFalse);
    expect(host.starts, 1);
  });

  test('startup can retry after a host failure', () async {
    final repository = _MemoryRepository()..enabled = true;
    final host = _RecordingHost(failStartCount: 1);
    final session = BackgroundListeningSession(repository, host);

    await expectLater(session.start(), throwsStateError);
    await session.start();

    expect(host.starts, 2);
  });

  test('startup restores an enabled listener once', () async {
    final repository = _MemoryRepository()..enabled = true;
    final host = _RecordingHost();
    final session = BackgroundListeningSession(repository, host);

    await session.start();
    await session.start();

    expect(host.starts, 1);
  });

  test('runtime groups active subscriptions by server', () async {
    final repository = _MemoryRepository()..enabled = true;
    final first = await repository.add(url: 'https://ntfy.sh/first');
    await repository.add(url: 'https://ntfy.sh/second');
    final clients = <_HoldingClient>[];
    final runtime = BackgroundListenerRuntime(
      repository,
      clientFactory: (_) {
        final client = _HoldingClient();
        clients.add(client);
        return client;
      },
      retention: RetentionSession(
        repository,
        cleanupInterval: const Duration(days: 1),
      ),
    );

    expect(await runtime.start(), isTrue);
    await clients.single.connected.future;
    expect(clients.single.topicUrl, 'https://ntfy.sh/first,second');

    await repository.add(url: 'https://example.com/third');
    expect(await runtime.refresh(), isTrue);
    await clients.last.connected.future;
    expect(clients.where((client) => !client.closed), hasLength(2));

    await repository.remove(first.id);
    expect(await runtime.refresh(), isTrue);
    await clients.last.connected.future;
    expect(clients.first.closed, isTrue);
    expect(clients.where((client) => !client.closed), hasLength(2));
    expect(clients.last.topicUrl, 'https://ntfy.sh/second');

    await runtime.stop();
    expect(clients.every((client) => client.closed), isTrue);
  });

  test('runtime excludes topics with background delivery disabled', () async {
    final repository = _MemoryRepository()..enabled = true;
    final first = await repository.add(url: 'https://ntfy.sh/first');
    await repository.add(url: 'https://ntfy.sh/second');
    repository.setTopicBackgroundEnabled(first.id, false);
    late _HoldingClient client;
    final runtime = BackgroundListenerRuntime(
      repository,
      clientFactory: (_) => client = _HoldingClient(),
      retention: RetentionSession(
        repository,
        cleanupInterval: const Duration(days: 1),
      ),
    );

    expect(await runtime.start(), isTrue);
    await client.connected.future;
    expect(client.topicUrl, 'https://ntfy.sh/second');
    await runtime.stop();
  });

  test('UnifiedPush remains active and forwards exact message bytes', () async {
    final repository = _MemoryRepository();
    final subscription = repository.addUnifiedPush(
      url: 'https://ntfy.sh/upTopic',
      application: 'com.example.connector',
      token: 'connector-token',
    );
    final delivered = <(String, String, List<int>)>[];
    final notifications = _RecordingNotificationPlatform();
    late _HoldingClient client;
    final runtime = BackgroundListenerRuntime(
      repository,
      clientFactory: (_) => client = _HoldingClient(),
      notifications: MessageNotificationSession(notifications),
      unifiedPushMessage: (application, token, message) async {
        delivered.add((application, token, message));
      },
      retention: RetentionSession(
        repository,
        cleanupInterval: const Duration(days: 1),
      ),
    );

    expect(await runtime.start(), isTrue);
    await client.connected.future;
    client.add(
      jsonEncode({
        'event': 'message',
        'topic': 'upTopic',
        'id': 'up-message',
        'time': 1,
        'message': 'AAEC/w==',
        'encoding': 'base64',
      }),
    );
    await _until(() async => delivered.isNotEmpty);

    expect(delivered.single.$1, 'com.example.connector');
    expect(delivered.single.$2, 'connector-token');
    expect(delivered.single.$3, [0, 1, 2, 255]);
    expect(notifications.requests, isEmpty);
    expect((await repository.loadFeed(subscription.id)).messages, hasLength(1));
    await runtime.stop();
  });

  test('runtime reports aggregate connection state and removal', () async {
    final repository = _MemoryRepository()..enabled = true;
    await repository.add(url: 'https://ntfy.sh/first');
    final statuses = <BackgroundServerConnectionStatus>[];
    late _HoldingClient client;
    final runtime = BackgroundListenerRuntime(
      repository,
      clientFactory: (_) => client = _HoldingClient(),
      connectionStatusChanged: (status) async => statuses.add(status),
      retention: RetentionSession(
        repository,
        cleanupInterval: const Duration(days: 1),
      ),
    );

    await runtime.start();
    await client.connected.future;
    await _until(() async => statuses.length >= 2);
    expect(statuses.first.state, BackgroundConnectionState.connecting);
    expect(statuses[1].state, BackgroundConnectionState.connected);

    await runtime.stop();
    expect(statuses.last.error, '__removed__');
  });

  test('different per-topic cursors remain on safe separate streams', () async {
    final repository = _MemoryRepository()..enabled = true;
    final first = await repository.add(url: 'https://ntfy.sh/first');
    await repository.add(url: 'https://ntfy.sh/second');
    await repository.ingest(
      first.id,
      IncomingMessage(
        eventId: 'first-cursor',
        time: DateTime.utc(2026),
        message: 'Existing',
      ),
    );
    final clients = <_HoldingClient>[];
    final runtime = BackgroundListenerRuntime(
      repository,
      clientFactory: (_) {
        final client = _HoldingClient();
        clients.add(client);
        return client;
      },
      retention: RetentionSession(
        repository,
        cleanupInterval: const Duration(days: 1),
      ),
    );

    expect(await runtime.start(), isTrue);
    await Future.wait(clients.map((client) => client.connected.future));

    expect(
      clients.map((client) => client.topicUrl),
      containsAll(['https://ntfy.sh/first', 'https://ntfy.sh/second']),
    );
    await runtime.stop();
  });

  test('refresh retains a listener after its cursor advances', () async {
    final repository = _MemoryRepository()..enabled = true;
    final subscription = await repository.add(url: 'https://ntfy.sh/first');
    final clients = <_HoldingClient>[];
    final runtime = BackgroundListenerRuntime(
      repository,
      clientFactory: (_) {
        final client = _HoldingClient();
        clients.add(client);
        return client;
      },
      retention: RetentionSession(
        repository,
        cleanupInterval: const Duration(days: 1),
      ),
    );
    expect(await runtime.start(), isTrue);
    await clients.single.connected.future;
    clients.single.add(
      jsonEncode({
        'event': 'message',
        'topic': 'first',
        'id': 'advanced-cursor',
        'time': 1,
        'message': 'New',
      }),
    );
    await _until(
      () async =>
          (await repository.loadFeed(subscription.id)).messages.isNotEmpty,
    );

    expect(await runtime.refresh(), isTrue);
    expect(clients, hasLength(1));
    expect(clients.single.closed, isFalse);
    await runtime.stop();
  });

  test(
    'grouped stream routes each message through shared Dart ingestion',
    () async {
      final repository = _MemoryRepository()..enabled = true;
      final first = await repository.add(url: 'https://ntfy.sh/first');
      final second = await repository.add(url: 'https://ntfy.sh/second');
      late _HoldingClient client;
      final runtime = BackgroundListenerRuntime(
        repository,
        clientFactory: (_) => client = _HoldingClient(),
        retention: RetentionSession(
          repository,
          cleanupInterval: const Duration(days: 1),
        ),
      );

      expect(await runtime.start(), isTrue);
      await client.connected.future;
      client.add(
        jsonEncode({
          'event': 'message',
          'topic': 'first',
          'id': 'first-event',
          'time': 1,
          'message': 'First message',
        }),
      );
      client.add(
        jsonEncode({
          'event': 'message',
          'topic': 'second',
          'id': 'second-event',
          'time': 2,
          'message': 'Second message',
        }),
      );
      await _until(
        () async =>
            (await repository.loadFeed(first.id)).messages.length == 1 &&
            (await repository.loadFeed(second.id)).messages.length == 1,
      );

      expect(
        (await repository.loadFeed(first.id)).messages.single.message,
        'First message',
      );
      expect(
        (await repository.loadFeed(second.id)).messages.single.message,
        'Second message',
      );
      await runtime.stop();
    },
  );

  test('runtime alerts once only after a new insert', () async {
    final repository = _MemoryRepository()..enabled = true;
    final subscription = await repository.add(url: 'https://ntfy.sh/alerts');
    final platform = _RecordingNotificationPlatform();
    late _HoldingClient client;
    final runtime = BackgroundListenerRuntime(
      repository,
      clientFactory: (_) => client = _HoldingClient(),
      notifications: MessageNotificationSession(platform),
    );

    expect(await runtime.start(), isTrue);
    await client.connected.future;
    final line = jsonEncode({
      'event': 'message',
      'topic': 'alerts',
      'id': 'same-event',
      'time': 1,
      'message': 'Only once',
    });
    client
      ..add(line)
      ..add(line);
    await _until(() async => platform.requests.length == 1);

    expect((await repository.loadFeed(subscription.id)).messages, hasLength(1));
    expect(platform.requests.single.eventId, 'same-event');
    await runtime.stop();
  });

  test(
    'network reconnect replaces listeners without duplicate alerts',
    () async {
      final repository = _MemoryRepository()..enabled = true;
      final subscription = await repository.add(url: 'https://ntfy.sh/alerts');
      final platform = _RecordingNotificationPlatform();
      final clients = <_HoldingClient>[];
      final runtime = BackgroundListenerRuntime(
        repository,
        clientFactory: (_) {
          final client = _HoldingClient();
          clients.add(client);
          return client;
        },
        notifications: MessageNotificationSession(platform),
        retryDelays: const [Duration.zero],
      );
      final line = jsonEncode({
        'event': 'message',
        'topic': 'alerts',
        'id': 'same-event',
        'time': 1,
        'message': 'Only once across networks',
      });

      expect(await runtime.start(), isTrue);
      await clients.single.connected.future;
      clients.single.add(line);
      await _until(() async => platform.requests.length == 1);

      expect(await runtime.reconnect(), isTrue);
      await clients.last.connected.future;
      expect(clients, hasLength(2));
      expect(clients.first.closed, isTrue);
      expect(clients.where((client) => !client.closed), hasLength(1));

      clients.last.add(line);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        (await repository.loadFeed(subscription.id)).messages,
        hasLength(1),
      );
      expect(platform.requests, hasLength(1));
      await runtime.stop();
    },
  );

  test('denied notifications do not stop background history', () async {
    final repository = _MemoryRepository()..enabled = true;
    final subscription = await repository.add(url: 'https://ntfy.sh/alerts');
    final platform = _RecordingNotificationPlatform()..allowPosting = false;
    late _HoldingClient client;
    final runtime = BackgroundListenerRuntime(
      repository,
      clientFactory: (_) => client = _HoldingClient(),
      notifications: MessageNotificationSession(platform),
    );

    expect(await runtime.start(), isTrue);
    await client.connected.future;
    for (var index = 0; index < 2; index++) {
      client.add(
        jsonEncode({
          'event': 'message',
          'topic': 'alerts',
          'id': 'denied-$index',
          'time': index + 1,
          'message': 'Stored $index',
        }),
      );
    }
    await _until(
      () async =>
          (await repository.loadFeed(subscription.id)).messages.length == 2,
    );

    expect(platform.requests, hasLength(2));
    await runtime.stop();
  });

  test('runtime stays idle when there are no subscriptions', () async {
    final repository = _MemoryRepository()..enabled = true;
    final runtime = BackgroundListenerRuntime(repository);

    expect(await runtime.start(), isFalse);
    await runtime.stop();
  });

  test(
    'reconnect scheduling keeps working with exact alarms allowed or denied',
    () async {
      for (final allowed in [true, false]) {
        final repository = _MemoryRepository()..enabled = true;
        await repository.add(url: 'https://ntfy.sh/alerts');
        final scheduler = _RecordingReconnectScheduler(allowed);
        late _HoldingClient client;
        final runtime = BackgroundListenerRuntime(
          repository,
          clientFactory: (_) => client = _HoldingClient(),
          reconnectScheduler: scheduler,
          retryDelays: const [Duration(hours: 1)],
        );

        expect(await runtime.start(), isTrue);
        await client.connected.future;
        await client.abort();
        await _until(() async => scheduler.scheduled == 1);
        expect(scheduler.results, [allowed]);
        await runtime.stop();
        expect(scheduler.cancelled, greaterThanOrEqualTo(1));
      }
    },
  );

  test(
    'connection alerts wait for the setting and cancel on recovery',
    () async {
      final platform = _RecordingConnectionAlertPlatform();
      final gate = Completer<void>();
      Duration? requestedDelay;
      final session = ConnectionAlertSession(
        loadThresholdSeconds: () async => 300,
        platform: platform,
        delay: (duration) {
          requestedDelay = duration;
          return gate.future;
        },
      );

      final pending = session.disconnected('https://example.com');
      await Future<void>.delayed(Duration.zero);
      expect(requestedDelay, const Duration(minutes: 5));
      await session.connected('https://example.com');
      gate.complete();
      await pending;
      expect(platform.shown, isEmpty);

      final immediate = ConnectionAlertSession(
        loadThresholdSeconds: () async => 900,
        platform: platform,
        delay: (_) async {},
      );
      await immediate.disconnected('https://example.com');
      expect(platform.shown.single, ('https://example.com', 900));
      await immediate.close();
    },
  );
}

class _RecordingConnectionAlertPlatform implements ConnectionAlertPlatform {
  final shown = <(String, int)>[];
  int clears = 0;

  @override
  Future<void> show(String server, int thresholdSeconds) async {
    shown.add((server, thresholdSeconds));
  }

  @override
  Future<void> clear() async => clears++;
}

class _RecordingReconnectScheduler implements ReconnectScheduler {
  _RecordingReconnectScheduler(this.allowed);

  final bool allowed;
  int scheduled = 0;
  int cancelled = 0;
  final results = <bool>[];

  @override
  Future<bool> schedule(Object listener, DateTime when) async {
    scheduled++;
    results.add(allowed);
    return allowed;
  }

  @override
  Future<void> cancel(Object listener) async => cancelled++;
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

class _RecordingHost implements BackgroundListeningHost {
  _RecordingHost({int failStartCount = 0}) : failuresRemaining = failStartCount;

  int failuresRemaining;
  int starts = 0;
  int stops = 0;
  int permissionRequests = 0;
  int channelSettingsOpens = 0;

  @override
  Future<void> startOrRefresh() async {
    starts++;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('start failed');
    }
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> requestNotificationPermission() async => permissionRequests++;

  @override
  Future<void> openChannelSettings() async => channelSettingsOpens++;

  @override
  Future<BackgroundListeningHostStatus> status() async =>
      const BackgroundListeningHostStatus(
        running: false,
        notificationPresent: false,
      );
}

class _RecordingNotificationPlatform implements NotificationPlatform {
  final requests = <MessageNotification>[];
  bool allowPosting = true;

  @override
  Stream<NotificationTarget> get taps => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<bool> show(MessageNotification notification) async {
    requests.add(notification);
    return allowPosting;
  }

  @override
  Future<bool> isSubscriptionVisible(int subscriptionId) async => false;

  @override
  Future<void> setVisibleSubscription(int? subscriptionId) async {}

  @override
  Future<void> close() async {}
}

class _HoldingClient implements NtfyStreamClient, AbortableNtfyStreamClient {
  final connected = Completer<void>();
  final _lines = StreamController<String>();
  int connections = 0;
  bool closed = false;
  String? topicUrl;

  @override
  Future<FeedConnection> connect({
    required String topicUrl,
    String? cursor,
  }) async {
    this.topicUrl = topicUrl;
    connections++;
    if (!connected.isCompleted) connected.complete();
    return FeedConnection(lines: _lines.stream, onClose: abort);
  }

  void add(String line) => _lines.add(line);

  @override
  Future<void> abort() async {
    if (closed) return;
    closed = true;
    await _lines.close();
  }
}

class _MemoryRepository implements AppRepository {
  bool enabled = false;
  var _nextId = 1;
  final _subscriptions = <Subscription>[];
  final _feeds = <int, FeedSnapshot>{};
  RetentionPeriod retention = RetentionPeriod.never;

  @override
  Future<bool> loadBackgroundListening() async => enabled;

  @override
  Future<void> setBackgroundListening(bool value) async => enabled = value;

  @override
  Future<Subscription> add({required String url, String? displayName}) async {
    final subscription = Subscription(
      id: _nextId++,
      url: url,
      displayName: displayName,
    );
    _subscriptions.add(subscription);
    _feeds[subscription.id] = FeedSnapshot(messages: const []);
    return subscription;
  }

  Subscription addUnifiedPush({
    required String url,
    required String application,
    required String token,
  }) {
    final subscription = Subscription(
      id: _nextId++,
      url: url,
      unifiedPushApp: application,
      unifiedPushToken: token,
    );
    _subscriptions.add(subscription);
    _feeds[subscription.id] = FeedSnapshot(messages: const []);
    return subscription;
  }

  @override
  Future<List<Subscription>> all() async => List.of(_subscriptions);

  void setTopicBackgroundEnabled(int subscriptionId, bool enabled) {
    final index = _subscriptions.indexWhere(
      (item) => item.id == subscriptionId,
    );
    final current = _subscriptions[index];
    _subscriptions[index] = Subscription(
      id: current.id,
      url: current.url,
      displayName: current.displayName,
      backgroundEnabled: enabled,
      unifiedPushApp: current.unifiedPushApp,
      unifiedPushToken: current.unifiedPushToken,
    );
  }

  @override
  Future<void> markRead(int subscriptionId) async {}

  @override
  Future<Subscription> rename(int subscriptionId, String? displayName) async {
    final index = _subscriptions.indexWhere(
      (item) => item.id == subscriptionId,
    );
    final current = _subscriptions[index];
    final renamed = Subscription(
      id: current.id,
      url: current.url,
      displayName: displayName?.trim().isEmpty == true
          ? null
          : displayName?.trim(),
      unreadCount: current.unreadCount,
      totalCount: current.totalCount,
      lastActivity: current.lastActivity,
      backgroundEnabled: current.backgroundEnabled,
      unifiedPushApp: current.unifiedPushApp,
      unifiedPushToken: current.unifiedPushToken,
    );
    _subscriptions[index] = renamed;
    return renamed;
  }

  @override
  Future<void> remove(int subscriptionId) async {
    _subscriptions.removeWhere((item) => item.id == subscriptionId);
    _feeds.remove(subscriptionId);
  }

  @override
  Future<FeedSnapshot> loadFeed(int subscriptionId) async =>
      _feeds[subscriptionId] ??
      (throw StateError('Subscription $subscriptionId does not exist.'));

  @override
  Future<StoredMessage?> ingest(
    int subscriptionId,
    IncomingMessage message,
  ) async {
    final snapshot = await loadFeed(subscriptionId);
    if (snapshot.messages.any((stored) => stored.eventId == message.eventId)) {
      return null;
    }
    final stored = StoredMessage(
      localId: snapshot.messages.length + 1,
      subscriptionId: subscriptionId,
      eventId: message.eventId,
      time: message.time,
      message: message.message,
      title: message.title,
      priority: message.priority,
      tags: message.tags,
    );
    _feeds[subscriptionId] = FeedSnapshot(
      messages: [...snapshot.messages, stored],
      cursor: stored.eventId,
    );
    return stored;
  }

  @override
  Future<void> deleteMessage(int subscriptionId, int localId) async {}

  @override
  Future<void> restoreMessage(
    int subscriptionId,
    StoredMessage message,
  ) async {}

  @override
  Future<void> clearMessages(int subscriptionId) async {}

  @override
  Future<RetentionSettings> loadRetention({int? subscriptionId}) async =>
      RetentionSettings(global: retention);

  @override
  Future<void> executeRetention(RetentionCommand command) async {}
}

Future<void> _until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
