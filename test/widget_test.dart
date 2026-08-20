import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/app_settings.dart';
import 'package:ntfy_flutter/background_listening.dart';
import 'package:ntfy_flutter/design.dart';
import 'package:ntfy_flutter/main.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/notifications.dart';
import 'package:ntfy_flutter/ntfy_topic_icon.dart';
import 'package:ntfy_flutter/retention.dart';
import 'package:ntfy_flutter/retention_settings.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:ntfy_flutter/topic_feed.dart';
import 'package:ntfy_flutter/topic_feed_screen.dart';

void main() {
  late _MemorySubscriptionRepository store;

  setUp(() => store = _MemorySubscriptionRepository());

  testWidgets('design headers collapse on scroll and expand at the top', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: CollapsibleDesignBody(
            title: const Text('Page title'),
            child: ListView.builder(
              itemCount: 1,
              itemBuilder: (_, index) => ListTile(title: Text('Row $index')),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(DesignHeader)).height, 268);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Row 0')),
    );
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    final heldHeight = tester.getSize(find.byType(DesignHeader)).height;
    expect(heldHeight, inExclusiveRange(72, 268));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(find.byType(DesignHeader)).height, heldHeight);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesignHeader)).height, 268);

    await tester.drag(find.text('Row 0'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesignHeader)).height, 72);
    await tester.fling(find.byType(ListView), const Offset(0, 700), 1000);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesignHeader)).height, 268);
  });

  testWidgets('expanded header aligns back button with trailing actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: DesignHeader(
            progress: 1,
            duration: Duration.zero,
            title: const Text('Page title'),
            leading: const SizedBox(key: Key('expanded-back')),
            actions: const [
              SizedBox(
                key: Key('expanded-action'),
                width: 48,
                height: 48,
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const Key('expanded-back'))).dy,
      tester.getTopLeft(find.byKey(const Key('expanded-action'))).dy,
    );
  });

  testWidgets('expanded header follows a drag started on the title', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: CollapsibleDesignBody(
            title: const Text('Page title'),
            scrollController: scrollController,
            child: ListView.builder(
              controller: scrollController,
              itemCount: 50,
              itemBuilder: (_, index) => ListTile(title: Text('Row $index')),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Page title')),
    );
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(
      tester.getSize(find.byType(DesignHeader)).height,
      inExclusiveRange(72, 268),
    );
    await gesture.moveBy(const Offset(0, -250));
    await tester.pump();
    expect(scrollController.offset, greaterThan(0));
    await gesture.up();
    await tester.pump();
    await tester.pump(designMotionDuration);
    expect(tester.getSize(find.byType(DesignHeader)).height, 72);
  });

  testWidgets('inertial scrolling finishes collapsing the header promptly', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Scaffold(
          body: CollapsibleDesignBody(
            title: const Text('Page title'),
            scrollController: scrollController,
            child: ListView.builder(
              controller: scrollController,
              itemCount: 50,
              itemBuilder: (_, index) => ListTile(title: Text('Row $index')),
            ),
          ),
        ),
      ),
    );
    if (tester.getSize(find.byType(DesignHeader)).height == 72) {
      await tester.drag(find.text('Page title'), const Offset(0, 300));
      await tester.pumpAndSettle();
    }

    await tester.fling(find.text('Row 0'), const Offset(0, -80), 3000);
    expect(
      tester.getSize(find.byType(DesignHeader)).height,
      inExclusiveRange(72, 268),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(designMotionDuration);

    expect(scrollController.offset, greaterThan(80));
    expect(tester.getSize(find.byType(DesignHeader)).height, 72);
  });

  testWidgets('settled header state is shared between pages', (tester) async {
    Widget page(String title) => Scaffold(
      body: CollapsibleDesignBody(
        title: Text(title),
        child: ListView(children: [ListTile(title: Text('$title row'))]),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(theme: lightTheme, home: page('First page')),
    );
    await tester.drag(find.text('First page row'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesignHeader)).height, 72);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => page('Next page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesignHeader)).height, 72);

    await tester.fling(find.text('Next page row'), const Offset(0, 700), 1000);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesignHeader)).height, 268);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DesignHeader)).height, 268);
  });

  testWidgets('starts on the empty subscriptions screen', (tester) async {
    await tester.pumpWidget(NtfyApp(store: store));
    await tester.pump();

    expect(find.text('Subscribed topics'), findsOneWidget);
    expect(
      find.text("It looks like you don't have any subscriptions yet."),
      findsOneWidget,
    );
    expect(find.byType(NtfyTopicIcon), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('home polling stops while the app is backgrounded', (
    tester,
  ) async {
    await tester.pumpWidget(NtfyApp(store: store));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(store.allCalls, greaterThan(1));

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    final pausedCalls = store.allCalls;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(store.allCalls, pausedCalls);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(store.allCalls, greaterThan(pausedCalls));
  });

  testWidgets('shows connection errors and retries from the topic list', (
    tester,
  ) async {
    await store.add(url: 'https://ntfy.sh/alerts');
    store.backgroundListening = true;
    final host = _RecordingBackgroundHost(
      statusValue: const BackgroundListeningHostStatus(
        running: true,
        notificationPresent: true,
        connections: [
          BackgroundServerConnectionStatus(
            server: 'https://ntfy.sh/',
            state: BackgroundConnectionState.connecting,
            error: 'Connection refused.',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      NtfyApp(
        store: store,
        backgroundListening: BackgroundListeningSession(store, host),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('connection-error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('connection-error')));
    await tester.pumpAndSettle();
    expect(find.text('Connection refused.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry now'));
    await tester.pumpAndSettle();
    expect(host.starts, 2);
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
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Subscribe'))
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
    await tester.tap(find.widgetWithText(FilledButton, 'Subscribe'));
    await tester.pumpAndSettle();

    expect(find.text('Production'), findsOneWidget);
    final displayName = tester.widget<Text>(find.text('Production'));
    expect(displayName.style?.fontSize, 16);
    expect(displayName.style?.fontWeight, FontWeight.w700);
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(find.textContaining('https://ntfy.sh/alerts'), findsNothing);
    expect(
      find.text("It looks like you don't have any subscriptions yet."),
      findsNothing,
    );
  });

  testWidgets('topic settings rename only the local display name', (
    tester,
  ) async {
    await store.add(url: 'https://ntfy.sh/alerts', displayName: 'Production');
    await tester.pumpWidget(
      NtfyApp(
        store: store,
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: store,
            subscription: subscription,
            client: _SilentClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Production'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscription settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topic-display-name')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('display-name-field')),
      'Critical alerts',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-display-name')), findsOneWidget);
    expect(find.text('Critical alerts'), findsWidgets);
    expect((await store.all()).single.url, 'https://ntfy.sh/alerts');
  });

  testWidgets('changing background delivery keeps topic settings open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TopicSettingsScreen(
          subscription: const Subscription(
            id: 1,
            url: 'https://ntfy.sh/alerts',
            displayName: 'Production',
            backgroundEnabled: true,
          ),
          retention: RetentionSession(store),
          onRename: (name) => store.rename(1, name),
          onBackgroundEnabled: (enabled) async => Subscription(
            id: 1,
            url: 'https://ntfy.sh/alerts',
            displayName: 'Production',
            backgroundEnabled: enabled,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('topic-background-listening')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-display-name')), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('topic-background-listening')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('tapping the topic URL copies it', (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TopicSettingsScreen(
          subscription: const Subscription(
            id: 1,
            url: 'https://ntfy.sh/alerts',
          ),
          retention: RetentionSession(store),
        ),
      ),
    );

    await tester.tap(find.text('Topic URL'));
    await tester.pump();

    expect(copiedText, 'https://ntfy.sh/alerts');
    expect(find.text('Topic URL copied.'), findsOneWidget);
  });

  testWidgets('UnifiedPush rows show their app and open settings', (
    tester,
  ) async {
    store.seedUnifiedPush();
    await tester.pumpWidget(NtfyApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('com.example.client (UnifiedPush)'), findsOneWidget);
    await tester.tap(find.text('UnifiedPush topic'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('topic-display-name')), findsOneWidget);
  });

  testWidgets('topic rows expose and clear unread activity', (tester) async {
    store.seedUnread(count: 3);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      NtfyApp(
        store: store,
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: store,
            subscription: subscription,
            client: _SilentClient(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.bySemanticsLabel(RegExp('3 unread notifications')),
      findsOneWidget,
    );
    await tester.tap(find.text('Production'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect((await store.all()).single.unreadCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    semantics.dispose();
  });

  testWidgets('home settings action owns update and support links', (
    tester,
  ) async {
    final settings = AppSettingsStore(
      preferences: _MemoryPreferences(),
      secrets: _MemorySecrets(),
    );
    await tester.pumpWidget(NtfyApp(store: store, settings: settings));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-settings-action')), findsOneWidget);
    expect(find.byType(PopupMenuButton), findsNothing);

    await tester.tap(find.byKey(const Key('home-settings-action')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.byKey(const Key('check-for-updates-setting')), findsOneWidget);
    expect(find.byKey(const Key('report-bug-setting')), findsOneWidget);
    expect(find.byKey(const Key('documentation-setting')), findsOneWidget);
  });

  testWidgets('subscription deletion needs two stages and supports undo', (
    tester,
  ) async {
    await store.add(url: 'https://ntfy.sh/alerts', displayName: 'Production');
    await tester.pumpWidget(NtfyApp(store: store));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('subscription-1'));
    await tester.drag(row, const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(find.text('Production'), findsOneWidget);
    expect((await store.all()).single.displayName, 'Production');
    expect(
      find.descendant(
        of: row,
        matching: find.byKey(const Key('swipe-delete-action')),
      ),
      findsOneWidget,
    );
    expect(find.text('Unsubscribe from topic?'), findsNothing);

    await tester.drag(find.text('Production'), const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(find.text('Production'), findsNothing);
    expect(find.text('Subscription deleted'), findsOneWidget);
    expect((await store.all()).single.displayName, 'Production');

    await tester.tap(find.widgetWithText(TextButton, 'Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Production'), findsOneWidget);
    expect((await store.all()).single.displayName, 'Production');
  });

  testWidgets('subscription delete action commits after undo expires', (
    tester,
  ) async {
    await store.add(url: 'https://ntfy.sh/alerts', displayName: 'Production');
    await tester.pumpWidget(NtfyApp(store: store));
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('subscription-1'));
    await tester.drag(row, const Offset(-180, 0));
    await tester.pumpAndSettle();
    final action = find.descendant(
      of: row,
      matching: find.byKey(const Key('swipe-delete-action')),
    );
    await tester.tap(action);
    await tester.pump();
    expect(find.text('Production'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(await store.all(), isEmpty);
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
    await tester.tap(find.widgetWithText(FilledButton, 'Subscribe'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('Subscribe to topic'), findsOneWidget);

    delayedStore.complete();
    await tester.pumpAndSettle();
    expect(find.text('delayed'), findsOneWidget);
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
    final subscribeButton = find.widgetWithText(FilledButton, 'Subscribe');

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

  testWidgets('uses the design system light colors', (tester) async {
    await tester.pumpWidget(NtfyApp(store: store));

    final theme = Theme.of(tester.element(find.byType(Scaffold)));

    expect(theme.appBarTheme.backgroundColor, const Color(0xfff8fafa));
    expect(theme.scaffoldBackgroundColor, const Color(0xfff8fafa));
    expect(theme.colorScheme.primary, const Color(0xff004f45));
  });

  testWidgets('uses the design system dark colors', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(NtfyApp(store: store));
    final theme = Theme.of(tester.element(find.byType(Scaffold)));

    expect(theme.brightness, Brightness.dark);
    expect(theme.appBarTheme.backgroundColor, const Color(0xff0f1413));
    expect(theme.scaffoldBackgroundColor, const Color(0xff0f1413));
  });

  testWidgets('labels primary controls and meets Android tap targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(NtfyApp(store: store));

      expect(find.bySemanticsLabel('Add subscription'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('home-settings-action')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('home-settings-action')));
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

  testWidgets('settings persists new messages at bottom', (tester) async {
    final settings = AppSettingsStore(
      preferences: _MemoryPreferences(),
      secrets: _MemorySecrets(),
    );
    await tester.pumpWidget(NtfyApp(store: store, settings: settings));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-settings-action')));
    await tester.pumpAndSettle();
    final setting = find.byKey(const Key('new-messages-at-bottom-setting'));
    await tester.ensureVisible(setting);
    await tester.pumpAndSettle();
    await tester.tap(setting);
    await tester.pumpAndSettle();

    expect((await settings.loadSettings()).newMessagesAtBottom, isTrue);
  });

  testWidgets('notification taps deduplicate only while the route is open', (
    tester,
  ) async {
    await store.add(url: 'https://ntfy.sh/first', displayName: 'First');
    final second = await store.add(
      url: 'https://ntfy.sh/second',
      displayName: 'Second',
    );
    final platform = _RecordingNotificationPlatform();
    await tester.pumpWidget(
      NtfyApp(
        store: store,
        notifications: MessageNotificationSession(platform),
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: store,
            subscription: subscription,
            client: _SilentClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    platform.emit(
      NotificationTarget(subscriptionId: second.id, eventId: 'second-message'),
    );
    platform.emit(
      NotificationTarget(subscriptionId: second.id, eventId: 'second-message'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TopicFeedScreen), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Subscribed topics'), findsOneWidget);

    platform.emit(
      NotificationTarget(subscriptionId: second.id, eventId: 'second-message'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TopicFeedScreen), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('topic-only subscriptions use the configured default server', (
    tester,
  ) async {
    final settings = AppSettingsStore(
      preferences: _MemoryPreferences(),
      secrets: _MemorySecrets(),
    );
    await settings.saveSettings(
      const AppSettings(defaultServer: 'https://example.com/base/'),
    );
    await tester.pumpWidget(NtfyApp(store: store, settings: settings));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('topic-url-field')), 'alerts');
    await tester.pump();
    final subscribe = find.widgetWithText(FilledButton, 'Subscribe');
    expect(tester.widget<FilledButton>(subscribe).onPressed, isNotNull);
    await tester.tap(subscribe);
    await tester.pumpAndSettle();

    expect(await store.all(), hasLength(1));
    expect((await store.all()).single.url, 'https://example.com/base/alerts');
  });

  testWidgets('scheme-less server subscriptions are recognized as URLs', (
    tester,
  ) async {
    await tester.pumpWidget(NtfyApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('topic-url-field')),
      'ntfy.sh/topic1',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Subscribe'));
    await tester.pumpAndSettle();

    expect(await store.all(), hasLength(1));
    expect((await store.all()).single.url, 'https://ntfy.sh/topic1');
  });

  testWidgets('only a resumed topmost topic is marked visible', (tester) async {
    await store.add(url: 'https://ntfy.sh/alerts', displayName: 'Production');
    final platform = _RecordingNotificationPlatform();
    await tester.pumpWidget(
      NtfyApp(
        store: store,
        notifications: MessageNotificationSession(platform),
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: store,
            subscription: subscription,
            client: _SilentClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production'));
    await tester.pumpAndSettle();
    expect(platform.visibleId, 1);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscription settings'));
    await tester.pumpAndSettle();
    expect(platform.visibleId, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(platform.visibleId, 1);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(platform.visibleId, isNull);

    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(platform.visibleId, 1);
  });

  testWidgets('home has stable light, dark, and large-text goldens', (
    tester,
  ) async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf')))
        .load();
    await (FontLoader('HankenGrotesk')
          ..addFont(rootBundle.load('assets/fonts/HankenGrotesk-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/HankenGrotesk-Bold.ttf')))
        .load();
    await store.add(url: 'https://ntfy.sh/rahul', displayName: 'Rahul');
    final routeObserver = RouteObserver<PageRoute<dynamic>>();

    Future<void> pumpVariant({
      required ThemeData theme,
      required Size size,
      required double textScale,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          navigatorObservers: [routeObserver],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: SubscriptionsScreen(
            store: store,
            feedFactory: (subscription) => TopicFeedSession(
              controller: TopicFeedController(
                repository: store,
                subscription: subscription,
                client: _SilentClient(),
              ),
            ),
            retention: RetentionSession(store),
            backgroundListening: BackgroundListeningSession(
              store,
              _RecordingBackgroundHost(),
            ),
            notifications: MessageNotificationSession(
              _RecordingNotificationPlatform(),
            ),
            routeObserver: routeObserver,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    addTearDown(tester.view.reset);
    await pumpVariant(
      theme: lightTheme,
      size: const Size(412, 915),
      textScale: 1,
    );
    await expectLater(
      find.byType(SubscriptionsScreen),
      matchesGoldenFile('goldens/home_light_phone.png'),
    );

    await pumpVariant(
      theme: darkTheme,
      size: const Size(412, 915),
      textScale: 1,
    );
    await expectLater(
      find.byType(SubscriptionsScreen),
      matchesGoldenFile('goldens/home_dark_phone.png'),
    );

    await pumpVariant(
      theme: lightTheme,
      size: const Size(600, 960),
      textScale: 1.6,
    );
    await expectLater(
      find.byType(SubscriptionsScreen),
      matchesGoldenFile('goldens/home_light_large_text.png'),
    );
  }, tags: 'golden');
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
  Future<void> markRead(int subscriptionId) async {}

  @override
  Future<Subscription> rename(int subscriptionId, String? displayName) async {
    final current = _subscriptions.singleWhere(
      (item) => item.id == subscriptionId,
    );
    final renamed = Subscription(
      id: current.id,
      url: current.url,
      displayName: displayName?.trim().isEmpty == true
          ? null
          : displayName?.trim(),
      unreadCount: current.unreadCount,
      totalCount: current.totalCount,
      lastActivity: current.lastActivity,
    );
    _subscriptions = [renamed];
    return renamed;
  }

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
  _RecordingBackgroundHost({
    this.statusValue = const BackgroundListeningHostStatus(
      running: false,
      notificationPresent: false,
    ),
  });

  final BackgroundListeningHostStatus statusValue;
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
  Future<BackgroundListeningHostStatus> status() async => statusValue;
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
  final _taps = StreamController<NotificationTarget>.broadcast();
  int? visibleId;

  void emit(NotificationTarget target) => _taps.add(target);

  @override
  Stream<NotificationTarget> get taps => _taps.stream;

  @override
  Future<void> start() async {}

  @override
  Future<bool> show(MessageNotification notification) async => true;

  @override
  Future<bool> isSubscriptionVisible(int subscriptionId) async =>
      visibleId == subscriptionId;

  @override
  Future<void> setVisibleSubscription(int? subscriptionId) async {
    visibleId = subscriptionId;
  }

  @override
  Future<void> close() => _taps.close();
}

class _SilentClient implements NtfyStreamClient {
  final _lines = StreamController<String>();

  @override
  Future<FeedConnection> connect({
    required String topicUrl,
    String? cursor,
  }) async => FeedConnection(
    lines: _lines.stream,
    onClose: () async {
      if (!_lines.isClosed) await _lines.close();
    },
  );
}

class _MemorySubscriptionRepository
    with _MemoryRetention
    implements AppRepository {
  final _subscriptions = <Subscription>[];
  var allCalls = 0;

  void seedUnread({required int count}) {
    _subscriptions.add(
      Subscription(
        id: 1,
        url: 'https://ntfy.sh/alerts',
        displayName: 'Production',
        unreadCount: count,
        totalCount: count,
        lastActivity: DateTime.utc(2026),
      ),
    );
  }

  void seedUnifiedPush() {
    _subscriptions.add(
      const Subscription(
        id: 1,
        url: 'https://ntfy.sh/up-topic',
        displayName: 'UnifiedPush topic',
        unifiedPushApp: 'com.example.client',
        unifiedPushToken: 'connector-token',
      ),
    );
  }

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
  Future<List<Subscription>> all() async {
    allCalls++;
    return List.unmodifiable(_subscriptions);
  }

  @override
  Future<void> markRead(int subscriptionId) async {
    final index = _subscriptions.indexWhere(
      (item) => item.id == subscriptionId,
    );
    if (index < 0) return;
    final current = _subscriptions[index];
    _subscriptions[index] = Subscription(
      id: current.id,
      url: current.url,
      displayName: current.displayName,
      totalCount: current.totalCount,
      lastActivity: current.lastActivity,
    );
  }

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
    );
    _subscriptions[index] = renamed;
    return renamed;
  }

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
