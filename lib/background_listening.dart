import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/services.dart';

import 'attachments.dart';
import 'app_settings.dart';
import 'messages.dart';

import 'package:flutter/widgets.dart';

import 'retention.dart';
import 'notifications.dart';
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
    this.notificationsAllowed = true,
    this.messageNotifications = const [],
    this.connections = const [],
  });

  final bool running;
  final bool notificationPresent;
  final bool notificationsAllowed;
  final List<MessageNotificationStatus> messageNotifications;
  final List<BackgroundServerConnectionStatus> connections;
}

enum BackgroundConnectionState { connecting, connected }

class BackgroundServerConnectionStatus {
  const BackgroundServerConnectionStatus({
    required this.server,
    required this.state,
    this.error,
    this.nextRetryEpochMilliseconds,
  });

  final String server;
  final BackgroundConnectionState state;
  final String? error;
  final int? nextRetryEpochMilliseconds;

  Map<String, Object?> toJson() => {
    'server': server,
    'state': state.name,
    'error': error,
    'nextRetryEpochMilliseconds': nextRetryEpochMilliseconds,
  };

  @override
  bool operator ==(Object other) =>
      other is BackgroundServerConnectionStatus &&
      other.server == server &&
      other.state == state &&
      other.error == error &&
      other.nextRetryEpochMilliseconds == nextRetryEpochMilliseconds;

  @override
  int get hashCode =>
      Object.hash(server, state, error, nextRetryEpochMilliseconds);
}

class MessageNotificationStatus {
  const MessageNotificationStatus({
    required this.subscriptionId,
    required this.eventId,
    required this.channelId,
  });

