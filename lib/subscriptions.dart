import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import 'messages.dart';
import 'notification_policy.dart';
import 'retention.dart';

class Subscription {
  const Subscription({
    required this.id,
    required this.url,
    this.displayName,
    this.unreadCount = 0,
    this.totalCount = 0,
    this.lastActivity,
    this.backgroundEnabled = true,
    this.unifiedPushApp,
    this.unifiedPushToken,
  });

  final int id;
  final String url;
  final String? displayName;
  final int unreadCount;
  final int totalCount;
  final DateTime? lastActivity;
  final bool backgroundEnabled;
  final String? unifiedPushApp;
  final String? unifiedPushToken;

  @override
  bool operator ==(Object other) =>
      other is Subscription &&
      id == other.id &&
      url == other.url &&
      displayName == other.displayName &&
      unreadCount == other.unreadCount &&
      totalCount == other.totalCount &&
      lastActivity == other.lastActivity &&
      backgroundEnabled == other.backgroundEnabled &&
      unifiedPushApp == other.unifiedPushApp &&
      unifiedPushToken == other.unifiedPushToken;

  @override
  int get hashCode => Object.hash(
    id,
    url,
    displayName,
    unreadCount,
    totalCount,
    lastActivity,
    backgroundEnabled,
    unifiedPushApp,
    unifiedPushToken,
  );
}

class UnifiedPushRegistration {
  const UnifiedPushRegistration({
    required this.application,
    required this.token,
    required this.endpoint,
  });

  final String application;
  final String token;
  final String endpoint;
}

abstract interface class UnifiedPushRepository {
  Future<UnifiedPushRegistration> registerUnifiedPush({
    required String application,
    required String token,
    required String baseUrl,
  });

  Future<UnifiedPushRegistration?> unregisterUnifiedPush(String token);
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

  Future<Subscription> rename(int subscriptionId, String? displayName);

  Future<void> markRead(int subscriptionId);

  Future<void> remove(int subscriptionId);
}

abstract interface class BackgroundListeningRepository {
  Future<bool> loadBackgroundListening();

  Future<void> setBackgroundListening(bool enabled);
}

abstract interface class TopicDeliveryRepository {
  Future<Subscription> setTopicBackgroundEnabled(
    int subscriptionId,
    bool enabled,
  );
}

abstract interface class AppRepository
    implements
        SubscriptionRepository,
        MessageRepository,
        RetentionRepository,
        BackgroundListeningRepository {}

