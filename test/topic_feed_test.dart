import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:ntfy_flutter/topic_feed.dart';

void main() {
  test('parser accepts normal fields and ignores non-message input', () {
    final parsed = parseNtfyLine(
      jsonEncode({
        'event': 'message',
        'topic': 'alerts',
        'id': 'abc',
        'time': 1700000000,
        'message': 'Disk full',
        'title': 'Server',
        'priority': 5,
        'tags': ['warning', 'computer'],
      }),
      'https://ntfy.sh/alerts',
    );

    expect(parsed?.eventId, 'abc');
    expect(
      parsed?.time,
      DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
    );
    expect(parsed?.message, 'Disk full');
    expect(parsed?.title, 'Server');
    expect(parsed?.priority, 5);
    expect(parsed?.tags, ['warning', 'computer']);

    for (final line in [
      '{bad json',
      '[]',
      jsonEncode({'event': 'keepalive', 'topic': 'alerts'}),
      jsonEncode({'event': 'future', 'topic': 'alerts'}),
      jsonEncode({
        'event': 'message',
        'topic': 'other',
        'id': 'x',
        'time': 1,
        'message': 'wrong',
      }),
      jsonEncode({
        'event': 'message',
        'topic': 'alerts',
        'id': 4,
        'time': 1,
        'message': 'bad',
      }),
    ]) {
      expect(parseNtfyLine(line, 'https://ntfy.sh/alerts'), isNull);
    }
  });

  test(
    'controller tolerates bad lines, dedupes, and reconnects from cursor',
    () async {
      final repository = _MemoryMessageRepository();
      final client = _SequenceClient([
        [
          '{bad',
          jsonEncode({'event': 'keepalive', 'topic': 'alerts'}),
          _line('one', 2, 'Later'),
          _line('one', 2, 'Duplicate'),
        ],
        [_line('two', 1, 'Earlier')],
      ]);
      final controller = TopicFeedController(
        repository: repository,
        subscription: const Subscription(id: 7, url: 'https://ntfy.sh/alerts'),
        client: client,
        retryDelays: const [Duration.zero],
      );
      addTearDown(controller.close);

      unawaited(controller.start());
      await _until(() => controller.state.messages.length == 2);

      expect(client.cursors.take(2), [null, 'one']);
      expect(controller.state.messages.map((message) => message.eventId), [
        'two',
        'one',
      ]);
      expect(repository.ingested.map((message) => message.message), [
        'Later',
        'Earlier',
      ]);

      final deleted = await controller.deleteMessage(
        controller.state.messages.first.localId,
      );
      expect(controller.state.messages.single.message, 'Later');

      await controller.restoreMessage(deleted!);
      expect(controller.state.messages.map((message) => message.message), [
        'Earlier',
        'Later',
      ]);

      final requestCount = client.cursors.length;
      await controller.clearMessages();
      expect(client.cursors, hasLength(requestCount));
      expect(controller.state.messages, isEmpty);
      expect(controller.state.cursor, 'two');
    },
  );
}

String _line(String id, int time, String message) => jsonEncode({
  'event': 'message',
  'topic': 'alerts',
  'id': id,
  'time': time,
  'message': message,
});

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _SequenceClient implements NtfyStreamClient, AbortableNtfyStreamClient {
  _SequenceClient(this.responses);

  final List<List<String>> responses;
  final cursors = <String?>[];
  var index = 0;
  StreamController<String>? pending;

  @override
  Future<FeedConnection> connect({
    required String topicUrl,
    String? cursor,
  }) async {
    cursors.add(cursor);
    if (index < responses.length) {
      return FeedConnection(
        lines: Stream<String>.fromIterable(responses[index++]),
      );
    }
    pending = StreamController<String>();
    return FeedConnection(lines: pending!.stream, onClose: pending!.close);
  }

  @override
  Future<void> abort() async => pending?.close();
}

class _MemoryMessageRepository implements MessageRepository {
  final messages = <StoredMessage>[];
  final ingested = <IncomingMessage>[];
  String? cursor;

  @override
  Future<FeedSnapshot> loadFeed(int subscriptionId) async =>
      FeedSnapshot(messages: messages, cursor: cursor);

  @override
  Future<void> deleteMessage(int subscriptionId, int localId) async {
    messages.removeWhere((message) => message.localId == localId);
  }

  @override
  Future<void> restoreMessage(int subscriptionId, StoredMessage message) async {
    if (messages.every((stored) => stored.eventId != message.eventId)) {
      messages.add(message);
    }
  }

  @override
  Future<void> clearMessages(int subscriptionId) async => messages.clear();

  @override
  Future<StoredMessage?> ingest(
    int subscriptionId,
    IncomingMessage message,
  ) async {
    if (messages.any((stored) => stored.eventId == message.eventId)) {
      return null;
    }
    ingested.add(message);
    final stored = StoredMessage(
      localId: messages.length + 1,
      subscriptionId: subscriptionId,
      eventId: message.eventId,
      time: message.time,
      message: message.message,
      title: message.title,
      priority: message.priority,
      tags: message.tags,
    );
    messages.add(stored);
    cursor = message.eventId;
    return stored;
  }
}
