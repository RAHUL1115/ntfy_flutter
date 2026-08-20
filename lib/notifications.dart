import 'dart:async';

import 'package:flutter/services.dart';

import 'messages.dart';
import 'emojis.dart';
import 'notification_policy.dart';
import 'subscriptions.dart';

const notificationChannelName =
    'com.rahul1115.ntfy_flutter/message_notifications';

enum NotificationPriority { min, low, normal, high, max }

class FullScreenAlertSettings {
  const FullScreenAlertSettings({required this.enabled, required this.tags});

  final bool enabled;
  final List<String> tags;
}

List<String> normalizeFullScreenAlertTags(Iterable<String> tags) => tags
    .map((tag) => tag.trim().toLowerCase())
    .where((tag) => tag.isNotEmpty)
    .toSet()
    .toList(growable: false);

bool matchesFullScreenAlertTags(
  Iterable<String> messageTags,
  Iterable<String> selectedTags,
) {
  final selected = normalizeFullScreenAlertTags(selectedTags).toSet();
  return selected.isNotEmpty &&
      normalizeFullScreenAlertTags(messageTags).any(selected.contains);
}

class MessageNotification {
  const MessageNotification({
    required this.id,
    required this.subscriptionId,
    required this.eventId,
    String? sequenceId,
    required this.title,
    required this.body,
    required this.priority,
    required this.timestamp,
    this.insistent = false,
    this.fullScreenEligible = false,
    this.iconPath,
    this.channelId,
    this.channelName,
    this.click,
    this.iconUrl,
    this.iconBytes,
    this.actions = const [],
    this.contentType,
    this.encoding,
    this.messageBytes = const [],
  }) : sequenceId = sequenceId ?? eventId;

  final int id;
  final int subscriptionId;
  final String eventId;
  final String sequenceId;
  final String title;
  final String body;
  final NotificationPriority priority;
  final DateTime timestamp;
  final bool insistent;
  final bool fullScreenEligible;
  final String? iconPath;
  final String? channelId;
  final String? channelName;
  final String? click;
  final String? iconUrl;
  final Uint8List? iconBytes;
  final List<MessageAction> actions;
  final String? contentType;
  final String? encoding;
  final List<int> messageBytes;

  Map<String, Object> toMap() => {
    'id': id,
    'subscriptionId': subscriptionId,
    'eventId': eventId,
    'sequenceId': sequenceId,
    'title': title,
    'body': body,
    'priority': priority.name,
    'timestamp': timestamp.toUtc().millisecondsSinceEpoch,
    'insistent': insistent,
    'fullScreenEligible': fullScreenEligible,
    'iconPath': ?iconPath,
    'channelId': ?channelId,
    'channelName': ?channelName,
    'click': ?click,
    'iconUrl': ?iconUrl,
    'iconBytes': ?iconBytes,
    'actions': actions.map((action) => action.toJson()).toList(),
    'contentType': contentType ?? '',
    'encoding': encoding ?? '',
    'messageBytes': Uint8List.fromList(messageBytes),
  };
}

class NotificationTarget {
  const NotificationTarget({
    required this.subscriptionId,
    required this.eventId,
  });

  final int subscriptionId;
  final String eventId;

  static NotificationTarget? fromMap(Object? value) {
    if (value is! Map) return null;
    final subscriptionId = value['subscriptionId'];
    final eventId = value['eventId'];
    if (subscriptionId is! int || eventId is! String || eventId.isEmpty) {
      return null;
    }
    return NotificationTarget(subscriptionId: subscriptionId, eventId: eventId);
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationTarget &&
      subscriptionId == other.subscriptionId &&
      eventId == other.eventId;

  @override
  int get hashCode => Object.hash(subscriptionId, eventId);
}

abstract interface class NotificationPlatform {
  Stream<NotificationTarget> get taps;

  Future<void> start();

  Future<bool> show(MessageNotification notification);

  Future<bool> isSubscriptionVisible(int subscriptionId);

  Future<void> setVisibleSubscription(int? subscriptionId);

