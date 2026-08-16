import 'dart:async';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app_database.dart';
import 'models.dart';
import 'notification_service.dart';
import 'ntfy_client.dart';

Duration reconnectDelay(int failures) {
  final exponent = failures < 0 ? 0 : (failures > 6 ? 6 : failures);
  return Duration(seconds: 1 << exponent);
}

bool isDeliveryReloadPayload(Object data) => data == 'reload';

@pragma('vm:entry-point')
void deliveryTaskCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(DeliveryTaskHandler());
}

class DeliveryService {
  static const _iconMetadata = 'dev.rahul.ntfy_flutter.DELIVERY_ICON';

  Future<void> Function()? _reload;

  void initialize() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ntfy_delivery',
        channelName: 'ntfy background delivery',
        channelDescription:
            'Shown while ntfy subscriptions are connected in the background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
  }

  void attach(Future<void> Function() reload) {
    _reload = reload;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  void detach() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _reload = null;
  }

  Future<void> ensureRunning() async {
    if (await FlutterForegroundTask.isRunningService) return;
    _throwIfFailure(await _start());
  }

  Future<void> startOrRestart() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    _throwIfFailure(
      isRunning ? await FlutterForegroundTask.restartService() : await _start(),
    );
  }

  Future<ServiceRequestResult> _start() => FlutterForegroundTask.startService(
    serviceId: 410,
    serviceTypes: const [ForegroundServiceTypes.specialUse],
    notificationTitle: 'ntfy delivery is active',
    notificationText: 'Listening for subscribed topics',
    notificationIcon: const NotificationIcon(metaDataName: _iconMetadata),
    callback: deliveryTaskCallback,
  );

  static void _throwIfFailure(ServiceRequestResult result) {
    if (result case ServiceRequestFailure(:final error)) throw error;
  }

  Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    final result = await FlutterForegroundTask.stopService();
    if (result case ServiceRequestFailure(:final error)) throw error;
  }

  void _onTaskData(Object data) {
    if (isDeliveryReloadPayload(data)) {
      final reload = _reload;
      if (reload != null) unawaited(reload());
    }
  }
}

class DeliveryTaskHandler extends TaskHandler {
  final AppDatabase _database = AppDatabase();
  final CredentialStore _credentials = CredentialStore();
  final NtfyClient _client = NtfyClient();
  final NotificationService _notifications = NotificationService();
  final Map<int, _SubscriptionConnection> _connections = {};

  Timer? _bootstrapTimer;
  Timer? _retentionTimer;
  int _bootstrapFailures = 0;
  bool _destroyed = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) => _bootstrap();

  Future<void> _bootstrap() async {
    try {
      await _database.initialize();
      await _notifications.initialize(readLaunchPayload: false);
      final deleted = await _database.deleteExpiredMessages();
      if (deleted.isNotEmpty) {
        FlutterForegroundTask.sendDataToMain('reload');
      }
      _retentionTimer ??= Timer.periodic(
        const Duration(minutes: 15),
        (_) => unawaited(_pruneExpired()),
      );
      final subscriptions = await _database.readSubscriptions();
      if (_destroyed) return;
      _bootstrapFailures = 0;
      for (final subscription in subscriptions) {
        final connection = _SubscriptionConnection(subscription.id);
        _connections[subscription.id] = connection;
        unawaited(_connect(connection));
      }
    } catch (_) {
      if (_destroyed) return;
      _bootstrapTimer = Timer(
        reconnectDelay(_bootstrapFailures++),
        () => unawaited(_bootstrap()),
      );
    }
  }

  Future<void> _connect(_SubscriptionConnection connection) async {
    if (_destroyed || connection.connecting) return;
    connection.connecting = true;
    connection.timer = null;
    try {
      final subscriptions = await _database.readSubscriptions();
      final subscription = subscriptions
          .where((item) => item.id == connection.subscriptionId)
          .firstOrNull;
      if (subscription == null || _destroyed) {
        _connections.remove(connection.subscriptionId);
        return;
      }
      final credential = await _credentials.read(subscription.baseUrl);
      if (_destroyed) return;
      connection.stream = _client
          .stream(
            subscription.baseUrl,
            subscription.topic,
            since: subscription.lastEventId ?? 'all',
            credential: credential,
          )
          .asyncMap((event) => _persist(subscription, event))
          .listen(
            (_) => connection.failures = 0,
            onError: (_) => _scheduleReconnect(connection),
            onDone: () => _scheduleReconnect(connection),
            cancelOnError: true,
          );
    } catch (_) {
      _scheduleReconnect(connection);
    } finally {
      connection.connecting = false;
    }
  }

  Future<void> _persist(Subscription subscription, NtfyEvent event) async {
    final inserted = await _database.applyEvents(subscription, [event]);
    final deleted = await _database.deleteExpiredMessages(
      subscriptionId: subscription.id,
    );
    for (final message in inserted) {
      if (!deleted.contains(message.id)) {
        await _notifications.showMessage(subscription, message);
      }
    }
    if (inserted.isNotEmpty || deleted.isNotEmpty) {
      FlutterForegroundTask.sendDataToMain('reload');
    }
  }

  Future<void> _pruneExpired() async {
    try {
      final deleted = await _database.deleteExpiredMessages();
      if (deleted.isNotEmpty) {
        FlutterForegroundTask.sendDataToMain('reload');
      }
    } catch (_) {
      // The next timer tick or incoming event retries retention cleanup.
    }
  }

  void _scheduleReconnect(_SubscriptionConnection connection) {
    if (_destroyed || connection.timer != null) return;
    final stream = connection.stream;
    connection.stream = null;
    if (stream != null) unawaited(stream.cancel());
    connection.timer = Timer(
      reconnectDelay(connection.failures++),
      () => unawaited(_connect(connection)),
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _destroyed = true;
    _bootstrapTimer?.cancel();
    _retentionTimer?.cancel();
    for (final connection in _connections.values) {
      connection.timer?.cancel();
      await connection.stream?.cancel();
    }
    _connections.clear();
    _client.close();
    // sqflite's single-instance connection is shared by both Flutter engines.
    // Closing it here during a service restart invalidates the UI's handle.
  }
}

class _SubscriptionConnection {
  _SubscriptionConnection(this.subscriptionId);

  final int subscriptionId;
  StreamSubscription<void>? stream;
  Timer? timer;
  int failures = 0;
  bool connecting = false;
}
