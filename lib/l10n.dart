import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NtfyLocalizations {
  NtfyLocalizations(this.locale, this._translations);

  final Locale locale;
  final Map<String, String> _translations;
  late final List<_TemplateTranslation> _templates = _translations.entries
      .where((entry) => _placeholder.hasMatch(entry.key))
      .map(_TemplateTranslation.new)
      .toList(growable: false);

  static NtfyLocalizations of(BuildContext context) =>
      Localizations.of<NtfyLocalizations>(context, NtfyLocalizations) ??
      NtfyLocalizations(const Locale('en'), const {});

  String translate(String value) {
    final exact = _translations[value];
    if (exact != null) return exact;
    for (final template in _templates) {
      final translated = template.translate(value);
      if (translated != null) return translated;
    }
    return value;
  }

  static const delegate = _NtfyLocalizationsDelegate();
}

final _placeholder = RegExp(r'%(?:(\d+)\$)?[sd]');

class _TemplateTranslation {
  _TemplateTranslation(this.entry) {
    final pattern = StringBuffer('^');
    var end = 0;
    var sequential = 1;
    for (final match in _placeholder.allMatches(entry.key)) {
      pattern
        ..write(RegExp.escape(entry.key.substring(end, match.start)))
        ..write('(.*?)');
      captureIndexes.add(int.tryParse(match.group(1) ?? '') ?? sequential++);
      end = match.end;
    }
    pattern
      ..write(RegExp.escape(entry.key.substring(end)))
      ..write(r'$');
    expression = RegExp(pattern.toString());
  }

  final MapEntry<String, String> entry;
  final captureIndexes = <int>[];
  late final RegExp expression;

  String? translate(String value) {
    final match = expression.firstMatch(value);
    if (match == null) return null;
    var sequential = 1;
    return entry.value.replaceAllMapped(_placeholder, (placeholder) {
      final index = int.tryParse(placeholder.group(1) ?? '') ?? sequential++;
      final capture = captureIndexes.indexOf(index);
      return capture < 0 ? placeholder.group(0)! : match.group(capture + 1)!;
    });
  }
}

String tr(BuildContext context, String value) =>
    NtfyLocalizations.of(context).translate(value);

class _NtfyLocalizationsDelegate
    extends LocalizationsDelegate<NtfyLocalizations> {
  const _NtfyLocalizationsDelegate();

  static Map<String, Object?>? _all;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<NtfyLocalizations> load(Locale locale) {
    if (locale.languageCode == 'en') {
      return SynchronousFuture(NtfyLocalizations(locale, const {}));
    }
    return _load(locale);
  }

  Future<NtfyLocalizations> _load(Locale locale) async {
    _all ??= Map<String, Object?>.from(
      jsonDecode(await rootBundle.loadString('assets/i18n.json')) as Map,
    );
    final tag = locale.countryCode == null
        ? locale.languageCode
        : '${locale.languageCode}-${locale.countryCode}';
    final values = _all![tag] ?? _all![locale.languageCode];
    return NtfyLocalizations(
      locale,
      values is Map ? Map<String, String>.from(values) : const {},
    );
  }

  @override
  bool shouldReload(_NtfyLocalizationsDelegate old) => false;
}

class LText extends StatelessWidget {
  const LText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) => Text(
    NtfyLocalizations.of(context).translate(data),
    style: style,
    strutStyle: strutStyle,
    textAlign: textAlign,
    textDirection: textDirection,
    locale: locale,
    softWrap: softWrap,
    overflow: overflow,
    textScaler: textScaler,
    maxLines: maxLines,
    semanticsLabel: semanticsLabel,
    textWidthBasis: textWidthBasis,
    textHeightBehavior: textHeightBehavior,
    selectionColor: selectionColor,
  );
}
