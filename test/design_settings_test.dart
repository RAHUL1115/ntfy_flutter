import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/app_settings.dart';
import 'package:ntfy_flutter/design.dart';

void main() {
  test('font-size choices preserve system scaling or use documented overrides', () {
    expect(appFontScaleFactor(AppFontScalePreference.system), isNull);
    expect(appFontScaleFactor(AppFontScalePreference.small), 0.9);
    expect(appFontScaleFactor(AppFontScalePreference.standard), 1.0);
    expect(appFontScaleFactor(AppFontScalePreference.large), 1.15);
    expect(appFontScaleFactor(AppFontScalePreference.extraLarge), 1.3);
  });

  test('every accent has readable primary contrast in light and dark modes', () {
    for (final brightness in Brightness.values) {
      final dynamicScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xff336699),
        brightness: brightness,
      );
      for (final accent in AppAccentPreference.values) {
        final scheme = designAppTheme(
          brightness: brightness,
          accent: accent,
          dynamicScheme: dynamicScheme,
        ).colorScheme;
        expect(
          _contrastRatio(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5),
          reason: '${accent.name} ${brightness.name} primary contrast',
        );
      }
    }
  });

  test('dynamic accent uses the supplied Android color scheme', () {
    final dynamicScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff336699),
      brightness: Brightness.light,
    );
    final actual = designAppTheme(
      brightness: Brightness.light,
      accent: AppAccentPreference.dynamic,
      dynamicScheme: dynamicScheme,
    ).colorScheme;

    expect(actual, dynamicScheme);
  });
}

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() > second.computeLuminance()
      ? first
      : second;
  final darker = identical(lighter, first) ? second : first;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