  Future<void> close();
}

abstract interface class MessageBroadcastPlatform {
  Future<void> broadcast(
    Subscription subscription,
    StoredMessage message, {
    required bool muted,
  });
}

abstract interface class NotificationControlPlatform {
  Future<void> cancel(int subscriptionId, String sequenceId);
}

class AndroidNotificationPlatform
    implements
        NotificationPlatform,
        MessageBroadcastPlatform,
        NotificationControlPlatform {
  AndroidNotificationPlatform();

  static const _channel = MethodChannel(notificationChannelName);
  final _taps = StreamController<NotificationTarget>.broadcast();
  Future<void> _drainTail = Future<void>.value();
  bool _started = false;

  @override
  Stream<NotificationTarget> get taps => _taps.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'notificationTapAvailable') {
        throw MissingPluginException('Unknown method ${call.method}');
      }
      await _drainTaps();
    });
    await _drainTaps();
  }

  Future<void> _drainTaps() {
    final result = _drainTail.then((_) async {
      while (true) {
        final value = await _channel.invokeMethod<Object?>(
          'takeNotificationTap',
        );
        final target = NotificationTarget.fromMap(value);
        if (target == null) return;
        _taps.add(target);
      }
    });
    _drainTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  @override
  Future<bool> show(MessageNotification notification) async =>
      await _channel.invokeMethod<bool>(
        'showNotification',
        notification.toMap(),
      ) ??
      false;

  @override
  Future<void> cancel(int subscriptionId, String sequenceId) =>
      _channel.invokeMethod('cancelNotification', {
        'subscriptionId': subscriptionId,
        'sequenceId': sequenceId,
      });

  @override
  Future<void> broadcast(
    Subscription subscription,
    StoredMessage message, {
    required bool muted,
  }) => _channel.invokeMethod('broadcastMessage', {
    'id': message.eventId,
    'baseUrl': Uri.parse(subscription.url).origin,
    'topic': Uri.parse(subscription.url).pathSegments.last,
    'time': message.time.toUtc().millisecondsSinceEpoch ~/ 1000,
    'title': message.title ?? '',
    'message': message.decodedMessage,
    'messageBytes': Uint8List.fromList(message.messageBytes),
    'messageEncoding': message.encoding ?? '',
    'contentType': message.contentType ?? '',
    'tags': message.tags.join(','),
    'priority': message.priority,
    'click': message.click ?? '',
    'muted': muted,
    'attachmentName': message.attachment?.name ?? '',
    'attachmentType': message.attachment?.type ?? '',
    'attachmentSize': message.attachment?.size ?? 0,
    'attachmentExpires':
        message.attachment?.expires?.millisecondsSinceEpoch == null
        ? 0
        : message.attachment!.expires!.millisecondsSinceEpoch ~/ 1000,
    'attachmentUrl': message.attachment?.url ?? '',
  });

  @override
  Future<bool> isSubscriptionVisible(int subscriptionId) async =>
      await _channel.invokeMethod<bool>(
        'isSubscriptionVisible',
        subscriptionId,
      ) ??
      false;

  @override
  Future<void> setVisibleSubscription(int? subscriptionId) =>
      _channel.invokeMethod('setVisibleSubscription', subscriptionId);

  @override
  Future<void> close() async {
    if (_started) _channel.setMethodCallHandler(null);
    await _taps.close();
  }
}

class AndroidNotificationSettings {
  const AndroidNotificationSettings();

  Future<void> open({int? subscriptionId}) =>
      const MethodChannel(notificationChannelName)
          .invokeMethod('openNotificationSettings', subscriptionId);
}

abstract interface class ConnectionAlertPlatform {
  Future<void> show(String server, int thresholdSeconds);
  Future<void> clear();
}

class AndroidConnectionAlertPlatform implements ConnectionAlertPlatform {
  const AndroidConnectionAlertPlatform();

  static const _channel = MethodChannel(notificationChannelName);

  @override
  Future<void> show(String server, int thresholdSeconds) =>
      _channel.invokeMethod('showConnectionAlert', {
        'server': server,
        'thresholdSeconds': thresholdSeconds,
      });

  @override
  Future<void> clear() => _channel.invokeMethod('clearConnectionAlert');
}

