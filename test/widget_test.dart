import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/background_listening.dart';
import 'package:ntfy_flutter/main.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/retention.dart';
import 'package:ntfy_flutter/subscriptions.dart';

void main() {
  late _MemorySubscriptionRepository store;

  setUp(() => store = _MemorySubscriptionRepository());

  testWidgets('starts on the empty subscriptions screen', (tester) async {
    await tester.pumpWidget(NtfyApp(store: store));
    await tester.pump();

    expect(find.text('Subscribed topics'), findsOneWidget);
    expect(
      find.text("It looks like you don't have any subscriptions yet."),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.sms_outlined), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('opens the subscription dialog from the add button', (
    tester,
  ) async {
    await tester.pumpWidget(NtfyApp(store: store));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Subscribe to topic'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Subscribe'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('adds and displays a named subscription', (tester) async {
    await tester.pumpWidget(NtfyApp(store: store));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('topic-url-field')),
      '  https://ntfy.sh/alerts/  ',
    );
    await tester.enterText(
      find.byKey(const Key('display-name-field')),
      '  Production  ',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Subscribe'));
    await tester.pumpAndSettle();

    expect(find.text('Production'), findsOneWidget);
    expect(find.text('https://ntfy.sh/alerts'), findsOneWidget);
    expect(
      find.text("It looks like you don't have any subscriptions yet."),
      findsNothing,
    );
  });

  testWidgets('swipe removal confirms before deleting local subscription', (
    tester,
  ) async {
    await store.add(url: 'https://ntfy.sh/alerts', displayName: 'Production');
    await tester.pumpWidget(NtfyApp(store: store));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Production'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Unsubscribe from topic?'), findsOneWidget);
    expect(find.textContaining('delete all locally stored'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Production'), findsOneWidget);

    await tester.drag(find.text('Production'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Unsubscribe'));
    await tester.pumpAndSettle();

    expect(await store.all(), isEmpty);
    expect(
      find.text("It looks like you don't have any subscriptions yet."),
      findsOneWidget,
    );
  });

  testWidgets('keeps the dialog open while a subscription is saving', (
    tester,
  ) async {
    final delayedStore = _DelayedSubscriptionRepository();
    await tester.pumpWidget(NtfyApp(store: delayedStore));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('topic-url-field')),
      'https://ntfy.sh/delayed',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Subscribe'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Subscribe to topic'), findsOneWidget);

    delayedStore.complete();
    await tester.pumpAndSettle();
    expect(find.text('https://ntfy.sh/delayed'), findsOneWidget);
  });

  testWidgets('shows actionable validation and duplicate feedback', (
    tester,
  ) async {
    await store.add(url: 'https://ntfy.sh/alerts');
    await tester.pumpWidget(NtfyApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    final urlField = find.byKey(const Key('topic-url-field'));
    final subscribeButton = find.widgetWithText(TextButton, 'Subscribe');

    await tester.enterText(urlField, 'https://ntfy.sh');
    await tester.pump();
    await tester.tap(subscribeButton);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The URL must include a topic, such as https://ntfy.sh/mytopic.',
      ),
      findsOneWidget,
    );

    await tester.enterText(urlField, 'ftp://ntfy.sh/new-topic');
    await tester.pump();
    await tester.tap(subscribeButton);
    await tester.pumpAndSettle();
    expect(find.text('Topic URLs must use HTTP or HTTPS.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('topic-url-field')),
      'HTTPS://NTFY.SH/alerts/',
    );
    await tester.pump();
    await tester.tap(subscribeButton);
    await tester.pumpAndSettle();
    expect(
      find.text('You are already subscribed to this topic.'),
      findsOneWidget,
    );
  });

  testWidgets('uses the source app light colors', (tester) async {
    await tester.pumpWidget(NtfyApp(store: store));

    final theme = Theme.of(tester.element(find.byType(Scaffold)));

    expect(theme.appBarTheme.backgroundColor, const Color(0xff338574));
    expect(theme.scaffoldBackgroundColor, const Color(0xffffffff));
  });

  testWidgets('uses the source app dark colors', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(NtfyApp(store: store));
    final theme = Theme.of(tester.element(find.byType(Scaffold)));

    expect(theme.brightness, Brightness.dark);
    expect(theme.appBarTheme.backgroundColor, const Color(0xff1b2023));
    expect(theme.scaffoldBackgroundColor, const Color(0xff121212));
  });

  testWidgets('labels primary controls and meets Android tap targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(NtfyApp(store: store));

      expect(find.bySemanticsLabel('Add subscription'), findsOneWidget);
      expect(find.byTooltip('Show menu'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('global settings selects and persists message retention', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(NtfyApp(store: store));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Delete notifications'), findsOneWidget);
    expect(find.text('Never auto-delete notifications'), findsOneWidget);

    await tester.tap(find.text('Delete notifications'));
    await tester.pumpAndSettle();
    for (final period in RetentionPeriod.values) {
      expect(find.text(period.label), findsOneWidget);
    }
    final selected = tester.getSemantics(find.bySemanticsLabel('Never'));
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);
    expect(selected.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    semantics.dispose();
    await tester.tap(find.text('After 1 hour'));
    await tester.pumpAndSettle();

    expect(store.globalRetention, RetentionPeriod.oneHour);
    expect(find.text('Auto-delete notifications after 1 hour'), findsOneWidget);
  });

  testWidgets('settings controls background listening and its channel', (
    tester,
  ) async {
    final host = _RecordingBackgroundHost();
    final background = BackgroundListeningSession(store, host);
    await tester.pumpWidget(
      NtfyApp(store: store, backgroundListening: background),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Background listening'), findsOneWidget);
    expect(
      find.textContaining('Android requires an ongoing notification'),
      findsOneWidget,
    );
    expect(
      find.text('Foreground listener notification settings'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('background-listening-switch')));
    await tester.pumpAndSettle();
    expect(store.backgroundListening, isTrue);
    expect(host.starts, 1);

    await tester.tap(find.text('Foreground listener notification settings'));
    await tester.pumpAndSettle();
    expect(host.channelSettingsOpens, 1);

    await tester.tap(find.byKey(const Key('background-listening-switch')));
    await tester.pumpAndSettle();
    expect(store.backgroundListening, isFalse);
    expect(host.stops, 1);
  });
}

class _DelayedSubscriptionRepository
    with _MemoryRetention
    implements AppRepository {
  final _pending = Completer<Subscription>();
  var _subscriptions = <Subscription>[];

  @override
  Future<Subscription> add({required String url, String? displayName}) =>
      _pending.future;

  void complete() {
    final subscription = const Subscription(
      id: 1,
      url: 'https://ntfy.sh/delayed',
    );
    _subscriptions = [subscription];
    _pending.complete(subscription);
  }

  @override
  Future<List<Subscription>> all() async => _subscriptions;

  @override
  Future<void> remove(int subscriptionId) async {
    _subscriptions.removeWhere((item) => item.id == subscriptionId);
  }

  @override
  Future<FeedSnapshot> loadFeed(int subscriptionId) async =>
      FeedSnapshot(messages: []);

  @override
  Future<StoredMessage?> ingest(
    int subscriptionId,
    IncomingMessage message,
  ) async => null;

  @override
  Future<void> deleteMessage(int subscriptionId, int localId) async {}

  @override
  Future<void> restoreMessage(
    int subscriptionId,
    StoredMessage message,
  ) async {}

  @override
  Future<void> clearMessages(int subscriptionId) async {}
}

mixin _MemoryRetention {
  RetentionPeriod globalRetention = RetentionPeriod.never;
  final topicRetention = <int, RetentionPeriod?>{};
  bool backgroundListening = false;

  Future<bool> loadBackgroundListening() async => backgroundListening;

  Future<void> setBackgroundListening(bool enabled) async {
    backgroundListening = enabled;
  }

  Future<RetentionSettings> loadRetention({int? subscriptionId}) async =>
      RetentionSettings(
        global: globalRetention,
        override: subscriptionId == null
            ? null
            : topicRetention[subscriptionId],
      );

  Future<void> executeRetention(RetentionCommand command) async {
    switch (command) {
      case SetGlobalRetention(:final period):
        globalRetention = period;
      case SetTopicRetention(:final subscriptionId, :final period):
        topicRetention[subscriptionId] = period;
      case RunRetentionCleanup():
        break;
    }
  }
}

class _RecordingBackgroundHost implements BackgroundListeningHost {
  int starts = 0;
  int stops = 0;
  int channelSettingsOpens = 0;

  @override
  Future<void> startOrRefresh() async => starts++;

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> requestNotificationPermission() async {}

  @override
  Future<void> openChannelSettings() async => channelSettingsOpens++;

  @override
  Future<BackgroundListeningHostStatus> status() async =>
      const BackgroundListeningHostStatus(
        running: false,
        notificationPresent: false,
      );
}

class _MemorySubscriptionRepository
    with _MemoryRetention
    implements AppRepository {
  final _subscriptions = <Subscription>[];

  @override
  Future<Subscription> add({required String url, String? displayName}) async {
    final normalizedUrl = SubscriptionStore.normalizeUrl(url);
    if (_subscriptions.any((item) => item.url == normalizedUrl)) {
      throw const SubscriptionException(
        'You are already subscribed to this topic.',
      );
    }
    final normalizedName = displayName?.trim();
    final subscription = Subscription(
      id: _subscriptions.length + 1,
      url: normalizedUrl,
      displayName: normalizedName?.isEmpty == true ? null : normalizedName,
    );
    _subscriptions.add(subscription);
    return subscription;
  }

  @override
  Future<List<Subscription>> all() async => List.unmodifiable(_subscriptions);

  @override
  Future<void> remove(int subscriptionId) async {
    _subscriptions.removeWhere((item) => item.id == subscriptionId);
  }

  @override
  Future<FeedSnapshot> loadFeed(int subscriptionId) async =>
      FeedSnapshot(messages: []);

  @override
  Future<StoredMessage?> ingest(
    int subscriptionId,
    IncomingMessage message,
  ) async => null;

  @override
  Future<void> deleteMessage(int subscriptionId, int localId) async {}

  @override
  Future<void> restoreMessage(
    int subscriptionId,
    StoredMessage message,
  ) async {}

  @override
  Future<void> clearMessages(int subscriptionId) async {}
}
