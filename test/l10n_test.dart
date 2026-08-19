import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/l10n.dart';

void main() {
  testWidgets('app strings and formatted values use the selected language', (
    tester,
  ) async {
    await tester.runAsync(
      () => NtfyLocalizations.delegate.load(const Locale('de')),
    );
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('de'),
        supportedLocales: [Locale('de')],
        localizationsDelegates: [
          NtfyLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: Column(
            children: [LText('Subscribed topics'), LText('3 notifications')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final context = tester.element(find.byType(Column));
    expect(NtfyLocalizations.of(context).locale.languageCode, 'de');
    expect(
      NtfyLocalizations.of(context).translate('Subscribed topics'),
      'Abonnierte Themen',
    );
    expect(find.text('Abonnierte Themen'), findsOneWidget);
    expect(find.text('3 Benachrichtigungen'), findsOneWidget);
    expect(find.text('Subscribed topics'), findsNothing);
  });
}