class SubscriptionStore
    implements
        AppRepository,
        NotificationPolicyRepository,
        TopicNotificationPolicyRepository,
        TopicDeliveryRepository,
        UnifiedPushRepository,
        AttachmentRepository {
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
        version: 11,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE subscriptions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              url TEXT NOT NULL UNIQUE,
              display_name TEXT,
              last_message_id TEXT,
              retention_seconds INTEGER,
              muted_until INTEGER,
              minimum_priority INTEGER,
              insistent_max_priority INTEGER,
              attachment_download INTEGER,
              subscription_icon_path TEXT,
              dedicated_channel INTEGER,
              background_enabled INTEGER NOT NULL DEFAULT 1,
              up_app_id TEXT,
              up_connector_token TEXT UNIQUE
            )
          ''');
          await _createMessagesSchema(database);
          await _createRetentionSettingsSchema(database);
        },
        onUpgrade: (database, oldVersion, _) async {
          if (oldVersion < 2) {
            await database.execute(
              'ALTER TABLE subscriptions ADD COLUMN last_message_id TEXT',
            );
            await _createMessagesSchema(database);
          }
          if (oldVersion < 3) {
            await database.execute(
              'ALTER TABLE subscriptions ADD COLUMN retention_seconds INTEGER',
            );
            await _createRetentionSettingsSchema(database);
          }
          if (oldVersion < 4) {
            await _addBackgroundListeningColumn(database);
          }
          if (oldVersion >= 2 && oldVersion < 5) {
            await database.execute(
              'ALTER TABLE messages ADD COLUMN is_read INTEGER NOT NULL DEFAULT 1',
            );
          }
          if (oldVersion < 6) await _addNotificationPolicyColumns(database);
          if (oldVersion < 7) {
            await database.execute(
              'ALTER TABLE subscriptions ADD COLUMN background_enabled INTEGER NOT NULL DEFAULT 1',
            );
          }
          if (oldVersion < 8) {
            final columns = await database.rawQuery(
              'PRAGMA table_info(messages)',
            );
            if (!columns.any((column) => column['name'] == 'attachment_json')) {
              await database.execute(
                'ALTER TABLE messages ADD COLUMN attachment_json TEXT',
              );
            }
          }
          if (oldVersion < 9) {
            await _addExtendedNotificationPolicyColumns(database);
          }
          if (oldVersion < 10) await _addExtendedMessageColumns(database);
          if (oldVersion < 11) {
            await database.execute(
              'ALTER TABLE subscriptions ADD COLUMN up_app_id TEXT',
            );
            await database.execute(
              'ALTER TABLE subscriptions ADD COLUMN up_connector_token TEXT',
            );
            await database.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS subscriptions_up_token ON subscriptions(up_connector_token)',
            );
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
    final rows = await _database.rawQuery('''
      SELECT subscriptions.*,
        SUM(CASE WHEN messages.is_read = 0 THEN 1 ELSE 0 END) AS unread_count,
        COUNT(messages.local_id) AS total_count,
        MAX(messages.event_time) AS last_activity
      FROM subscriptions
      LEFT JOIN messages ON messages.subscription_id = subscriptions.id
      GROUP BY subscriptions.id
      ORDER BY last_activity DESC, subscriptions.id
    ''');
    return rows
        .map(
          (row) => Subscription(
            id: row['id']! as int,
            url: row['url']! as String,
            displayName: row['display_name'] as String?,
            unreadCount: row['unread_count']! as int,
            totalCount: row['total_count']! as int,
            lastActivity: row['last_activity'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    row['last_activity']! as int,
                    isUtc: true,
                  ),
            backgroundEnabled: row['background_enabled'] == 1,
            unifiedPushApp: row['up_app_id'] as String?,
            unifiedPushToken: row['up_connector_token'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<UnifiedPushRegistration> registerUnifiedPush({
    required String application,
    required String token,
    required String baseUrl,
  }) async {
    if (application.trim().isEmpty || token.isEmpty) {
      throw const FormatException('Invalid UnifiedPush registration.');
    }
    final existing = await _database.query(
      'subscriptions',
      columns: ['url', 'up_app_id'],
      where: 'up_connector_token = ?',
      whereArgs: [token],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      if (existing.single['up_app_id'] != application) {
        throw StateError('The UnifiedPush token belongs to another app.');
      }
      return UnifiedPushRegistration(
        application: application,
        token: token,
        endpoint: _unifiedPushEndpoint(existing.single['url']! as String),
      );
    }
    final topic = 'up${_randomToken(12)}';
    final server = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final url = normalizeUrl('$server/$topic');
    await _database.insert('subscriptions', {
      'url': url,
      'background_enabled': 1,
      'up_app_id': application,
      'up_connector_token': token,
    });
    return UnifiedPushRegistration(
      application: application,
      token: token,
      endpoint: _unifiedPushEndpoint(url),
    );
  }

  @override
  Future<UnifiedPushRegistration?> unregisterUnifiedPush(String token) async {
    final rows = await _database.query(
      'subscriptions',
      columns: ['id', 'url', 'up_app_id'],
      where: 'up_connector_token = ?',
      whereArgs: [token],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    await remove(row['id']! as int);
    return UnifiedPushRegistration(
      application: row['up_app_id']! as String,
      token: token,
      endpoint: _unifiedPushEndpoint(row['url']! as String),
    );
  }

  @override
  Future<void> remove(int subscriptionId) async {
    final paths = await _attachmentPaths('subscription_id = ?', [
      subscriptionId,
    ]);
    await _database.delete(
      'subscriptions',
      where: 'id = ?',
      whereArgs: [subscriptionId],
    );
    await _deleteAttachmentFiles(paths);
  }

  @override
  Future<Subscription> rename(int subscriptionId, String? displayName) async {
    final normalizedName = displayName?.trim();
    final value = normalizedName?.isEmpty == true ? null : normalizedName;
    final updated = await _database.update(
      'subscriptions',
      {'display_name': value},
      where: 'id = ?',
      whereArgs: [subscriptionId],
    );
    if (updated == 0) {
      throw StateError('Subscription $subscriptionId does not exist.');
    }
    return (await all()).singleWhere((item) => item.id == subscriptionId);
  }

  @override
  Future<void> markRead(int subscriptionId) => _database.update(
    'messages',
    {'is_read': 1},
    where: 'subscription_id = ? AND is_read = 0',
    whereArgs: [subscriptionId],
  );

  @override
  Future<Subscription> setTopicBackgroundEnabled(
    int subscriptionId,
    bool enabled,
  ) async {
    final updated = await _database.update(
      'subscriptions',
      {'background_enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [subscriptionId],
    );
    if (updated == 0) {
      throw StateError('Subscription $subscriptionId does not exist.');
    }
    return (await all()).singleWhere((item) => item.id == subscriptionId);
  }

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
          orderBy: 'event_time DESC, local_id DESC',
        );
        return FeedSnapshot(
          cursor: subscriptionRows.single['last_message_id'] as String?,
          messages: rows.map(_storedMessageFromRow).toList(),
        );
      });

  @override
  Future<StoredMessage?> ingest(
    int subscriptionId,
    IncomingMessage message,
  ) async {
    final deletedPaths = message.event == MessageEventType.delete
        ? await _attachmentPaths('subscription_id = ? AND sequence_id = ?', [
            subscriptionId,
            message.sequenceId,
          ])
        : const <String>[];
    final stored = await _database.transaction((transaction) async {
      if (message.event != MessageEventType.message) {
        if (message.event == MessageEventType.clear) {
          await transaction.update(
            'messages',
            {'is_read': 1},
            where: 'subscription_id = ? AND sequence_id = ?',
            whereArgs: [subscriptionId, message.sequenceId],
          );
        } else {
          await transaction.delete(
            'messages',
            where: 'subscription_id = ? AND sequence_id = ?',
            whereArgs: [subscriptionId, message.sequenceId],
          );
        }
        await transaction.update(
          'subscriptions',
          {'last_message_id': message.eventId},
          where: 'id = ?',
          whereArgs: [subscriptionId],
        );
        return null;
      }
      final localId = await transaction.insert('messages', {
        'subscription_id': subscriptionId,
        'event_id': message.eventId,
        'sequence_id': message.sequenceId,
        'event_time': message.time.toUtc().millisecondsSinceEpoch,
        'message': message.message,
        'title': message.title,
        'priority': message.priority,
        'tags': jsonEncode(message.tags),
        'click': message.click,
        'icon': message.icon,
        'actions_json': jsonEncode(
          message.actions.map((action) => action.toJson()).toList(),
        ),
        'content_type': message.contentType,
        'encoding': message.encoding,
        'is_read': 0,
        'attachment_json': message.attachment == null
            ? null
            : jsonEncode(message.attachment!.toJson()),
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
        sequenceId: message.sequenceId,
        time: message.time.toUtc(),
        message: message.message,
        title: message.title,
        priority: message.priority,
        tags: List.unmodifiable(message.tags),
        click: message.click,
        icon: message.icon,
        actions: List.unmodifiable(message.actions),
        contentType: message.contentType,
        encoding: message.encoding,
        attachment: message.attachment,
      );
    });
    await _deleteAttachmentFiles(deletedPaths);
    return stored;
  }

  @override
  Future<void> deleteMessage(int subscriptionId, int localId) async {
    final paths = await _attachmentPaths(
      'subscription_id = ? AND local_id = ?',
      [subscriptionId, localId],
    );
    await _database.delete(
      'messages',
      where: 'subscription_id = ? AND local_id = ?',
      whereArgs: [subscriptionId, localId],
    );
    await _deleteAttachmentFiles(paths);
  }

  @override
  Future<void> setAttachmentLocalPath(
    int subscriptionId,
    int localId,
    String localPath,
  ) async {
    final rows = await _database.query(
      'messages',
      columns: ['attachment_json'],
      where: 'subscription_id = ? AND local_id = ?',
      whereArgs: [subscriptionId, localId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Message $localId does not exist.');
    final attachment = MessageAttachment.fromJson(
      jsonDecode(rows.single['attachment_json']! as String),
    );
    if (attachment == null) throw StateError('Message has no attachment.');
    await _database.update(
      'messages',
      {
        'attachment_json': jsonEncode(
          MessageAttachment(
            name: attachment.name,
            url: attachment.url,
            type: attachment.type,
            size: attachment.size,
            expires: attachment.expires,
            localPath: localPath,
          ).toJson(),
        ),
      },
      where: 'subscription_id = ? AND local_id = ?',
      whereArgs: [subscriptionId, localId],
    );
  }

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
      'sequence_id': message.sequenceId,
      'event_time': message.time.toUtc().millisecondsSinceEpoch,
      'message': message.message,
      'title': message.title,
      'priority': message.priority,
      'tags': jsonEncode(message.tags),
      'click': message.click,
      'icon': message.icon,
      'actions_json': jsonEncode(
        message.actions.map((action) => action.toJson()).toList(),
      ),
      'content_type': message.contentType,
      'encoding': message.encoding,
      'is_read': 1,
      'attachment_json': message.attachment == null
          ? null
          : jsonEncode(message.attachment!.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<void> clearMessages(int subscriptionId) async {
    final paths = await _attachmentPaths('subscription_id = ?', [
      subscriptionId,
    ]);
    await _database.delete(
      'messages',
      where: 'subscription_id = ?',
      whereArgs: [subscriptionId],
    );
    await _deleteAttachmentFiles(paths);
  }

  @override
  Future<RetentionSettings> loadRetention({int? subscriptionId}) =>
      _database.transaction((transaction) async {
        final settingsRows = await transaction.query(
          'app_settings',
          columns: ['retention_seconds'],
          where: 'id = 1',
          limit: 1,
        );
        if (settingsRows.isEmpty) {
          throw StateError('Global retention settings are missing.');
        }
        final global = RetentionPeriod.fromSeconds(
          settingsRows.single['retention_seconds']! as int,
        );
        if (subscriptionId == null) {
          return RetentionSettings(global: global);
        }
        final subscriptionRows = await transaction.query(
          'subscriptions',
          columns: ['retention_seconds'],
          where: 'id = ?',
          whereArgs: [subscriptionId],
          limit: 1,
        );
        if (subscriptionRows.isEmpty) {
          throw StateError('Subscription $subscriptionId does not exist.');
        }
        final seconds = subscriptionRows.single['retention_seconds'] as int?;
        return RetentionSettings(
          global: global,
          override: seconds == null
              ? null
              : RetentionPeriod.fromSeconds(seconds),
        );
      });

  @override
  Future<bool> loadBackgroundListening() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['background_listening'],
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Background listening settings are missing.');
    }
    return rows.single['background_listening'] == 1;
  }

  @override
  Future<void> setBackgroundListening(bool enabled) async {
    final updated = await _database.update('app_settings', {
      'background_listening': enabled ? 1 : 0,
    }, where: 'id = 1');
    if (updated == 0) {
      throw StateError('Background listening settings are missing.');
    }
  }

  @override
  Future<NotificationPolicy> loadNotificationPolicy({
    int? subscriptionId,
  }) => _database.transaction((transaction) async {
    final globalRows = await transaction.query(
      'app_settings',
      columns: [
        'muted_until',
        'minimum_priority',
        'insistent_max_priority',
        'attachment_download',
        'subscription_icon_path',
        'dedicated_channel',
      ],
      where: 'id = 1',
      limit: 1,
    );
    if (globalRows.isEmpty) throw StateError('Global settings are missing.');
    var row = globalRows.single;
    if (subscriptionId != null) {
      final topicRows = await transaction.query(
        'subscriptions',
        columns: [
          'muted_until',
          'minimum_priority',
          'insistent_max_priority',
          'attachment_download',
          'subscription_icon_path',
          'dedicated_channel',
        ],
        where: 'id = ?',
        whereArgs: [subscriptionId],
        limit: 1,
      );
      if (topicRows.isEmpty) {
        throw StateError('Subscription $subscriptionId does not exist.');
      }
      final topic = topicRows.single;
      row = {
        'muted_until': topic['muted_until'] ?? row['muted_until'],
        'minimum_priority':
            topic['minimum_priority'] ?? row['minimum_priority'],
        'insistent_max_priority':
            topic['insistent_max_priority'] ?? row['insistent_max_priority'],
        'attachment_download':
            topic['attachment_download'] ?? row['attachment_download'],
        'subscription_icon_path':
            topic['subscription_icon_path'] ?? row['subscription_icon_path'],
        'dedicated_channel':
            topic['dedicated_channel'] ?? row['dedicated_channel'],
      };
    }
    return NotificationPolicy(
      mutedUntilEpochSeconds: row['muted_until']! as int,
      minimumPriority: row['minimum_priority']! as int,
      insistentMaxPriority: row['insistent_max_priority'] == 1,
      attachmentDownloadMaxBytes: row['attachment_download']! as int,
      subscriptionIconPath: row['subscription_icon_path'] as String?,
      dedicatedChannel: row['dedicated_channel'] == 1,
    );
  });

  @override
  Future<void> setGlobalNotificationPolicy(NotificationPolicy policy) async {
    await _database.update('app_settings', {
      'muted_until': policy.mutedUntilEpochSeconds,
      'minimum_priority': policy.minimumPriority,
      'insistent_max_priority': policy.insistentMaxPriority ? 1 : 0,
      'attachment_download': policy.attachmentDownloadMaxBytes,
      'subscription_icon_path': policy.subscriptionIconPath,
      'dedicated_channel': policy.dedicatedChannel ? 1 : 0,
    }, where: 'id = 1');
  }

  @override
  Future<void> setTopicNotificationPolicy(
    int subscriptionId,
    NotificationPolicy? policy,
  ) async {
    final updated = await _database.update(
      'subscriptions',
      {
        'muted_until': policy?.mutedUntilEpochSeconds,
        'minimum_priority': policy?.minimumPriority,
        'insistent_max_priority': policy == null
            ? null
            : policy.insistentMaxPriority
            ? 1
            : 0,
        'attachment_download': policy?.attachmentDownloadMaxBytes,
        'subscription_icon_path': policy?.subscriptionIconPath,
        'dedicated_channel': policy == null
            ? null
            : policy.dedicatedChannel
            ? 1
            : 0,
      },
      where: 'id = ?',
      whereArgs: [subscriptionId],
    );
    if (updated == 0) {
      throw StateError('Subscription $subscriptionId does not exist.');
    }
  }

  @override
  Future<TopicNotificationPolicyOverrides> loadTopicNotificationPolicyOverrides(
    int subscriptionId,
  ) async {
    final rows = await _database.query(
      'subscriptions',
      columns: [
        'muted_until',
        'minimum_priority',
        'insistent_max_priority',
        'attachment_download',
        'subscription_icon_path',
        'dedicated_channel',
      ],
      where: 'id = ?',
      whereArgs: [subscriptionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Subscription $subscriptionId does not exist.');
    }
    final row = rows.single;
    return TopicNotificationPolicyOverrides(
      mutedUntilEpochSeconds: row['muted_until'] as int?,
      minimumPriority: row['minimum_priority'] as int?,
      insistentMaxPriority: row['insistent_max_priority'] == null
          ? null
          : row['insistent_max_priority'] == 1,
      attachmentDownloadMaxBytes: row['attachment_download'] as int?,
      subscriptionIconPath: row['subscription_icon_path'] as String?,
      dedicatedChannel: row['dedicated_channel'] == null
          ? null
          : row['dedicated_channel'] == 1,
    );
  }

  @override
  Future<void> setTopicNotificationPolicyOverrides(
    int subscriptionId,
    TopicNotificationPolicyOverrides overrides,
  ) async {
    final updated = await _database.update(
      'subscriptions',
      {
        'muted_until': overrides.mutedUntilEpochSeconds,
        'minimum_priority': overrides.minimumPriority,
        'insistent_max_priority': overrides.insistentMaxPriority == null
            ? null
            : overrides.insistentMaxPriority!
            ? 1
            : 0,
        'attachment_download': overrides.attachmentDownloadMaxBytes,
        'subscription_icon_path': overrides.subscriptionIconPath,
        'dedicated_channel': overrides.dedicatedChannel == null
            ? null
            : overrides.dedicatedChannel!
            ? 1
            : 0,
      },
      where: 'id = ?',
      whereArgs: [subscriptionId],
    );
    if (updated == 0) {
      throw StateError('Subscription $subscriptionId does not exist.');
    }
  }

  @override
  Future<void> executeRetention(RetentionCommand command) async {
    final paths = await _database.transaction((transaction) async {
      switch (command) {
        case SetGlobalRetention(:final period):
          await transaction.update('app_settings', {
            'retention_seconds': period.seconds,
          }, where: 'id = 1');
        case SetTopicRetention(:final subscriptionId, :final period):
          final updated = await transaction.update(
            'subscriptions',
            {'retention_seconds': period?.seconds},
            where: 'id = ?',
            whereArgs: [subscriptionId],
          );
          if (updated == 0) {
            throw StateError('Subscription $subscriptionId does not exist.');
          }
        case RunRetentionCleanup():
          break;
      }
      final paths = await _expiredAttachmentPaths(
        transaction,
        command.now.toUtc(),
      );
      await _cleanupExpired(transaction, command.now.toUtc());
      return paths;
    });
    await _deleteAttachmentFiles(paths);
  }

  Future<void> close() => _database.close();

  Future<Map<String, Object>> exportBackup({
    bool includeSubscriptions = true,
  }) async {
    final settings = (await _database.query(
      'app_settings',
      where: 'id = 1',
      limit: 1,
    )).single;
    final subscriptions = includeSubscriptions
        ? await _database.query(
            'subscriptions',
            columns: [
              'url',
              'display_name',
              'retention_seconds',
              'muted_until',
              'minimum_priority',
              'insistent_max_priority',
              'attachment_download',
              'dedicated_channel',
              'background_enabled',
              'up_app_id',
              'up_connector_token',
            ],
          )
        : <Map<String, Object?>>[];
    final messageRows = includeSubscriptions
        ? await _database.rawQuery('''
            SELECT subscriptions.url AS subscription_url, messages.*
            FROM messages
            JOIN subscriptions ON subscriptions.id = messages.subscription_id
            ORDER BY messages.event_time, messages.local_id
          ''')
        : <Map<String, Object?>>[];
    final messages = <Map<String, Object?>>[];
    for (final row in messageRows) {
      final attachment = row['attachment_json'] == null
          ? null
          : MessageAttachment.fromJson(
              jsonDecode(row['attachment_json']! as String),
            );
      messages.add({
        'subscription_url': row['subscription_url'],
        'event_id': row['event_id'],
        'sequence_id': row['sequence_id'],
        'event_time': row['event_time'],
        'message': row['message'],
        'title': row['title'],
        'priority': row['priority'],
        'tags': jsonDecode(row['tags']! as String),
        'click': row['click'],
        'icon': row['icon'],
        'actions': jsonDecode(row['actions_json']! as String),
        'content_type': row['content_type'],
        'encoding': row['encoding'],
        'is_read': row['is_read'],
        'attachment': attachment == null
            ? null
            : MessageAttachment(
                name: attachment.name,
                url: attachment.url,
                type: attachment.type,
                size: attachment.size,
                expires: attachment.expires,
              ).toJson(),
      });
    }
    return {
      'format': 'ntfy-flutter-backup',
      'version': 1,
      'settings': Map<String, Object?>.from(settings)..remove('id'),
      'subscriptions': subscriptions,
      'messages': messages,
    };
  }

  Future<void> restoreBackup(Object? backup) async {
    if (backup is! Map ||
        backup['format'] != 'ntfy-flutter-backup' ||
        backup['version'] != 1 ||
        backup['subscriptions'] is! List ||
        backup['settings'] is! Map) {
      throw const FormatException('This is not a supported ntfy backup.');
    }
    final subscriptions = <Map<String, Object?>>[];
    for (final value in backup['subscriptions']! as List) {
      if (value is! Map || value['url'] is! String) {
        throw const FormatException('The backup contains an invalid topic.');
      }
      final url = normalizeUrl(value['url']! as String);
      subscriptions.add({
        'url': url,
        'display_name': value['display_name'] as String?,
        'retention_seconds': value['retention_seconds'] as int?,
        'muted_until': value['muted_until'] as int?,
        'minimum_priority': value['minimum_priority'] as int?,
        'insistent_max_priority': value['insistent_max_priority'] as int?,
        'attachment_download': value['attachment_download'] as int?,
        'dedicated_channel': value['dedicated_channel'] as int?,
        'background_enabled': value['background_enabled'] == 0 ? 0 : 1,
        'up_app_id': value['up_app_id'] as String?,
        'up_connector_token': value['up_connector_token'] as String?,
      });
    }
    final messages = <Map<String, Object?>>[];
    final messageValues = backup['messages'];
    if (messageValues != null && messageValues is! List) {
      throw const FormatException('The backup contains invalid notifications.');
    }
    for (final value in messageValues as List? ?? const []) {
      if (value is! Map ||
          value['subscription_url'] is! String ||
          value['event_id'] is! String ||
          value['event_time'] is! int ||
          value['message'] is! String ||
          value['priority'] is! int ||
          value['tags'] is! List) {
        throw const FormatException(
          'The backup contains an invalid notification.',
        );
      }
      final priority = value['priority']! as int;
      if (priority < 1 ||
          priority > 5 ||
          !(value['tags']! as List).every((tag) => tag is String)) {
        throw const FormatException(
          'The backup contains an invalid notification.',
        );
      }
      final attachment = value['attachment'];
      final parsedAttachment = attachment == null
          ? null
          : MessageAttachment.fromJson(attachment);
      if (attachment != null && parsedAttachment == null) {
        throw const FormatException(
          'The backup contains an invalid attachment.',
        );
      }
      final actionValues = value['actions'] ?? const <Object?>[];
      if (actionValues is! List) {
        throw const FormatException(
          'The backup contains invalid notification actions.',
        );
      }
      final actions = actionValues.map(MessageAction.fromJson).toList();
      if (actions.any((action) => action == null)) {
        throw const FormatException(
          'The backup contains invalid notification actions.',
        );
      }
      messages.add({
        'subscription_url': normalizeUrl(value['subscription_url']! as String),
        'event_id': value['event_id'],
        'sequence_id': value['sequence_id'] is String
            ? value['sequence_id']
            : value['event_id'],
        'event_time': value['event_time'],
        'message': value['message'],
        'title': value['title'] as String?,
        'priority': priority,
        'tags': jsonEncode(value['tags']),
        'click': value['click'] as String?,
        'icon': value['icon'] as String?,
        'actions_json': jsonEncode(
          actions
              .cast<MessageAction>()
              .map((action) => action.toJson())
              .toList(),
        ),
        'content_type': value['content_type'] as String?,
        'encoding': value['encoding'] as String?,
        'is_read': value['is_read'] == 0 ? 0 : 1,
        'attachment_json': parsedAttachment == null
            ? null
            : jsonEncode(
                MessageAttachment(
                  name: parsedAttachment.name,
                  url: parsedAttachment.url,
                  type: parsedAttachment.type,
                  size: parsedAttachment.size,
                  expires: parsedAttachment.expires,
                ).toJson(),
              ),
      });
    }
    final settings = Map<String, Object?>.from(backup['settings']! as Map);
    const allowedSettings = {
      'retention_seconds',
      'background_listening',
      'muted_until',
      'minimum_priority',
      'insistent_max_priority',
      'attachment_download',
      'dedicated_channel',
    };
    settings.removeWhere((key, _) => !allowedSettings.contains(key));
    await _database.transaction((transaction) async {
      if (settings.isNotEmpty) {
        await transaction.update('app_settings', settings, where: 'id = 1');
      }
      for (final subscription in subscriptions) {
        final existing = await transaction.query(
          'subscriptions',
          columns: ['id'],
          where: 'url = ?',
          whereArgs: [subscription['url']],
          limit: 1,
        );
        if (existing.isEmpty) {
          await transaction.insert('subscriptions', subscription);
        } else {
          final values = Map<String, Object?>.from(subscription)..remove('url');
          await transaction.update(
            'subscriptions',
            values,
            where: 'id = ?',
            whereArgs: [existing.single['id']],
          );
        }
      }
      for (final message in messages) {
        final subscription = await transaction.query(
          'subscriptions',
          columns: ['id'],
          where: 'url = ?',
          whereArgs: [message.remove('subscription_url')],
          limit: 1,
        );
        if (subscription.isEmpty) {
          throw const FormatException(
            'A notification references a missing subscription.',
          );
        }
        await transaction.insert('messages', {
          ...message,
          'subscription_id': subscription.single['id'],
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<List<String>> _attachmentPaths(
    String where,
    List<Object?> whereArgs,
  ) async {
    final rows = await _database.query(
      'messages',
      columns: ['attachment_json'],
      where: '$where AND attachment_json IS NOT NULL',
      whereArgs: whereArgs,
    );
    return rows
        .map(
          (row) => MessageAttachment.fromJson(
            jsonDecode(row['attachment_json']! as String),
          )?.localPath,
        )
        .whereType<String>()
        .toList();
  }

  Future<List<String>> _expiredAttachmentPaths(
    DatabaseExecutor database,
    DateTime now,
  ) async {
    final rows = await database.rawQuery(
      '''
      SELECT messages.attachment_json
      FROM messages
      JOIN subscriptions ON subscriptions.id = messages.subscription_id
      CROSS JOIN app_settings
      WHERE messages.attachment_json IS NOT NULL
        AND app_settings.id = 1
        AND COALESCE(
          subscriptions.retention_seconds,
          app_settings.retention_seconds
        ) > 0
        AND messages.event_time < ? - 1000 * COALESCE(
          subscriptions.retention_seconds,
          app_settings.retention_seconds
        )
      ''',
      [now.millisecondsSinceEpoch],
    );
    return rows
        .map(
          (row) => MessageAttachment.fromJson(
            jsonDecode(row['attachment_json']! as String),
          )?.localPath,
        )
        .whereType<String>()
        .toList();
  }

  Future<void> _deleteAttachmentFiles(Iterable<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Database deletion remains authoritative if a cached file is gone.
      }
    }
  }

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
      sequence_id TEXT NOT NULL,
      event_time INTEGER NOT NULL,
      message TEXT NOT NULL,
      title TEXT,
      priority INTEGER NOT NULL,
      tags TEXT NOT NULL,
      click TEXT,
      icon TEXT,
      actions_json TEXT NOT NULL DEFAULT '[]',
      content_type TEXT,
      encoding TEXT,
      is_read INTEGER NOT NULL DEFAULT 0,
      attachment_json TEXT,
      UNIQUE(subscription_id, event_id),
      FOREIGN KEY(subscription_id) REFERENCES subscriptions(id) ON DELETE CASCADE
    )
  ''');
  await database.execute('''
    CREATE INDEX messages_subscription_time
    ON messages(subscription_id, event_time, local_id)
  ''');
  await database.execute('''
    CREATE INDEX messages_subscription_sequence
    ON messages(subscription_id, sequence_id)
  ''');
}

