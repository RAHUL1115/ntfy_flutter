import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'messages.dart';

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

  Future<void> remove(int subscriptionId);
}

abstract interface class AppRepository
    implements SubscriptionRepository, MessageRepository {}

class SubscriptionStore implements AppRepository {
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
        version: 2,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE subscriptions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              url TEXT NOT NULL UNIQUE,
              display_name TEXT,
              last_message_id TEXT
            )
          ''');
          await _createMessagesSchema(database);
        },
        onUpgrade: (database, oldVersion, _) async {
          if (oldVersion < 2) {
            await database.execute(
              'ALTER TABLE subscriptions ADD COLUMN last_message_id TEXT',
            );
            await _createMessagesSchema(database);
          }
        },
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

  @override
  Future<void> remove(int subscriptionId) => _database.delete(
    'subscriptions',
    where: 'id = ?',
    whereArgs: [subscriptionId],
  );

  @override
  Future<FeedSnapshot> loadFeed(int subscriptionId) =>
      _database.transaction((transaction) async {
        final subscriptionRows = await transaction.query(
          'subscriptions',
          columns: ['last_message_id'],
          where: 'id = ?',
          whereArgs: [subscriptionId],
          limit: 1,
        );
        if (subscriptionRows.isEmpty) {
          throw StateError('Subscription $subscriptionId does not exist.');
        }
        final rows = await transaction.query(
          'messages',
          where: 'subscription_id = ?',
          whereArgs: [subscriptionId],
          orderBy: 'event_time ASC, local_id ASC',
        );
        return FeedSnapshot(
          cursor: subscriptionRows.single['last_message_id'] as String?,
          messages: rows.map(_storedMessageFromRow).toList(),
        );
      });

  @override
  Future<StoredMessage?> ingest(int subscriptionId, IncomingMessage message) =>
      _database.transaction((transaction) async {
        final localId = await transaction.insert('messages', {
          'subscription_id': subscriptionId,
          'event_id': message.eventId,
          'event_time': message.time.toUtc().millisecondsSinceEpoch,
          'message': message.message,
          'title': message.title,
          'priority': message.priority,
          'tags': jsonEncode(message.tags),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (localId == 0) return null;

        await transaction.update(
          'subscriptions',
          {'last_message_id': message.eventId},
          where: 'id = ?',
          whereArgs: [subscriptionId],
        );
        return StoredMessage(
          localId: localId,
          subscriptionId: subscriptionId,
          eventId: message.eventId,
          time: message.time.toUtc(),
          message: message.message,
          title: message.title,
          priority: message.priority,
          tags: List.unmodifiable(message.tags),
        );
      });

  @override
  Future<void> deleteMessage(int subscriptionId, int localId) =>
      _database.delete(
        'messages',
        where: 'subscription_id = ? AND local_id = ?',
        whereArgs: [subscriptionId, localId],
      );

  @override
  Future<void> restoreMessage(int subscriptionId, StoredMessage message) async {
    if (message.subscriptionId != subscriptionId) {
      throw ArgumentError.value(
        message.subscriptionId,
        'message.subscriptionId',
        'Must match the selected subscription.',
      );
    }
    await _database.insert('messages', {
      'local_id': message.localId,
      'subscription_id': subscriptionId,
      'event_id': message.eventId,
      'event_time': message.time.toUtc().millisecondsSinceEpoch,
      'message': message.message,
      'title': message.title,
      'priority': message.priority,
      'tags': jsonEncode(message.tags),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<void> clearMessages(int subscriptionId) => _database.delete(
    'messages',
    where: 'subscription_id = ?',
    whereArgs: [subscriptionId],
  );

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

Future<void> _createMessagesSchema(DatabaseExecutor database) async {
  await database.execute('''
    CREATE TABLE messages (
      local_id INTEGER PRIMARY KEY AUTOINCREMENT,
      subscription_id INTEGER NOT NULL,
      event_id TEXT NOT NULL,
      event_time INTEGER NOT NULL,
      message TEXT NOT NULL,
      title TEXT,
      priority INTEGER NOT NULL,
      tags TEXT NOT NULL,
      UNIQUE(subscription_id, event_id),
      FOREIGN KEY(subscription_id) REFERENCES subscriptions(id) ON DELETE CASCADE
    )
  ''');
  await database.execute('''
    CREATE INDEX messages_subscription_time
    ON messages(subscription_id, event_time, local_id)
  ''');
}

StoredMessage _storedMessageFromRow(Map<String, Object?> row) => StoredMessage(
  localId: row['local_id']! as int,
  subscriptionId: row['subscription_id']! as int,
  eventId: row['event_id']! as String,
  time: DateTime.fromMillisecondsSinceEpoch(
    row['event_time']! as int,
    isUtc: true,
  ),
  message: row['message']! as String,
  title: row['title'] as String?,
  priority: row['priority']! as int,
  tags: List.unmodifiable(
    (jsonDecode(row['tags']! as String) as List).cast<String>(),
  ),
);
