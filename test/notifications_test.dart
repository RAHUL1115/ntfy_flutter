import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/notification_policy.dart';
import 'package:ntfy_flutter/notifications.dart';
import 'package:ntfy_flutter/subscriptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new messages preserve the five ntfy notification priorities', () async {
    final platform = _RecordingNotificationPlatform();
    final notifications = MessageNotificationSession(platform);
    const subscription = Subscription(
      id: 7,
      url: 'https://ntfy.sh/alerts',
      displayName: 'Production alerts',
    );

    for (var priority = 1; priority <= 5; priority++) {
      await notifications.show(
        subscription,
        StoredMessage(
          localId: priority,
          subscriptionId: subscription.id,
          eventId: 'event-$priority',
          time: DateTime.utc(2026, 8, 17, 12, priority),
          message: 'Message $priority',
          priority: priority,
        ),
      );
    }

    expect(
      platform.shown.map((notification) => notification.priority),
      NotificationPriority.values,
    );
    expect(platform.shown.first.title, 'Production alerts');
  });

  test('recognized tags use the same emoji title/body presentation', () async {
    final platform = _RecordingNotificationPlatform();
    final notifications = MessageNotificationSession(platform);
    const subscription = Subscription(id: 7, url: 'https://ntfy.sh/alerts');

    await notifications.show(
      subscription,
      StoredMessage(
        localId: 1,
        subscriptionId: 7,
        eventId: 'with-title',
        time: DateTime.utc(2026),
        message: 'Body',
        title: 'Title',
        tags: const ['warning'],
      ),
    );
    await notifications.show(
      subscription,
      StoredMessage(
        localId: 2,
        subscriptionId: 7,
        eventId: 'without-title',
        time: DateTime.utc(2026),
        message: 'Body',
        tags: const ['warning'],
      ),
    );

    expect(platform.shown.first.title, '⚠️ Title');
    expect(platform.shown.first.body, 'Body');
    expect(platform.shown.last.title, 'alerts');
    expect(platform.shown.last.body, '⚠️ Body');
  });

  test(
    'advanced metadata reaches replacement notification and controls cancel it',
    () async {
      final platform = _RecordingNotificationPlatform();
      final notifications = MessageNotificationSession(platform);
      const subscription = Subscription(id: 7, url: 'https://ntfy.sh/alerts');
      final message = StoredMessage(
        localId: 1,
        subscriptionId: 7,
        eventId: 'update-2',
        sequenceId: 'deployment',
        time: DateTime.utc(2026),
        message: base64Encode(utf8.encode('Decoded')),
        encoding: 'base64',
        contentType: 'text/markdown',
        click: 'https://example.com',
        icon: 'https://example.com/icon.png',
        actions: const [
          MessageAction(id: 'open', action: 'view', label: 'Open'),
        ],
      );

      expect(await notifications.show(subscription, message), isTrue);
      final shown = platform.shown.single;
      expect(shown.sequenceId, 'deployment');
      expect(shown.body, 'Decoded');
      expect(shown.click, 'https://example.com');
      expect(shown.iconUrl, 'https://example.com/icon.png');
      expect(shown.actions.single.label, 'Open');
      expect(shown.contentType, 'text/markdown');
      expect(shown.encoding, 'base64');
      expect(shown.messageBytes, utf8.encode('Decoded'));

      await notifications.handleControl(
        subscription,
        IncomingMessage(
          eventId: 'delete',
          sequenceId: 'deployment',
          event: MessageEventType.delete,
          time: DateTime.utc(2026),
          message: '',
        ),
      );
      expect(platform.cancelled, [(7, 'deployment')]);
    },
  );

  test('remote icon updates the posted notification asynchronously', () async {
    final platform = _RecordingNotificationPlatform();
    final notifications = MessageNotificationSession(
      platform,
      iconLoader: (uri) async {
        expect(uri, Uri.parse('https://example.com/icon.png'));
        return Uint8List.fromList([1, 2, 3]);
      },
    );
    const subscription = Subscription(id: 7, url: 'https://ntfy.sh/alerts');

    expect(
      await notifications.show(
        subscription,
        StoredMessage(
          localId: 1,
          subscriptionId: 7,
          eventId: 'icon',
          time: DateTime.utc(2026),
          message: 'Body',
          icon: 'https://example.com/icon.png',
        ),
      ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);

    expect(platform.shown, hasLength(2));
    expect(platform.shown.first.iconBytes, isNull);
    expect(platform.shown.last.iconBytes, [1, 2, 3]);
    expect(platform.shown.last.eventId, 'icon');
  });

  test('only the exact visibly active subscription is suppressed', () async {
    final platform = _RecordingNotificationPlatform()..visibleId = 7;
    final notifications = MessageNotificationSession(platform);
    final message = StoredMessage(
      localId: 1,
      subscriptionId: 7,
      eventId: 'same-topic',
      time: DateTime.utc(2026),
      message: 'Already visible',
    );

    expect(
      await notifications.show(
        const Subscription(id: 7, url: 'https://ntfy.sh/visible'),
        message,
      ),
      isFalse,
    );
    expect(
      await notifications.show(
        const Subscription(id: 8, url: 'https://ntfy.sh/other'),
        StoredMessage(
          localId: 2,
          subscriptionId: 8,
          eventId: 'other-topic',
          time: DateTime.utc(2026),
          message: 'Other topic',
        ),
      ),
      isTrue,
    );
    expect(platform.shown.single.subscriptionId, 8);
  });

  test('enabled broadcasts include visible and muted messages', () async {
    final platform = _RecordingNotificationPlatform()..visibleId = 7;
    final policies = _PolicyRepository(
      const NotificationPolicy(minimumPriority: 5),
    );
    final notifications = MessageNotificationSession(
      platform,
      policies: policies,
      broadcastsEnabled: () async => true,
    );
    const subscription = Subscription(id: 7, url: 'https://ntfy.sh/alerts');
    final message = StoredMessage(
      localId: 1,
      subscriptionId: 7,
      eventId: 'broadcast-event',
      time: DateTime.utc(2026),
      message: 'Muted but broadcast',
      priority: 3,
    );

    expect(await notifications.show(subscription, message), isFalse);
    expect(platform.shown, isEmpty);
    expect(platform.broadcasts, [(subscription, message, true)]);
  });

  test('notification permission denial is a non-fatal result', () async {
    final platform = _RecordingNotificationPlatform()..allowPosting = false;
    final notifications = MessageNotificationSession(platform);

    expect(
      await notifications.show(
        const Subscription(id: 7, url: 'https://ntfy.sh/alerts'),
        StoredMessage(
          localId: 1,
          subscriptionId: 7,
          eventId: 'denied',
          time: DateTime.utc(2026),
          message: 'Still stored',
        ),
      ),
      isFalse,
    );
  });

  test(
    'persisted policy mutes and filters without dropping max alerts',
    () async {
      final platform = _RecordingNotificationPlatform();
      final policies = _PolicyRepository(
        const NotificationPolicy(
          minimumPriority: 4,
          insistentMaxPriority: true,
          subscriptionIconPath: '/managed/icon.png',
          dedicatedChannel: true,
        ),
      );
      final notifications = MessageNotificationSession(
        platform,
        policies: policies,
        now: () => DateTime.utc(2026),
      );
      const subscription = Subscription(id: 7, url: 'https://ntfy.sh/alerts');

      expect(
        await notifications.show(
          subscription,
          StoredMessage(
            localId: 1,
            subscriptionId: 7,
            eventId: 'low',
            time: DateTime.utc(2026),
            message: 'Low',
            priority: 3,
          ),
        ),
        isFalse,
      );
      expect(
        await notifications.show(
          subscription,
          StoredMessage(
            localId: 2,
            subscriptionId: 7,
            eventId: 'max',
            time: DateTime.utc(2026),
            message: 'Max',
            priority: 5,
          ),
        ),
        isTrue,
      );
      expect(platform.shown.single.insistent, isTrue);
      expect(platform.shown.single.iconPath, '/managed/icon.png');
      expect(platform.shown.single.channelId, 'ntfy-topic-7');

      policies.policy = const NotificationPolicy(
        mutedUntilEpochSeconds: NotificationPolicy.untilResumed,
      );
      expect(
        await notifications.show(
          subscription,
          StoredMessage(
            localId: 3,
            subscriptionId: 7,
            eventId: 'muted',
            time: DateTime.utc(2026),
            message: 'Muted',
          ),
        ),
        isFalse,
      );
    },
  );
}