Future<void> _createRetentionSettingsSchema(DatabaseExecutor database) async {
  await database.execute('''
    CREATE TABLE app_settings (
      id INTEGER PRIMARY KEY CHECK(id = 1),
      retention_seconds INTEGER NOT NULL DEFAULT 0,
      background_listening INTEGER NOT NULL DEFAULT 0,
      muted_until INTEGER NOT NULL DEFAULT 0,
      minimum_priority INTEGER NOT NULL DEFAULT 1,
      insistent_max_priority INTEGER NOT NULL DEFAULT 0
      ,attachment_download INTEGER NOT NULL DEFAULT 1048576
      ,subscription_icon_path TEXT
      ,dedicated_channel INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await database.insert('app_settings', {
    'id': 1,
    'retention_seconds': 0,
    'background_listening': 0,
    'muted_until': 0,
    'minimum_priority': 1,
    'insistent_max_priority': 0,
    'attachment_download': 1048576,
    'subscription_icon_path': null,
    'dedicated_channel': 0,
  });
}

Future<void> _addExtendedNotificationPolicyColumns(Database database) async {
  final appColumns = await database.rawQuery('PRAGMA table_info(app_settings)');
  final appNames = appColumns.map((column) => column['name']).toSet();
  if (!appNames.contains('attachment_download')) {
    await database.execute(
      'ALTER TABLE app_settings ADD COLUMN attachment_download INTEGER NOT NULL DEFAULT 1048576',
    );
  }
  if (!appNames.contains('subscription_icon_path')) {
    await database.execute(
      'ALTER TABLE app_settings ADD COLUMN subscription_icon_path TEXT',
    );
  }
  if (!appNames.contains('dedicated_channel')) {
    await database.execute(
      'ALTER TABLE app_settings ADD COLUMN dedicated_channel INTEGER NOT NULL DEFAULT 0',
    );
  }
  final topicColumns = await database.rawQuery(
    'PRAGMA table_info(subscriptions)',
  );
  final topicNames = topicColumns.map((column) => column['name']).toSet();
  if (!topicNames.contains('attachment_download')) {
    await database.execute(
      'ALTER TABLE subscriptions ADD COLUMN attachment_download INTEGER',
    );
  }
  if (!topicNames.contains('subscription_icon_path')) {
    await database.execute(
      'ALTER TABLE subscriptions ADD COLUMN subscription_icon_path TEXT',
    );
  }
  if (!topicNames.contains('dedicated_channel')) {
    await database.execute(
      'ALTER TABLE subscriptions ADD COLUMN dedicated_channel INTEGER',
    );
  }
}

Future<void> _addNotificationPolicyColumns(Database database) async {
  final appColumns = await database.rawQuery('PRAGMA table_info(app_settings)');
  final appNames = appColumns.map((column) => column['name']).toSet();
  if (!appNames.contains('muted_until')) {
    await database.execute(
      'ALTER TABLE app_settings ADD COLUMN muted_until INTEGER NOT NULL DEFAULT 0',
    );
  }
  if (!appNames.contains('minimum_priority')) {
    await database.execute(
      'ALTER TABLE app_settings ADD COLUMN minimum_priority INTEGER NOT NULL DEFAULT 1',
    );
  }
  if (!appNames.contains('insistent_max_priority')) {
    await database.execute(
      'ALTER TABLE app_settings ADD COLUMN insistent_max_priority INTEGER NOT NULL DEFAULT 0',
    );
  }
  final topicColumns = await database.rawQuery(
    'PRAGMA table_info(subscriptions)',
  );
  final topicNames = topicColumns.map((column) => column['name']).toSet();
  for (final column in const [
    'muted_until',
    'minimum_priority',
    'insistent_max_priority',
  ]) {
    if (!topicNames.contains(column)) {
      await database.execute(
        'ALTER TABLE subscriptions ADD COLUMN $column INTEGER',
      );
    }
  }
}

Future<void> _addBackgroundListeningColumn(DatabaseExecutor database) async {
  final columns = await database.rawQuery('PRAGMA table_info(app_settings)');
  if (columns.any((column) => column['name'] == 'background_listening')) {
    return;
  }
  await database.execute(
    'ALTER TABLE app_settings ADD COLUMN '
    'background_listening INTEGER NOT NULL DEFAULT 0',
  );
}

Future<int> _cleanupExpired(DatabaseExecutor database, DateTime now) =>
    database.rawDelete(
      '''
    DELETE FROM messages
    WHERE EXISTS (
      SELECT 1
      FROM subscriptions
      CROSS JOIN app_settings
      WHERE subscriptions.id = messages.subscription_id
        AND app_settings.id = 1
        AND COALESCE(
          subscriptions.retention_seconds,
          app_settings.retention_seconds
        ) > 0
        AND messages.event_time < ? - 1000 * COALESCE(
          subscriptions.retention_seconds,
          app_settings.retention_seconds
        )
    )
  ''',
      [now.millisecondsSinceEpoch],
    );

StoredMessage _storedMessageFromRow(Map<String, Object?> row) => StoredMessage(
  localId: row['local_id']! as int,
  subscriptionId: row['subscription_id']! as int,
  eventId: row['event_id']! as String,
  sequenceId: row['sequence_id']! as String,
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
  click: row['click'] as String?,
  icon: row['icon'] as String?,
  actions: List.unmodifiable(
    (jsonDecode(row['actions_json']! as String) as List)
        .map(MessageAction.fromJson)
        .whereType<MessageAction>(),
  ),
  contentType: row['content_type'] as String?,
  encoding: row['encoding'] as String?,
  attachment: row['attachment_json'] == null
      ? null
      : MessageAttachment.fromJson(
          jsonDecode(row['attachment_json']! as String),
        ),
);

Future<void> _addExtendedMessageColumns(DatabaseExecutor database) async {
  final existing = (await database.rawQuery('PRAGMA table_info(messages)'))
      .map((column) => column['name'])
      .toSet();
  if (!existing.contains('sequence_id')) {
    await database.execute(
      "ALTER TABLE messages ADD COLUMN sequence_id TEXT NOT NULL DEFAULT ''",
    );
    await database.execute(
      'UPDATE messages SET sequence_id = event_id WHERE sequence_id = \'\'',
    );
  }
  if (!existing.contains('click')) {
    await database.execute('ALTER TABLE messages ADD COLUMN click TEXT');
  }
  if (!existing.contains('icon')) {
    await database.execute('ALTER TABLE messages ADD COLUMN icon TEXT');
  }
  if (!existing.contains('actions_json')) {
    await database.execute(
      "ALTER TABLE messages ADD COLUMN actions_json TEXT NOT NULL DEFAULT '[]'",
    );
  }
  if (!existing.contains('content_type')) {
    await database.execute('ALTER TABLE messages ADD COLUMN content_type TEXT');
  }
  if (!existing.contains('encoding')) {
    await database.execute('ALTER TABLE messages ADD COLUMN encoding TEXT');
  }
  await database.execute('''
    CREATE INDEX IF NOT EXISTS messages_subscription_sequence
    ON messages(subscription_id, sequence_id)
  ''');
}

String _unifiedPushEndpoint(String topicUrl) =>
    Uri.parse(topicUrl).replace(queryParameters: const {'up': '1'}).toString();

String _randomToken(int length) {
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}
