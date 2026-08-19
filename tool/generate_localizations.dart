import 'dart:convert';
import 'dart:io';

// Generates assets/i18n.json from Apache-2.0-licensed ntfy Android resources.
// See LICENSE and NOTICE in this repository for attribution and terms.

const _languages = <String, String>{
  'en': 'values',
  'bg': 'values-bg',
  'ca': 'values-ca',
  'cs': 'values-cs',
  'de': 'values-de',
  'es': 'values-es',
  'et': 'values-et',
  'fi': 'values-fi',
  'fr': 'values-fr',
  'gl': 'values-gl',
  'in': 'values-in',
  'it': 'values-it',
  'iw': 'values-iw',
  'ja': 'values-ja',
  'ko': 'values-ko',
  'nb-NO': 'values-nb-rNO',
  'nl': 'values-nl',
  'pl': 'values-pl',
  'pt': 'values-pt',
  'pt-BR': 'values-pt-rBR',
  'ro': 'values-ro',
  'ru': 'values-ru',
  'sk': 'values-sk',
  'sv': 'values-sv',
  'ta': 'values-ta',
  'tr': 'values-tr',
  'uk': 'values-uk',
  'uz': 'values-uz',
  'vi': 'values-vi',
  'zh-CN': 'values-zh-rCN',
  'zh-TW': 'values-zh-rTW',
};

void main() {
  final root = Directory('../ntfy-android/app/src/main/res');
  if (!root.existsSync()) {
    stderr.writeln('Run from the ntfy_flutter repository root.');
    exitCode = 1;
    return;
  }
  final english = _readStrings(File('${root.path}/values/strings.xml'));
  final output = <String, Map<String, String>>{};
  for (final language in _languages.entries) {
    final translated = _readStrings(
      File('${root.path}/${language.value}/strings.xml'),
    );
    final values = <String, String>{};
    for (final entry in english.entries) {
      final translatedValue = translated[entry.key];
      if (translatedValue != null) values[entry.value] = translatedValue;
    }
    output[language.key] = values;
  }
  File('assets/i18n.json').writeAsStringSync(jsonEncode(output));
}

Map<String, String> _readStrings(File file) {
  if (!file.existsSync()) return const {};
  final result = <String, String>{};
  final expression = RegExp(
    r'<string\s+name="([^"]+)"[^>]*>([\s\S]*?)</string>',
  );
  for (final match in expression.allMatches(file.readAsStringSync())) {
    result[match.group(1)!] = _decode(match.group(2)!);
  }
  return result;
}

String _decode(String value) => value
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll(r'\n', '\n')
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&')
    .trim();
