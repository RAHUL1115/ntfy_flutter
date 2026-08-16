import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';

int? parseSubscriptionPayload(String? payload) =>
    payload == null ? null : int.tryParse(payload);

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const messageChannel = AndroidNotificationChannel(
    'ntfy_messages',
    'ntfy messages',
    description: 'Notifications for newly received ntfy messages',
    importance: Importance.defaultImportance,
  );

  final FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _tapPayloads =
      StreamController<String>.broadcast(sync: true);
  String? _launchPayload;

  String? get launchPayload => _launchPayload;
  Stream<String> get tapPayloads => _tapPayloads.stream;

  String? takeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  Future<void> initialize({bool readLaunchPayload = true}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _tapPayloads.add(payload);
      },
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(messageChannel);
    if (readLaunchPayload) {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        _launchPayload = details?.notificationResponse?.payload;
      }
    }
  }

  Future<bool> requestPermission() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission() ??
      true;

  Future<void> showMessage(Subscription subscription, StoredMessage message) =>
      _plugin.show(
        id: message.id,
        title: message.title ?? subscription.displayNameOrTopic,
        body: message.message,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'ntfy_messages',
            'ntfy messages',
            channelDescription:
                'Notifications for newly received ntfy messages',
            icon: 'ic_notification',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        payload: subscription.id.toString(),
      );
}
