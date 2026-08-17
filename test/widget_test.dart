import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/main.dart';
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

  testWidgets('opens settings from the app bar menu', (tester) async {
    await tester.pumpWidget(NtfyApp(store: store));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Subscribed topics'), findsNothing);
  });
}

class _DelayedSubscriptionRepository implements SubscriptionRepository {
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
}

class _MemorySubscriptionRepository implements SubscriptionRepository {
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
}
