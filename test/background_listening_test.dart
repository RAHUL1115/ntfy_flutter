import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/background_listening.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/retention.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:ntfy_flutter/topic_feed.dart';

void main() {
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

  test('runtime stays idle when there are no subscriptions', () async {
    final repository = _MemoryRepository()..enabled = true;
    final runtime = BackgroundListenerRuntime(repository);

    expect(await runtime.start(), isFalse);
    await runtime.stop();
  });
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

  @override
  Future<List<Subscription>> all() async => List.of(_subscriptions);

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
