import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/main.dart';

void main() {
  testWidgets('starts on the empty subscriptions screen', (tester) async {
    await tester.pumpWidget(const NtfyApp());

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
    await tester.pumpWidget(const NtfyApp());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Subscribe to topic'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Subscribe'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('uses the source app light colors', (tester) async {
    await tester.pumpWidget(const NtfyApp());

    final theme = Theme.of(tester.element(find.byType(Scaffold)));

    expect(theme.appBarTheme.backgroundColor, const Color(0xff338574));
    expect(theme.scaffoldBackgroundColor, const Color(0xffffffff));
  });

  testWidgets('uses the source app dark colors', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const NtfyApp());
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
      await tester.pumpWidget(const NtfyApp());

      expect(find.bySemanticsLabel('Add subscription'), findsOneWidget);
      expect(find.byTooltip('Show menu'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('opens settings from the app bar menu', (tester) async {
    await tester.pumpWidget(const NtfyApp());

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Subscribed topics'), findsNothing);
  });
}