class _PolicyRepository implements NotificationPolicyRepository {
  _PolicyRepository(this.policy);

  NotificationPolicy policy;

  @override
  Future<NotificationPolicy> loadNotificationPolicy({
    int? subscriptionId,
  }) async => policy;

  @override
  Future<void> setGlobalNotificationPolicy(NotificationPolicy policy) async {
    this.policy = policy;
  }

  @override
  Future<void> setTopicNotificationPolicy(
    int subscriptionId,
    NotificationPolicy? policy,
  ) async {
    if (policy != null) this.policy = policy;
  }
}

class _RecordingNotificationPlatform
    implements
        NotificationPlatform,
        MessageBroadcastPlatform,
        NotificationControlPlatform {
  final shown = <MessageNotification>[];
  final broadcasts = <(Subscription, StoredMessage, bool)>[];
  final cancelled = <(int, String)>[];
  final _taps = StreamController<NotificationTarget>.broadcast();
  int? visibleId;
  bool allowPosting = true;

  @override
  Stream<NotificationTarget> get taps => _taps.stream;

  @override
  Future<bool> isSubscriptionVisible(int subscriptionId) async =>
      visibleId == subscriptionId;

  @override
  Future<void> setVisibleSubscription(int? subscriptionId) async {
    visibleId = subscriptionId;
  }

  @override
  Future<bool> show(MessageNotification notification) async {
    if (!allowPosting) return false;
    shown.add(notification);
    return true;
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> close() => _taps.close();

  @override
  Future<void> cancel(int subscriptionId, String sequenceId) async {
    cancelled.add((subscriptionId, sequenceId));
  }

  @override
  Future<void> broadcast(
    Subscription subscription,
    StoredMessage message, {
    required bool muted,
  }) async {
    broadcasts.add((subscription, message, muted));
  }
}
