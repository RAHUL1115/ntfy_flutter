class IncomingMessage {
  const IncomingMessage({
    required this.eventId,
    required this.time,
    required this.message,
    this.title,
    this.priority = 3,
    this.tags = const [],
  });

  final String eventId;
  final DateTime time;
  final String message;
  final String? title;
  final int priority;
  final List<String> tags;
}

class StoredMessage extends IncomingMessage {
  const StoredMessage({
    required this.localId,
    required this.subscriptionId,
    required super.eventId,
    required super.time,
    required super.message,
    super.title,
    super.priority,
    super.tags,
  });

  final int localId;
  final int subscriptionId;

  @override
  bool operator ==(Object other) =>
      other is StoredMessage &&
      localId == other.localId &&
      subscriptionId == other.subscriptionId &&
      eventId == other.eventId &&
      time == other.time &&
      message == other.message &&
      title == other.title &&
      priority == other.priority &&
      _listsEqual(tags, other.tags);

  @override
  int get hashCode => Object.hash(
    localId,
    subscriptionId,
    eventId,
    time,
    message,
    title,
    priority,
    Object.hashAll(tags),
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
}

bool _listsEqual(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
