import 'dart:convert';

enum MessageEventType { message, clear, delete }

class IncomingMessage {
  const IncomingMessage({
    required this.eventId,
    required this.time,
    required this.message,
    String? sequenceId,
    this.event = MessageEventType.message,
    this.title,
    this.priority = 3,
    this.tags = const [],
    this.click,
    this.icon,
    this.actions = const [],
    this.contentType,
    this.encoding,
    this.attachment,
  }) : sequenceId = sequenceId ?? eventId;

  final String eventId;
  final String sequenceId;
  final MessageEventType event;
  final DateTime time;
  final String message;
  final String? title;
  final int priority;
  final List<String> tags;
  final String? click;
  final String? icon;
  final List<MessageAction> actions;
  final String? contentType;
  final String? encoding;
  final MessageAttachment? attachment;

  List<int> get messageBytes {
    if (encoding != 'base64') return utf8.encode(message);
    try {
      return base64Decode(message);
    } on FormatException {
      return utf8.encode(message);
    }
  }

  String get decodedMessage => utf8.decode(messageBytes, allowMalformed: true);
}

class MessageAction {
  const MessageAction({
    required this.id,
    required this.action,
    required this.label,
    this.clear,
    this.url,
    this.method,
    this.headers = const {},
    this.body,
    this.intent,
    this.extras = const {},
    this.value,
  });

  final String id;
  final String action;
  final String label;
  final bool? clear;
  final String? url;
  final String? method;
  final Map<String, String> headers;
  final String? body;
  final String? intent;
  final Map<String, String> extras;
  final String? value;

  Map<String, Object?> toJson() => {
    'id': id,
    'action': action,
    'label': label,
    'clear': clear,
    'url': url,
    'method': method,
    'headers': headers,
    'body': body,
    'intent': intent,
    'extras': extras,
    'value': value,
  };

  static MessageAction? fromJson(Object? value) {
    if (value is! Map ||
        value['id'] is! String ||
        value['action'] is! String ||
        value['label'] is! String) {
      return null;
    }
    final headers = _stringMap(value['headers']);
    final extras = _stringMap(value['extras']);
    if (headers == null || extras == null) return null;
    return MessageAction(
      id: value['id']! as String,
      action: value['action']! as String,
      label: value['label']! as String,
      clear: value['clear'] as bool?,
      url: value['url'] as String?,
      method: value['method'] as String?,
      headers: headers,
      body: value['body'] as String?,
      intent: value['intent'] as String?,
      extras: extras,
      value: value['value'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MessageAction &&
      id == other.id &&
      action == other.action &&
      label == other.label &&
      clear == other.clear &&
      url == other.url &&
      method == other.method &&
      _mapsEqual(headers, other.headers) &&
      body == other.body &&
      intent == other.intent &&
      _mapsEqual(extras, other.extras) &&
      value == other.value;

  @override
  int get hashCode => Object.hash(
    id,
    action,
    label,
    clear,
    url,
    method,
    Object.hashAllUnordered(headers.entries),
    body,
    intent,
    Object.hashAllUnordered(extras.entries),
    value,
  );
}

class MessageAttachment {
  const MessageAttachment({
    required this.name,
    required this.url,
    this.type,
    this.size,
    this.expires,
    this.localPath,
  });

  final String name;
  final String url;
  final String? type;
  final int? size;
  final DateTime? expires;
  final String? localPath;

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url,
    'type': type,
    'size': size,
    'expires': expires?.millisecondsSinceEpoch,
    'localPath': localPath,
  };

  static MessageAttachment? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final url = value['url'];
    if (name is! String || url is! String) return null;
    final expires = value['expires'];
    return MessageAttachment(
      name: name,
      url: url,
      type: value['type'] as String?,
      size: value['size'] as int?,
      expires: expires is int
          ? DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true)
          : null,
      localPath: value['localPath'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MessageAttachment &&
      name == other.name &&
      url == other.url &&
      type == other.type &&
      size == other.size &&
      expires == other.expires &&
      localPath == other.localPath;

  @override
  int get hashCode => Object.hash(name, url, type, size, expires, localPath);
}

abstract interface class AttachmentRepository {
  Future<void> setAttachmentLocalPath(
    int subscriptionId,
    int localId,
    String localPath,
  );
}

class StoredMessage extends IncomingMessage {
  const StoredMessage({
    required this.localId,
    required this.subscriptionId,
    required super.eventId,
    required super.time,
    required super.message,
    super.sequenceId,
    super.title,
    super.priority,
    super.tags,
    super.click,
    super.icon,
    super.actions,
    super.contentType,
    super.encoding,
    super.attachment,
  });

  final int localId;
  final int subscriptionId;

  @override
  bool operator ==(Object other) =>
      other is StoredMessage &&
      localId == other.localId &&
      subscriptionId == other.subscriptionId &&
      eventId == other.eventId &&
      sequenceId == other.sequenceId &&
      time == other.time &&
      message == other.message &&
      title == other.title &&
      priority == other.priority &&
      _listsEqual(tags, other.tags) &&
      click == other.click &&
      icon == other.icon &&
      _listsEqual(actions, other.actions) &&
      contentType == other.contentType &&
      encoding == other.encoding &&
      attachment == other.attachment;

  @override
  int get hashCode => Object.hash(
    localId,
    subscriptionId,
    eventId,
    sequenceId,
    time,
    message,
    title,
    priority,
    Object.hashAll(tags),
    click,
    icon,
    Object.hashAll(actions),
    contentType,
    encoding,
    attachment,
  );
}

class FeedSnapshot {
  FeedSnapshot({required List<StoredMessage> messages, this.cursor})
    : messages = List.unmodifiable(messages);

  final List<StoredMessage> messages;
  final String? cursor;
}

abstract interface class MessageRepository {
  Future<FeedSnapshot> loadFeed(int subscriptionId);

  Future<StoredMessage?> ingest(int subscriptionId, IncomingMessage message);

  Future<void> deleteMessage(int subscriptionId, int localId);

  Future<void> restoreMessage(int subscriptionId, StoredMessage message);

  Future<void> clearMessages(int subscriptionId);
}

bool _listsEqual(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

Map<String, String>? _stringMap(Object? value) {
  if (value == null) return const {};
  if (value is! Map ||
      value.keys.any((key) => key is! String) ||
      value.values.any((item) => item is! String)) {
    return null;
  }
  return Map.unmodifiable(value.cast<String, String>());
}

bool _mapsEqual(Map<String, String> left, Map<String, String> right) {
  if (left.length != right.length) return false;
  return left.entries.every((entry) => right[entry.key] == entry.value);
}
