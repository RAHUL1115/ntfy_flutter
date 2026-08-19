import 'dart:convert';

import 'package:flutter/services.dart';

class EmojiTags {
  EmojiTags._();

  static Future<Map<String, String>>? _aliases;

  static Future<String> prefix(Iterable<String> tags) async {
    if (tags.isEmpty) return '';
    final aliases = await (_aliases ??= _load());
    return tags
        .map((tag) => tag.replaceAll(':', ''))
        .map((tag) => aliases[tag])
        .whereType<String>()
        .join();
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
