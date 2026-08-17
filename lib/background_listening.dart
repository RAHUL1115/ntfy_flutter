import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'retention.dart';
import 'subscriptions.dart';
import 'topic_feed.dart';

const _hostChannelName = 'com.rahul1115.ntfy_flutter/background_host';
const _runtimeChannelName = 'com.rahul1115.ntfy_flutter/background_runtime';

class BackgroundListeningSettings {
  const BackgroundListeningSettings({required this.enabled});

  final bool enabled;
}

class BackgroundListeningHostStatus {
  const BackgroundListeningHostStatus({
    required this.running,
    required this.notificationPresent,
  });

  final bool running;
  final bool notificationPresent;
}

abstract interface class BackgroundListeningHost {
  Future<void> startOrRefresh();

  Future<void> stop();

  Future<void> requestNotificationPermission();

  Future<void> openChannelSettings();

  Future<BackgroundListeningHostStatus> status();
}

class AndroidBackgroundListeningHost implements BackgroundListeningHost {
  const AndroidBackgroundListeningHost();

  static const _channel = MethodChannel(_hostChannelName);

  @override
  Future<void> startOrRefresh() => _channel.invokeMethod('startOrRefresh');

  @override
  Future<void> stop() => _channel.invokeMethod('stop');

  @override
  Future<void> requestNotificationPermission() =>
      _channel.invokeMethod('requestNotificationPermission');

  @override
  Future<void> openChannelSettings() =>
      _channel.invokeMethod('openChannelSettings');

  @override
  Future<BackgroundListeningHostStatus> status() async {
    final value = await _channel.invokeMapMethod<String, Object?>('status');
    return BackgroundListeningHostStatus(
      running: value?['running'] == true,
      notificationPresent: value?['notificationPresent'] == true,
    );
  }
}

sealed class BackgroundListeningCommand {
  const BackgroundListeningCommand();
}

final class SetBackgroundListening extends BackgroundListeningCommand {
  const SetBackgroundListening(this.enabled);

  final bool enabled;
}

final class RefreshBackgroundListener extends BackgroundListeningCommand {
  const RefreshBackgroundListener();
}

final class OpenBackgroundChannelSettings extends BackgroundListeningCommand {
  const OpenBackgroundChannelSettings();
}

class BackgroundListeningSession {
  BackgroundListeningSession(this._repository, this._host);

  final BackgroundListeningRepository _repository;
  final BackgroundListeningHost _host;
  Future<void> _commandTail = Future<void>.value();
  bool _started = false;

  Future<BackgroundListeningSettings> load() async =>
      BackgroundListeningSettings(
        enabled: await _repository.loadBackgroundListening(),
      );

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _serialize(() async {
        if (await _repository.loadBackgroundListening()) {
          await _host.startOrRefresh();
        }
      });
    } catch (_) {
      _started = false;
      rethrow;
    }
  }

  Future<void> execute(BackgroundListeningCommand command) =>
      _serialize(() async {
        switch (command) {
          case SetBackgroundListening(:final enabled):
            if (enabled) await _host.requestNotificationPermission();
            await _repository.setBackgroundListening(enabled);
            try {
              if (enabled) {
                await _host.startOrRefresh();
              } else {
                await _host.stop();
              }
            } catch (_) {
              if (enabled) {
                await _repository.setBackgroundListening(false);
              }
              rethrow;
            }
          case RefreshBackgroundListener():
            if (await _repository.loadBackgroundListening()) {
              await _host.startOrRefresh();
            }
          case OpenBackgroundChannelSettings():
            await _host.openChannelSettings();
        }
      });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _commandTail.then((_) => operation());
    _commandTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

typedef BackgroundStreamClientFactory = NtfyStreamClient Function(
  String serverKey,
);

const _backgroundRetryDelays = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 16),
  Duration(seconds: 30),
];

class BackgroundListenerRuntime {
  BackgroundListenerRuntime(
    this._repository, {
    BackgroundStreamClientFactory? clientFactory,
    RetentionSession? retention,
  }) : _clientFactory = clientFactory ?? ((_) => HttpNtfyStreamClient()),
       _retention = retention ?? RetentionSession(_repository);

  final AppRepository _repository;
  final BackgroundStreamClientFactory _clientFactory;
  final RetentionSession _retention;
  final _listeners = <(String, String?), _BackgroundServerListener>{};
  Future<void> _operationTail = Future<void>.value();
  bool _started = false;
  bool _closed = false;

  Future<bool> start() => _serialize(() async {
    if (_closed) return false;
    if (!_started) {
      _started = true;
      _retention.start();
    }
    return _refresh();
  });

  Future<bool> refresh() => _serialize(() async {
    if (_closed) return false;
    return _refresh();
  });

