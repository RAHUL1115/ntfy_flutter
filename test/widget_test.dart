import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/main.dart';

void main() {
  testWidgets('add topic form shows safety guidance and validates input', (
    tester,
  ) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AddSubscriptionPage(
          onSubmit: (baseUrl, topic, displayName, credential) async {
            submitted = true;
            return true;
          },
        ),
      ),
    );

    expect(find.text('Add topic'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Subscribe'), findsOneWidget);
    expect(
      find.textContaining('Public topic names should be hard to guess'),
      findsOneWidget,
    );
    expect(find.text('None'), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);
    expect(find.text('Bearer'), findsOneWidget);

    expect(find.text('Topic URL'), findsOneWidget);
    expect(find.text('Display name (optional)'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Topic URL'),
      'https://ntfy.sh/path/extra',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Subscribe'));
    await tester.pump();

    expect(
      find.text('Use a full topic URL such as https://ntfy.sh/my-topic'),
      findsOneWidget,
    );
    expect(submitted, isFalse);
  });
}
