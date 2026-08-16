// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'ntfy_client.dart';

class AppDatabase {
  static const _globalRetentionKey = 'global_retention_seconds';

  AppDatabase({Database? database, String? path})
    : _database = database,
      _path = path;

  Database? _database;
  final String? _path;

  Future<void> initialize() async {
    if (_database != null) {
      await _database!.execute('PRAGMA foreign_keys = ON');
      await _createSchema(_database!);
      return;
    }
    final path =
        _path ??
        '${await getDatabasesPath()}${Platform.pathSeparator}ntfy_flutter.db';
    _database = await openDatabase(
      path,
      version: 3,
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      onCreate: (database, _) => _createSchema(database),
      onUpgrade: _upgradeSchema,
    );
  }

  Future<Subscription> addSubscription(
    String baseUrl,
    String topic, {
    String? displayName,
    List<NtfyEvent> initialEvents = const [],
  }) async {
    final database = _requireDatabase;
    return database.transaction((transaction) async {
      final createdAt = DateTime.now().toUtc();
      final id = await transaction.insert('subscriptions', {
        'base_url': baseUrl,
        'topic': topic,
        'display_name': _cleanDisplayName(displayName),
        'created_at': createdAt.millisecondsSinceEpoch,
      });
      final subscription = Subscription(
        id: id,
        baseUrl: baseUrl,
        topic: topic,
        displayName: _cleanDisplayName(displayName),
        createdAt: createdAt,
      );
      await _applyEvents(
        transaction,
        subscription,
        initialEvents,
        markRead: true,
      );
      return _readSubscription(transaction, id);
    });
  }

  Future<List<StoredMessage>> applyEvents(
    Subscription subscription,
    List<NtfyEvent> events, {
    bool markRead = false,
  }) => _requireDatabase.transaction(
    (transaction) =>
        _applyEvents(transaction, subscription, events, markRead: markRead),
  );