  Future<bool> _refresh() async {
    if (!await _repository.loadBackgroundListening()) {
      await _closeListeners();
      return false;
    }

    final grouped = <(String, String?), List<Subscription>>{};
    for (final subscription in await _repository.all()) {
      final snapshot = await _repository.loadFeed(subscription.id);
      final key = (_serverKey(subscription.url), snapshot.cursor);
      grouped.putIfAbsent(key, () => []).add(subscription);
    }

    for (final entry in _listeners.entries.toList()) {
      final desired = grouped[entry.key];
      if (desired == null || !entry.value.matches(desired)) {
        _listeners.remove(entry.key);
        await entry.value.close();
      }
    }
    for (final entry in grouped.entries) {
      if (_listeners.containsKey(entry.key)) continue;
      final listener = _BackgroundServerListener(
        repository: _repository,
        subscriptions: entry.value,
        client: _clientFactory(entry.key.$1),
        cursor: entry.key.$2,
      );
      _listeners[entry.key] = listener;
      unawaited(listener.start());
    }
    return _listeners.isNotEmpty;
  }

  Future<void> stop() => _serialize(() async {
    if (_closed) return;
    _closed = true;
    await _closeListeners();
    await _retention.close();
  });

  Future<void> _closeListeners() async {
    final listeners = _listeners.values.toList();
    _listeners.clear();
    await Future.wait(listeners.map((listener) => listener.close()));
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

class _BackgroundServerListener {
  _BackgroundServerListener({
    required this.repository,
    required List<Subscription> subscriptions,
    required this.client,
    required this._cursor,
  }) : subscriptions = List.unmodifiable(subscriptions),
       _subscriptionIds = subscriptions.map((item) => item.id).toSet(),
       _byTopic = {
         for (final subscription in subscriptions)
           _topicName(subscription.url): subscription,
       },
       topicUrl = _groupTopicUrl(subscriptions);

  final AppRepository repository;
  final List<Subscription> subscriptions;
  final NtfyStreamClient client;
  final Set<int> _subscriptionIds;
  final Map<String, Subscription> _byTopic;
  final String topicUrl;
  FeedConnection? _connection;
  Future<void>? _runFuture;
  Timer? _retryTimer;
  Completer<void>? _retryCompleter;
  bool _closed = false;
  int _retryIndex = 0;
  String? _cursor;

  bool matches(List<Subscription> desired) =>
      _subscriptionIds.length == desired.length &&
      desired.every((item) => _subscriptionIds.contains(item.id));

  Future<void> start() => _runFuture ??= _run();

  Future<void> _run() async {
    while (!_closed) {
      FeedConnection? connection;
      try {
        connection = await client.connect(topicUrl: topicUrl, cursor: _cursor);
        if (_closed) return;
        _connection = connection;
        await for (final line in connection.lines) {
          if (_closed) return;
          if (isNtfyProtocolLine(line)) _retryIndex = 0;
          final event = parseNtfyMessageEvent(line);
          final subscription = event == null ? null : _byTopic[event.topic];
          if (event == null || subscription == null) continue;
          final stored = await repository.ingest(
            subscription.id,
            event.message,
          );
          _cursor = event.message.eventId;
          if (stored != null) _retryIndex = 0;
        }
      } catch (_) {
        if (_closed) return;
      } finally {
        if (identical(_connection, connection)) _connection = null;
        try {
          await connection?.close();
        } catch (_) {
          // Closing a failed socket is best effort.
        }
      }
      if (!_closed) await _waitForRetry();
    }
  }

  Future<void> _waitForRetry() async {
    final delay =
        _backgroundRetryDelays[_retryIndex.clamp(
          0,
          _backgroundRetryDelays.length - 1,
        )];
    if (_retryIndex < _backgroundRetryDelays.length - 1) _retryIndex++;
    final completer = Completer<void>();
    _retryCompleter = completer;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    if (identical(_retryCompleter, completer)) _retryCompleter = null;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    final completer = _retryCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    _retryCompleter = null;
    try {
      await _connection?.close();
    } catch (_) {
      // Closing is best effort during cancellation.
    }
    if (client case final AbortableNtfyStreamClient abortable) {
      await abortable.abort();
    }
    await _runFuture;
  }
}

String _serverKey(String topicUrl) {
  final uri = Uri.parse(topicUrl);
  final parent = uri.pathSegments.sublist(0, uri.pathSegments.length - 1);
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: parent,
  ).toString();
}

String _groupTopicUrl(List<Subscription> subscriptions) {
  final first = Uri.parse(subscriptions.first.url);
  final parent = first.pathSegments.sublist(0, first.pathSegments.length - 1);
  final topics = subscriptions.map((item) => _topicName(item.url)).toList()
    ..sort();
  return Uri(
    scheme: first.scheme,
    host: first.host,
    port: first.hasPort ? first.port : null,
    pathSegments: [...parent, topics.join(',')],
  ).toString();
}

String _topicName(String topicUrl) => Uri.parse(topicUrl).pathSegments.last;

@pragma('vm:entry-point')
Future<void> backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  const channel = MethodChannel(_runtimeChannelName);

  try {
    final store = await SubscriptionStore.open();
    final runtime = BackgroundListenerRuntime(store);
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'refresh':
          return runtime.refresh();
        case 'stop':
          await runtime.stop();
          return true;
        default:
          throw MissingPluginException('Unknown method ${call.method}');
      }
    });
    final active = await runtime.start();
    await channel.invokeMethod('ready', active);
  } catch (error) {
    await channel.invokeMethod('failed', error.toString());
  }
}
