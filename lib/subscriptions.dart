import 'package:sqflite/sqflite.dart';

class Subscription {
  const Subscription({required this.id, required this.url, this.displayName});

  final int id;
  final String url;
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      other is Subscription &&
      id == other.id &&
      url == other.url &&
      displayName == other.displayName;

  @override
  int get hashCode => Object.hash(id, url, displayName);
}

class SubscriptionException implements Exception {
  const SubscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class SubscriptionRepository {
  Future<Subscription> add({required String url, String? displayName});

  Future<List<Subscription>> all();
}

class SubscriptionStore implements SubscriptionRepository {
  SubscriptionStore._(this._database);

  final Database _database;

  static Future<SubscriptionStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final selectedFactory = factory ?? databaseFactory;
    final selectedPath =
        path ?? '${await selectedFactory.getDatabasesPath()}/ntfy.db';
    final database = await selectedFactory.openDatabase(
      selectedPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) => database.execute('''
          CREATE TABLE subscriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL UNIQUE,
            display_name TEXT
          )
        '''),
      ),
    );
    return SubscriptionStore._(database);
  }

  @override
  Future<Subscription> add({required String url, String? displayName}) async {
    final normalizedUrl = normalizeUrl(url);
    final normalizedName = displayName?.trim();
    try {
      final id = await _database.insert('subscriptions', {
        'url': normalizedUrl,
        'display_name': normalizedName?.isEmpty == true ? null : normalizedName,
      });
      return Subscription(
        id: id,
        url: normalizedUrl,
        displayName: normalizedName?.isEmpty == true ? null : normalizedName,
      );
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const SubscriptionException(
          'You are already subscribed to this topic.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<Subscription>> all() async {
    final rows = await _database.query('subscriptions', orderBy: 'id');
    return rows
        .map(
          (row) => Subscription(
            id: row['id']! as int,
            url: row['url']! as String,
            displayName: row['display_name'] as String?,
          ),
        )
        .toList();
  }

  Future<void> close() => _database.close();

  static String normalizeUrl(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (value.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const SubscriptionException(
        'Enter a complete topic URL, such as https://ntfy.sh/mytopic.',
      );
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const SubscriptionException('Topic URLs must use HTTP or HTTPS.');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const SubscriptionException(
        'Authenticated topic URLs are not supported yet.',
      );
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw const SubscriptionException(
        'Remove query parameters and fragments from the topic URL.',
      );
    }
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      throw const SubscriptionException(
        'The URL must include a topic, such as https://ntfy.sh/mytopic.',
      );
    }
    if (!RegExp(r'^[-_A-Za-z0-9]{1,64}$').hasMatch(segments.last)) {
      throw const SubscriptionException(
        'Topic names may contain only letters, numbers, hyphens, and underscores, up to 64 characters.',
      );
    }
    final defaultPort =
        (scheme == 'http' && uri.port == 80) ||
        (scheme == 'https' && uri.port == 443);
    return Uri(
      scheme: scheme,
      host: uri.host.toLowerCase(),
      port: uri.hasPort && !defaultPort ? uri.port : null,
      pathSegments: segments,
    ).toString();
  }
}