class MessageNotificationSession {
  MessageNotificationSession(
    this.platform, {
    this.policies,
    this.broadcastsEnabled,
    this.fullScreenAlertSettings,
    this.iconLoader,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final NotificationPlatform platform;
  final NotificationPolicyRepository? policies;
  final Future<bool> Function()? broadcastsEnabled;
  final Future<FullScreenAlertSettings> Function()? fullScreenAlertSettings;
  final Future<Uint8List> Function(Uri uri)? iconLoader;
  final DateTime Function() _now;
  Future<void> _visibilityTail = Future<void>.value();
  int? _visibleSubscriptionId;

  Stream<NotificationTarget> get taps => platform.taps;

  Future<void> start() => platform.start();

  Future<bool> show(Subscription subscription, StoredMessage message) async {
    try {
      final policy = await policies?.loadNotificationPolicy(
        subscriptionId: subscription.id,
      );
      final muted = policy != null && !policy.allows(message.priority, _now());
      if (await broadcastsEnabled?.call() == true) {
        if (platform is MessageBroadcastPlatform) {
          final broadcaster = platform as MessageBroadcastPlatform;
          await broadcaster.broadcast(subscription, message, muted: muted);
        }
      }
      if (_visibleSubscriptionId == subscription.id) return false;
      if (await platform.isSubscriptionVisible(subscription.id)) return false;
      if (muted) {
        return false;
      }
      final emojis = await EmojiTags.prefix(message.tags);
      final fullScreen = await fullScreenAlertSettings?.call();
      final fallbackTitle =
          subscription.displayName ??
          Uri.parse(subscription.url).pathSegments.last;
      final title = message.title == null
          ? fallbackTitle
          : emojis.isEmpty
          ? message.title!
          : '$emojis ${message.title}';
      final decoded = message.decodedMessage;
      final body = message.title != null || emojis.isEmpty
          ? decoded
          : '$emojis $decoded';
      final notification = MessageNotification(
        id: message.localId,
        subscriptionId: subscription.id,
        eventId: message.eventId,
        sequenceId: message.sequenceId,
        title: title,
        body: body,
        priority: NotificationPriority.values[message.priority - 1],
        timestamp: message.time,
        insistent:
            policy?.insistentMaxPriority == true && message.priority == 5,
        fullScreenEligible:
            fullScreen?.enabled == true &&
            matchesFullScreenAlertTags(message.tags, fullScreen!.tags),
        iconPath: policy?.subscriptionIconPath,
        channelId: policy?.dedicatedChannel == true
            ? 'ntfy-topic-${subscription.id}'
            : null,
        channelName: policy?.dedicatedChannel == true
            ? (subscription.displayName ??
                  Uri.parse(subscription.url).pathSegments.last)
            : null,
        click: message.click,
        iconUrl: message.icon,
        actions: message.actions,
        contentType: message.contentType,
        encoding: message.encoding,
        messageBytes: message.messageBytes,
      );
      final shown = await platform.show(notification);
      final icon = Uri.tryParse(message.icon ?? '');
      if (shown &&
          iconLoader != null &&
          icon != null &&
          (icon.scheme == 'http' || icon.scheme == 'https') &&
          icon.host.isNotEmpty) {
        unawaited(_loadIcon(notification, icon));
      }
      return shown;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadIcon(MessageNotification notification, Uri uri) async {
    try {
      final bytes = await iconLoader!(uri);
      if (bytes.isEmpty) return;
      await platform.show(
        MessageNotification(
          id: notification.id,
          subscriptionId: notification.subscriptionId,
          eventId: notification.eventId,
          sequenceId: notification.sequenceId,
          title: notification.title,
          body: notification.body,
          priority: notification.priority,
          timestamp: notification.timestamp,
          insistent: notification.insistent,
          fullScreenEligible: notification.fullScreenEligible,
          iconPath: notification.iconPath,
          channelId: notification.channelId,
          channelName: notification.channelName,
          click: notification.click,
          iconUrl: notification.iconUrl,
          iconBytes: bytes,
          actions: notification.actions,
          contentType: notification.contentType,
          encoding: notification.encoding,
          messageBytes: notification.messageBytes,
        ),
      );
    } catch (_) {
      // The text notification remains usable when a remote icon fails.
    }
  }

  Future<void> handleControl(
    Subscription subscription,
    IncomingMessage message,
  ) async {
    if (message.event == MessageEventType.message ||
        platform is! NotificationControlPlatform) {
      return;
    }
    await (platform as NotificationControlPlatform).cancel(
      subscription.id,
      message.sequenceId,
    );
  }

  Future<void> setVisibleSubscription(int? subscriptionId) {
    _visibleSubscriptionId = subscriptionId;
    final result = _visibilityTail.then((_) async {
      try {
        await platform.setVisibleSubscription(subscriptionId);
      } catch (_) {
        // Visibility transport failure must not disrupt the visible feed.
      }
    });
    _visibilityTail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<void> close() => platform.close();
}
