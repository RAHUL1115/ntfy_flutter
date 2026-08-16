import 'dart:convert';

enum AuthType { none, basic, bearer }

class AuthCredential {
  const AuthCredential.none()
    : type = AuthType.none,
      username = null,
      secret = null;

  const AuthCredential.basic({required this.username, required String password})
    : type = AuthType.basic,
      secret = password;

  const AuthCredential.bearer(String token)
    : type = AuthType.bearer,
      username = null,
      secret = token;

  final AuthType type;
  final String? username;
  final String? secret;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'username': username,
    'secret': secret,
  };

  factory AuthCredential.fromJson(Map<String, Object?> json) {
    switch (json['type']) {
      case 'basic':
        return AuthCredential.basic(
          username: json['username'] as String? ?? '',
          password: json['secret'] as String? ?? '',
        );
      case 'bearer':
        return AuthCredential.bearer(json['secret'] as String? ?? '');
      default:
        return const AuthCredential.none();
    }
  }
}

class Subscription {
  const Subscription({
    required this.id,
    required this.baseUrl,
    required this.topic,
    required this.createdAt,
    this.lastEventId,
    this.retentionSeconds,
    this.displayName,
  });

  final int id;
  final String baseUrl;
  final String topic;
  final String? lastEventId;
  final String? displayName;

  String get displayNameOrTopic => displayName ?? topic;
  final DateTime createdAt;

  /// `null` inherits the global default, `0` keeps messages forever.
  final int? retentionSeconds;

  Subscription copyWith({String? lastEventId, int? retentionSeconds}) =>
      Subscription(
        id: id,
        baseUrl: baseUrl,
        topic: topic,
        lastEventId: lastEventId ?? this.lastEventId,
        retentionSeconds: retentionSeconds ?? this.retentionSeconds,
        displayName: displayName,
        createdAt: createdAt,
      );
}

class NtfyEvent {
  const NtfyEvent({
    required this.id,
    required this.time,
    required this.event,
    required this.topic,
    this.message,
    this.title,
    this.tags = const [],
    this.priority = 3,
    this.sequenceId,
  });

  final String id;
  final DateTime time;
  final String event;
  final String topic;
  final String? message;
  final String? title;
  final List<String> tags;
  final int priority;
  final String? sequenceId;

  bool get isMessage => event == 'message';

  factory NtfyEvent.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final time = json['time'];
    final event = json['event'];
    final topic = json['topic'];
    if (id is! String || time is! num || event is! String || topic is! String) {
      throw const FormatException('Invalid ntfy event envelope');
    }

    final rawTags = json['tags'];
    if (rawTags != null && rawTags is! List) {
      throw const FormatException('Invalid ntfy event tags');
    }
    final tags = rawTags == null
        ? const <String>[]
        : (rawTags as List<Object?>)
              .map((tag) {
                if (tag is! String) {
                  throw const FormatException('Invalid ntfy event tag');
                }
                return tag;
              })
              .toList(growable: false);
    final priority = json['priority'];
    final sequenceId = json['sequence_id'];
    return NtfyEvent(
      id: id,
      time: DateTime.fromMillisecondsSinceEpoch(
        (time * 1000).round(),
        isUtc: true,
      ),
      event: event,
      topic: topic,
      message: json['message'] as String?,
      title: json['title'] as String?,
      tags: tags,
      priority: priority is num ? priority.toInt() : 3,
      sequenceId: sequenceId?.toString(),
    );
  }
}

class StoredMessage {
  const StoredMessage({
    required this.id,
    required this.subscriptionId,
    required this.eventId,
    required this.time,
    required this.message,
    required this.priority,
    required this.tags,
    required this.isRead,
    this.title,
  });

  final int id;
  final int subscriptionId;
  final String eventId;
  final DateTime time;
  final String message;
  final String? title;
  final int priority;
  final List<String> tags;
  final bool isRead;
}

class TopicSummary {
  const TopicSummary({
    required this.subscription,
    required this.unreadCount,
    this.latestMessage,
  });

  final Subscription subscription;
  final int unreadCount;
  final StoredMessage? latestMessage;
}

String encodeTags(List<String> tags) => jsonEncode(tags);

List<String> decodeTags(String value) =>
    (jsonDecode(value) as List).cast<String>();
