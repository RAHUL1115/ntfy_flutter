import 'dart:convert';

import 'package:flutter/services.dart';

class EmojiTags {
  EmojiTags._();

  static Future<Map<String, String>>? _aliases;
  static final _prefixes = <String, Future<String>>{};
  static final _unmatchedTags = <String, Future<List<String>>>{};

  static Future<String> prefix(Iterable<String> tags) {
    if (tags.isEmpty) return Future.value('');
    final values = tags.toList(growable: false);
    return _prefixes.putIfAbsent(values.join('\u0000'), () => _prefix(values));
  }

  static Future<String> _prefix(List<String> tags) async {
    final aliases = await (_aliases ??= _load());
    return tags
        .map((tag) => tag.replaceAll(':', ''))
        .map((tag) => aliases[tag])
        .whereType<String>()
        .join();
  }

  static Future<List<String>> unmatched(Iterable<String> tags) {
    if (tags.isEmpty) return Future.value(const []);
    final values = tags.toList(growable: false);
    return _unmatchedTags.putIfAbsent(
      values.join('\u0000'),
      () => _unmatched(values),
    );
  }

  static Future<List<String>> _unmatched(List<String> tags) async {
    final aliases = await (_aliases ??= _load());
    return tags
        .where((tag) => !aliases.containsKey(tag.replaceAll(':', '')))
        .toList(growable: false);
  }

  static Future<Map<String, String>> _load() async {
    final decoded =
        jsonDecode(await rootBundle.loadString('assets/emoji.json')) as List;
    return {
      for (final value in decoded)
        for (final alias in (value['aliases'] as List))
          alias as String: value['emoji']! as String,
    };
  }
}