  final int subscriptionId;
  final String eventId;
  final String channelId;
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
    final notifications = value?['messageNotifications'];
    final connections = value?['connections'];
    return BackgroundListeningHostStatus(
      running: value?['running'] == true,
      notificationPresent: value?['notificationPresent'] == true,
      notificationsAllowed: value?['notificationsAllowed'] != false,
      messageNotifications: notifications is List
          ? notifications
                .map((item) {
                  if (item is! Map) return null;
                  final subscriptionId = item['subscriptionId'];
                  final eventId = item['eventId'];
                  final channelId = item['channelId'];
                  if (subscriptionId is! int ||
                      eventId is! String ||
                      channelId is! String) {
                    return null;
                  }
                  return MessageNotificationStatus(
                    subscriptionId: subscriptionId,
                    eventId: eventId,
                    channelId: channelId,
                  );
                })
                .whereType<MessageNotificationStatus>()
                .toList()
          : const [],
      connections: connections is List
          ? connections
                .map((item) {
                  if (item is! Map || item['server'] is! String) return null;
                  final state = BackgroundConnectionState.values
                      .where((value) => value.name == item['state'])
                      .firstOrNull;
                  if (state == null) return null;
                  return BackgroundServerConnectionStatus(
                    server: item['server']! as String,
                    state: state,
                    error: item['error'] as String?,
                    nextRetryEpochMilliseconds:
                        item['nextRetryEpochMilliseconds'] as int?,
                  );
                })
                .whereType<BackgroundServerConnectionStatus>()
                .toList()
          : const [],
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

  Future<BackgroundListeningHostStatus> status() => _host.status();

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

class ConnectionAlertSession {
  ConnectionAlertSession({
    required this.loadThresholdSeconds,
    required this.platform,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final Future<int> Function() loadThresholdSeconds;
  final ConnectionAlertPlatform platform;
  final Future<void> Function(Duration) _delay;
  final _episodes = <String, Object>{};
  bool _closed = false;

  Future<void> disconnected(String server) async {
    if (_closed || _episodes.containsKey(server)) return;
    final threshold = await loadThresholdSeconds();
    if (_closed || threshold <= 0) return;
    final episode = Object();
    _episodes[server] = episode;
    await _delay(Duration(seconds: threshold));
    if (_closed || !identical(_episodes[server], episode)) return;
    await platform.show(server, threshold);
  }

  Future<void> connected(String server) async {
    if (_episodes.remove(server) != null && _episodes.isEmpty) {
      await platform.clear();
    }
  }

  Future<void> close() async {
    _closed = true;
    _episodes.clear();
    await platform.clear();
  }
}

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
    this.notifications,
    this.attachments,
    this.connectionAlerts,
    this.connectionStatusChanged,
    this.unifiedPushMessage,
    RetentionSession? retention,
    List<Duration>? retryDelays,
  }) : assert(retryDelays == null || retryDelays.isNotEmpty),
       _clientFactory = clientFactory ?? ((_) => HttpNtfyStreamClient()),
       _retention = retention ?? RetentionSession(_repository),
       _retryDelays = List.unmodifiable(retryDelays ?? _backgroundRetryDelays);

  final AppRepository _repository;
  final BackgroundStreamClientFactory _clientFactory;
  final MessageNotificationSession? notifications;
  final AttachmentAutoDownloader? attachments;
  final ConnectionAlertSession? connectionAlerts;
  final Future<void> Function(BackgroundServerConnectionStatus status)?
  connectionStatusChanged;
  final Future<void> Function(
    String application,
    String token,
    List<int> message,
  )?
  unifiedPushMessage;
  final RetentionSession _retention;
  final List<Duration> _retryDelays;
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

  Future<bool> reconnect() => _serialize(() async {
    if (_closed) return false;
    await _closeListeners();
    return _refresh();
  });

  Future<bool> _refresh() async {
    final regularListening = await _repository.loadBackgroundListening();

    final byCursor = <(String, String?), List<Subscription>>{};
    for (final subscription in await _repository.all()) {
      if (!regularListening && subscription.unifiedPushApp == null) continue;
      if (!subscription.backgroundEnabled) continue;
      final snapshot = await _repository.loadFeed(subscription.id);
      byCursor
          .putIfAbsent((
            _serverKey(subscription.url),
            snapshot.cursor,
          ), () => [])
          .add(subscription);
    }
    final grouped =
        <
          (String, String),
          ({List<Subscription> subscriptions, String? cursor})
        >{};
    for (final entry in byCursor.entries) {
      final subscriptions = entry.value.toList()
        ..sort((left, right) => left.id.compareTo(right.id));
      final ids = subscriptions.map((item) => item.id).join(',');
      grouped[(entry.key.$1, ids)] = (
        subscriptions: subscriptions,
        cursor: entry.key.$2,
      );
    }

    for (final entry in _listeners.entries.toList()) {
      final desired = grouped[entry.key];
      if (desired == null || !entry.value.matches(desired.subscriptions)) {
        _listeners.remove(entry.key);
        await entry.value.close();
      }
    }
    for (final entry in grouped.entries) {
      if (_listeners.containsKey(entry.key)) continue;
      final listener = _BackgroundServerListener(
        repository: _repository,
        subscriptions: entry.value.subscriptions,
        client: _clientFactory(entry.key.$1),
        cursor: entry.value.cursor,
        notifications: notifications,
        attachments: attachments,
        connectionAlerts: connectionAlerts,
        connectionStatusChanged: connectionStatusChanged,
        unifiedPushMessage: unifiedPushMessage,
        retryDelays: _retryDelays,
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
    await connectionAlerts?.close();
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
    required this.notifications,
    required this.attachments,
    required this.connectionAlerts,
    required this.connectionStatusChanged,
    required this.unifiedPushMessage,
    required this.retryDelays,
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
  final MessageNotificationSession? notifications;
  final AttachmentAutoDownloader? attachments;
  final ConnectionAlertSession? connectionAlerts;
  final Future<void> Function(BackgroundServerConnectionStatus status)?
  connectionStatusChanged;
  final Future<void> Function(
    String application,
    String token,
    List<int> message,
  )?
  unifiedPushMessage;
  final List<Duration> retryDelays;
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
    final server = _serverKey(topicUrl);
    while (!_closed) {
      FeedConnection? connection;
      Object? failure;
      try {
        await connectionStatusChanged?.call(
          BackgroundServerConnectionStatus(
            server: server,
            state: BackgroundConnectionState.connecting,
          ),
        );
        connection = await client.connect(topicUrl: topicUrl, cursor: _cursor);
        if (_closed) return;
        await connectionAlerts?.connected(server);
        await connectionStatusChanged?.call(
          BackgroundServerConnectionStatus(
            server: server,
            state: BackgroundConnectionState.connected,
          ),
        );
        _connection = connection;
        await for (final line in connection.lines) {
          if (_closed) return;
          if (isNtfyProtocolLine(line)) _retryIndex = 0;
          final event = parseNtfyMessageEvent(line);
          final subscription = event == null ? null : _byTopic[event.topic];
          if (event == null || subscription == null) continue;
          var stored = await repository.ingest(subscription.id, event.message);
          _cursor = event.message.eventId;
          if (event.message.event != MessageEventType.message) {
            await notifications?.handleControl(subscription, event.message);
          }
          if (stored != null) {
            _retryIndex = 0;
            final application = subscription.unifiedPushApp;
            final token = subscription.unifiedPushToken;
            if (application != null && token != null) {
              await unifiedPushMessage?.call(
                application,
                token,
                event.message.messageBytes,
              );
            } else {
              await notifications?.show(subscription, stored);
              final downloader = attachments;
              if (downloader != null) {
                unawaited(downloader.process(subscription, stored));
              }
            }
          }
        }
      } catch (error) {
        failure = error;
        if (_closed) return;
      } finally {
        if (identical(_connection, connection)) _connection = null;
        try {
          await connection?.close();
        } catch (_) {
          // Closing a failed socket is best effort.
        }
      }
      if (!_closed) {
        unawaited(connectionAlerts?.disconnected(server));
        final delay = retryDelays[_retryIndex.clamp(0, retryDelays.length - 1)];
        await connectionStatusChanged?.call(
          BackgroundServerConnectionStatus(
            server: server,
            state: BackgroundConnectionState.connecting,
            error: failure?.toString() ?? 'Connection closed.',
            nextRetryEpochMilliseconds: DateTime.now()
                .add(delay)
                .millisecondsSinceEpoch,
          ),
        );
        await _waitForRetry();
      }
    }
  }

  Future<void> _waitForRetry() async {
    final delay = retryDelays[_retryIndex.clamp(0, retryDelays.length - 1)];
    if (_retryIndex < retryDelays.length - 1) _retryIndex++;
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
    await connectionAlerts?.connected(_serverKey(topicUrl));
    await connectionStatusChanged?.call(
      BackgroundServerConnectionStatus(
        server: _serverKey(topicUrl),
        state: BackgroundConnectionState.connected,
        error: '__removed__',
      ),
    );
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
    final settings = await AppSettingsStore.open();
    late final BackgroundListenerRuntime runtime;
    runtime = BackgroundListenerRuntime(
      store,
      clientFactory: (_) => HttpNtfyStreamClient(profiles: settings),
      notifications: MessageNotificationSession(
        AndroidNotificationPlatform(),
        policies: store,
        broadcastsEnabled: () async =>
            (await settings.loadSettings()).broadcastsEnabled,
        iconLoader: (uri) =>
            AttachmentService(profiles: settings)
                .fetchBytes(uri, maxBytes: 1024 * 1024),
      ),
      attachments: AttachmentAutoDownloader(
        policies: store,
        repository: store,
        service: AttachmentService(profiles: settings),
      ),
      connectionAlerts: ConnectionAlertSession(
        loadThresholdSeconds: () async =>
            (await settings.loadSettings()).connectionAlertSeconds,
        platform: const AndroidConnectionAlertPlatform(),
      ),
      connectionStatusChanged: (status) =>
          channel.invokeMethod('connectionState', status.toJson()),
      unifiedPushMessage: (application, token, message) => channel.invokeMethod(
        'unifiedPushMessage',
        {'application': application, 'token': token, 'message': message},
      ),
    );
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'refresh':
          return runtime.refresh();
        case 'reconnect':
          return runtime.reconnect();
        case 'stop':
          await runtime.stop();
          return true;
        case 'unifiedPushRegister':
          final arguments = Map<String, Object?>.from(call.arguments as Map);
          final registration = await store.registerUnifiedPush(
            application: arguments['application']! as String,
            token: arguments['token']! as String,
            baseUrl: (await settings.loadSettings()).defaultServer,
          );
          final active = await runtime.refresh();
          return {
            'application': registration.application,
            'token': registration.token,
            'endpoint': registration.endpoint,
            'active': active,
          };
        case 'unifiedPushUnregister':
          final arguments = Map<String, Object?>.from(call.arguments as Map);
          final registration = await store.unregisterUnifiedPush(
            arguments['token']! as String,
          );
          final active = await runtime.refresh();
          return registration == null
              ? {'active': active}
              : {
                  'application': registration.application,
                  'token': registration.token,
                  'active': active,
                };
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