  Future<List<Subscription>> readSubscriptions() async {
    final rows = await _requireDatabase.query(
      'subscriptions',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(_subscriptionFromRow).toList(growable: false);
  }

  Future<List<TopicSummary>> readSummaries() async {
    final subscriptions = await readSubscriptions();
    final summaries = <TopicSummary>[];
    for (final subscription in subscriptions) {
      final unread = Sqflite.firstIntValue(
        await _requireDatabase.rawQuery(
          'SELECT COUNT(*) FROM messages '
          'WHERE subscription_id = ? AND is_read = 0',
          [subscription.id],
        ),
      );
      final latestRows = await _requireDatabase.query(
        'messages',
        where: 'subscription_id = ?',
        whereArgs: [subscription.id],
        orderBy: 'event_time DESC, id DESC',
        limit: 1,
      );
      summaries.add(
        TopicSummary(
          subscription: subscription,
          unreadCount: unread ?? 0,
          latestMessage: latestRows.isEmpty
              ? null
              : _messageFromRow(latestRows.single),
        ),
      );
    }
    return summaries;
  }

  Future<List<StoredMessage>> listMessages(int subscriptionId) async {
    final rows = await _requireDatabase.query(
      'messages',
      where: 'subscription_id = ?',
      whereArgs: [subscriptionId],
      orderBy: 'event_time DESC, id DESC',
    );
    return rows.map(_messageFromRow).toList(growable: false);
  }

  Future<void> markRead(int subscriptionId) => _requireDatabase.update(
    'messages',
    {'is_read': 1},
    where: 'subscription_id = ?',
    whereArgs: [subscriptionId],
  );

  Future<void> deleteMessage(int messageId) => _requireDatabase.delete(
    'messages',
    where: 'id = ?',
    whereArgs: [messageId],
  );

  Future<void> clearMessages(int subscriptionId) => _requireDatabase.delete(
    'messages',
    where: 'subscription_id = ?',
    whereArgs: [subscriptionId],
  );

  Future<int> readGlobalRetentionSeconds() async {
    final rows = await _requireDatabase.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_globalRetentionKey],
      limit: 1,
    );
    return rows.isEmpty ? 0 : int.tryParse(rows.single['value'] as String) ?? 0;
  }

  Future<void> setGlobalRetentionSeconds(int seconds) async {
    if (seconds < 0) throw ArgumentError.value(seconds, 'seconds');
    await _requireDatabase.insert('settings', {
      'key': _globalRetentionKey,
      'value': seconds.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setDisplayName(int subscriptionId, String? displayName) =>
      _requireDatabase.update(
        'subscriptions',
        {'display_name': _cleanDisplayName(displayName)},
        where: 'id = ?',
        whereArgs: [subscriptionId],
      );

  Future<void> setSubscriptionRetentionSeconds(
    int subscriptionId,
    int? seconds,
  ) async {
    if (seconds != null && seconds < 0) {
      throw ArgumentError.value(seconds, 'seconds');
    }
    await _requireDatabase.update(
      'subscriptions',
      {'retention_seconds': seconds},
      where: 'id = ?',
      whereArgs: [subscriptionId],
    );
  }

  Future<Set<int>> deleteExpiredMessages({
    int? subscriptionId,
    DateTime? now,
  }) async {
    final globalSeconds = await readGlobalRetentionSeconds();
    final subscriptions = await _requireDatabase.query(
      'subscriptions',
      columns: ['id', 'retention_seconds'],
      where: subscriptionId == null ? null : 'id = ?',
      whereArgs: subscriptionId == null ? null : [subscriptionId],
    );
    final nowMillis = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final deletedIds = <int>{};
    await _requireDatabase.transaction((transaction) async {
      for (final subscription in subscriptions) {
        final id = subscription['id'] as int;
        final seconds =
            subscription['retention_seconds'] as int? ?? globalSeconds;
        if (seconds <= 0) continue;
        final cutoff = nowMillis - seconds * Duration.millisecondsPerSecond;
        final expired = await transaction.query(
          'messages',
          columns: ['id'],
          where: 'subscription_id = ? AND event_time < ?',
          whereArgs: [id, cutoff],
        );
        deletedIds.addAll(expired.map((row) => row['id'] as int));
        if (expired.isNotEmpty) {
          await transaction.delete(
            'messages',
            where: 'subscription_id = ? AND event_time < ?',
            whereArgs: [id, cutoff],
          );
        }
      }
    });
    return deletedIds;
  }

  Future<void> unsubscribe(int subscriptionId) => _requireDatabase.delete(
    'subscriptions',
    where: 'id = ?',
    whereArgs: [subscriptionId],
  );

  Future<bool> hasSubscriptionsForBase(String baseUrl) async =>
      Sqflite.firstIntValue(
        await _requireDatabase.rawQuery(
          'SELECT COUNT(*) FROM subscriptions WHERE base_url = ?',
          [baseUrl],
        ),
      ) !=
      0;

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Database get _requireDatabase {
    final database = _database;
    if (database == null) {
      throw StateError('Database has not been initialized');
    }
    return database;
  }

  static Future<void> _createSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS subscriptions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        base_url TEXT NOT NULL,
        topic TEXT NOT NULL,
        last_event_id TEXT,
        created_at INTEGER NOT NULL,
        retention_seconds INTEGER,
        display_name TEXT,
        UNIQUE(base_url, topic)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subscription_id INTEGER NOT NULL,
        event_id TEXT NOT NULL,
        event_time INTEGER NOT NULL,
        message TEXT NOT NULL,
        title TEXT,
        priority INTEGER NOT NULL,
        tags TEXT NOT NULL,
        is_read INTEGER NOT NULL,
        UNIQUE(subscription_id, event_id),
        FOREIGN KEY(subscription_id) REFERENCES subscriptions(id)
          ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await database.execute(
        'ALTER TABLE subscriptions ADD COLUMN retention_seconds INTEGER',
      );
      await database.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await database.execute(
        'ALTER TABLE subscriptions ADD COLUMN display_name TEXT',
      );
    }
  }

  static Future<List<StoredMessage>> _applyEvents(
    DatabaseExecutor database,
    Subscription subscription,
    List<NtfyEvent> events, {
    required bool markRead,
  }) async {
    final inserted = <StoredMessage>[];
    String? cursor;
    for (final event in events) {
      if (event.topic != subscription.topic) continue;
      cursor = event.id;
      if (!event.isMessage) continue;
      final existing = Sqflite.firstIntValue(
        await database.rawQuery(
          'SELECT COUNT(*) FROM messages '
          'WHERE subscription_id = ? AND event_id = ?',
          [subscription.id, event.id],
        ),
      );
      if (existing != 0) continue;
      final id = await database.insert('messages', {
        'subscription_id': subscription.id,
        'event_id': event.id,
        'event_time': event.time.millisecondsSinceEpoch,
        'message': event.message ?? '',
        'title': event.title,
        'priority': event.priority,
        'tags': encodeTags(event.tags),
        'is_read': markRead ? 1 : 0,
      });
      inserted.add(
        StoredMessage(
          id: id,
          subscriptionId: subscription.id,
          eventId: event.id,
          time: event.time,
          message: event.message ?? '',
          title: event.title,
          priority: event.priority,
          tags: event.tags,
          isRead: markRead,
        ),
      );
    }
    if (cursor != null) {
      await database.update(
        'subscriptions',
        {'last_event_id': cursor},
        where: 'id = ?',
        whereArgs: [subscription.id],
      );
    }
    return inserted;
  }

  static Future<Subscription> _readSubscription(
    DatabaseExecutor database,
    int id,
  ) async {
    final rows = await database.query(
      'subscriptions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return _subscriptionFromRow(rows.single);
  }

  static Subscription _subscriptionFromRow(Map<String, Object?> row) =>
      Subscription(
        id: row['id'] as int,
        baseUrl: row['base_url'] as String,
        topic: row['topic'] as String,
        lastEventId: row['last_event_id'] as String?,
        retentionSeconds: row['retention_seconds'] as int?,
        displayName: row['display_name'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          row['created_at'] as int,
          isUtc: true,
        ),
      );

  static String? _cleanDisplayName(String? displayName) {
    final cleaned = displayName?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }

  static StoredMessage _messageFromRow(Map<String, Object?> row) =>
      StoredMessage(
        id: row['id'] as int,
        subscriptionId: row['subscription_id'] as int,
        eventId: row['event_id'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(
          row['event_time'] as int,
          isUtc: true,
        ),
        message: row['message'] as String,
        title: row['title'] as String?,
        priority: row['priority'] as int,
        tags: decodeTags(row['tags'] as String),
        isRead: (row['is_read'] as int) != 0,
      );
}

class CredentialStore {
  CredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<AuthCredential> read(String baseUrl) async {
    final value = await _storage.read(key: _key(baseUrl));
    if (value == null) return const AuthCredential.none();
    final json = jsonDecode(value);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid stored credentials');
    }
    return AuthCredential.fromJson(json);
  }

  Future<void> write(String baseUrl, AuthCredential credential) async {
    final key = _key(baseUrl);
    if (credential.type == AuthType.none) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: jsonEncode(credential.toJson()));
    }
  }

  Future<void> delete(String baseUrl) => _storage.delete(key: _key(baseUrl));

  static String _key(String baseUrl) {
    final normalized = NtfyClient.normalizeBaseUrl(baseUrl);
    return 'ntfy.credentials.${base64UrlEncode(utf8.encode(normalized))}';
  }
}
