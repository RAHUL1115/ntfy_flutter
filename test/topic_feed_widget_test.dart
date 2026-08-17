import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/main.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/publish.dart';
import 'package:ntfy_flutter/retention.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:ntfy_flutter/topic_feed.dart';

void main() {
  testWidgets(
    'saved row opens feed and keeps history while connection changes',
    (tester) async {
      final repository = _WidgetRepository(messageCount: 3);
      final client = _WidgetClient();
      await tester.pumpWidget(
        NtfyApp(
          store: repository,
          feedFactory: (subscription) => TopicFeedSession(
            controller: TopicFeedController(
              repository: repository,
              subscription: subscription,
              client: client,
              retryDelays: const [Duration(seconds: 30)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Production alerts'));
      await tester.pumpAndSettle();

      expect(find.text('Production alerts'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Body 2'), findsOneWidget);
      expect(find.text('Priority 5'), findsOneWidget);
      expect(find.text('Tags: warning'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Priority 5.*Title 2.*Body 2.*warning')),
        findsOneWidget,
      );

      await client.lines.close();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Reconnecting'), findsOneWidget);
      expect(find.text('Body 2'), findsOneWidget);
    },
  );

  testWidgets('offline and error states keep stored history visible', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 3);
    await tester.pumpWidget(
      NtfyApp(
        store: repository,
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: repository,
            subscription: subscription,
            client: _ThrowingClient(const SocketException('network down')),
            retryDelays: const [Duration(seconds: 30)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production alerts'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.text('Offline — retrying'), findsOneWidget);
    expect(find.text('Body 2'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      NtfyApp(
        store: repository,
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: repository,
            subscription: subscription,
            client: _ThrowingClient(
              FeedHttpException(403, Uri.parse(subscription.url)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production alerts'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Error — ntfy returned HTTP 403'),
      findsOneWidget,
    );
    expect(find.text('Body 2'), findsOneWidget);
  });

  testWidgets(
    'starts at latest and offers new-message action away from bottom',
    (tester) async {
      final repository = _WidgetRepository(messageCount: 30);
      final client = _WidgetClient();
      await tester.pumpWidget(
        NtfyApp(
          store: repository,
          feedFactory: (subscription) => TopicFeedSession(
            controller: TopicFeedController(
              repository: repository,
              subscription: subscription,
              client: client,
              retryDelays: const [Duration(seconds: 30)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Production alerts'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('message-id-29')), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('topic-feed-list')),
        const Offset(0, 500),
      );
      await tester.pump();
      final anchor = find.byKey(const ValueKey('message-id-20'));
      final anchorTop = tester.getTopLeft(anchor).dy;

      client.lines.add(
        jsonEncode({
          'event': 'message',
          'topic': 'alerts',
          'id': 'delayed',
          'time': 1,
          'message': 'Delayed body',
        }),
      );
      await tester.pump();
      await tester.pump();
      expect(
        tester.getTopLeft(anchor).dy,
        moreOrLessEquals(anchorTop, epsilon: 1),
      );

      client.lines.add(
        jsonEncode({
          'event': 'message',
          'topic': 'alerts',
          'id': 'new',
          'time': 100,
          'message': 'Newest body',
        }),
      );
      await tester.pump();

      expect(find.byKey(const Key('new-messages-action')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('new-messages-action')));
      await tester.pump();
      expect(find.text('Newest body'), findsOneWidget);
    },
  );

  testWidgets('swipe deletes one notification locally and supports undo', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 3);
    await tester.pumpWidget(
      NtfyApp(
        store: repository,
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: repository,
            subscription: subscription,
            client: _WidgetClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production alerts'));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('message-id-1')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Body 1'), findsNothing);
    expect(repository.messages.map((message) => message.message), [
      'Body 0',
      'Body 2',
    ]);
    expect(find.text('Notification deleted'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Body 1'), findsOneWidget);
    expect(repository.messages.map((message) => message.message), [
      'Body 0',
      'Body 2',
      'Body 1',
    ]);
  });

  testWidgets('clears one topic while preserving its live subscription', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 3);
    final client = _WidgetClient();
    await tester.pumpWidget(
      NtfyApp(
        store: repository,
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: repository,
            subscription: subscription,
            client: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production alerts'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all notifications'));
    await tester.pumpAndSettle();
    expect(
      find.text('Delete all of the notifications in this topic?'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Delete permanently'));
    await tester.pumpAndSettle();

    expect(repository.messages, isEmpty);
    expect(await repository.all(), [repository.subscription]);
    expect(
      find.text("You haven't received any notifications for this topic yet."),
      findsOneWidget,
    );

    client.lines.add(
      jsonEncode({
        'event': 'message',
        'topic': 'alerts',
        'id': 'after-clear',
        'time': 100,
        'message': 'After clear',
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('After clear'), findsOneWidget);
  });

  testWidgets('unsubscribing closes the active stream and removes history', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 3);
    final client = _WidgetClient();
    await tester.pumpWidget(
      NtfyApp(
        store: repository,
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: repository,
            subscription: subscription,
            client: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production alerts'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsubscribe'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Unsubscribe'));
    await tester.pumpAndSettle();

    expect(client.closed, isTrue);
    expect(repository.messages, isEmpty);
    expect(await repository.all(), isEmpty);
    expect(
      find.text("It looks like you don't have any subscriptions yet."),
      findsOneWidget,
    );
  });

  testWidgets('failed unsubscribe leaves the active feed usable', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 1)
      ..removeError = StateError('database busy');
    final client = _WidgetClient();
    await tester.pumpWidget(
      NtfyApp(
        store: repository,
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: repository,
            subscription: subscription,
            client: client,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production alerts'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unsubscribe'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Unsubscribe'));
    await tester.pumpAndSettle();

    expect(find.text('Could not unsubscribe. Try again.'), findsOneWidget);
    expect(find.text('Body 0'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(client.closed, isFalse);
    expect(await repository.all(), [repository.subscription]);
  });

  testWidgets('topic settings overrides retention and refreshes the feed', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 1);
    await tester.pumpWidget(
      NtfyApp(
        store: repository,
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: repository,
            subscription: subscription,
            client: _WidgetClient(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production alerts'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscription settings'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Delete notifications'), findsOneWidget);
    expect(
      find.text('Never auto-delete notifications (using global setting)'),
      findsOneWidget,
    );
    expect(find.text('Topic URL'), findsOneWidget);
    await tester.tap(find.text('Delete notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Use global setting'), findsOneWidget);
    await tester.tap(find.text('After 3 hours'));
    await tester.pumpAndSettle();

    expect(repository.topicRetention, RetentionPeriod.threeHours);
    expect(
      find.text('Auto-delete notifications after 3 hours'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Body 0'), findsNothing);
  });

  testWidgets('composer validates and preserves a failed draft for retry', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 0);
    final publisher = _FakePublisher()
      ..error = 'Server unavailable. Try again.';
    await tester.pumpWidget(
      NtfyApp(
        store: repository,
        feedFactory: (subscription) => TopicFeedSession(
          controller: TopicFeedController(
            repository: repository,
            subscription: subscription,
            client: _WidgetClient(),
          ),
          publisher: publisher,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production alerts'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quick-send')));
    await tester.pump();
    expect(find.text('Message is required.'), findsOneWidget);
    expect(publisher.messages, isEmpty);

    await tester.tap(find.byKey(const Key('expand-composer')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer-message-field')),
      'Keep this draft',
    );
    await tester.tap(find.byKey(const Key('composer-title-chip')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('composer-title-field')),
      'A title',
    );
    await tester.tap(find.byKey(const Key('composer-tags-chip')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('composer-tags-field')),
      'warning, server',
    );
    await tester.tap(find.byKey(const Key('composer-priority-chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer-priority-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 — High').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('publish-action')));
    await tester.pump();

    expect(find.text('Server unavailable. Try again.'), findsOneWidget);
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(publisher.messages.single.title, 'A title');
    expect(publisher.messages.single.tags, ['warning', 'server']);
    expect(publisher.messages.single.priority, 4);

    publisher.error = null;
    await tester.tap(find.byKey(const Key('publish-action')));
    await tester.pumpAndSettle();
    expect(find.text('Message published.'), findsOneWidget);
    expect(publisher.messages, hasLength(2));
    expect(publisher.messages.last.message, 'Keep this draft');
    expect(publisher.messages.last.title, 'A title');
    expect(publisher.messages.last.tags, ['warning', 'server']);
    expect(publisher.messages.last.priority, 4);
    expect(repository.messages, isEmpty);
  });
}

class _FakePublisher implements NtfyPublisher {
  final messages = <PublishMessage>[];
  String? error;

  @override
  Future<void> publish(String topicUrl, PublishMessage message) async {
    messages.add(message);
    if (error != null) throw PublishException(error!);
  }
}

class _ThrowingClient implements NtfyStreamClient {
  const _ThrowingClient(this.error);

  final Object error;

  @override
  Future<FeedConnection> connect({required String topicUrl, String? cursor}) =>
      Future.error(error);
}

class _WidgetClient implements NtfyStreamClient {
  final lines = StreamController<String>();
  var closed = false;

  @override
  Future<FeedConnection> connect({
    required String topicUrl,
    String? cursor,
  }) async => FeedConnection(
    lines: lines.stream,
    onClose: () async {
      closed = true;
      if (!lines.isClosed) await lines.close();
    },
  );
}

class _WidgetRepository implements AppRepository {
  _WidgetRepository({required int messageCount})
    : messages = List.generate(
        messageCount,
        (index) => StoredMessage(
          localId: index + 1,
          subscriptionId: 1,
          eventId: 'id-$index',
          time: DateTime.fromMillisecondsSinceEpoch(index * 1000, isUtc: true),
          message: 'Body $index',
          title: index == 2 ? 'Title 2' : null,
          priority: index == 2 ? 5 : 3,
          tags: index == 2 ? const ['warning'] : const [],
        ),
      );

  final List<StoredMessage> messages;
  var removed = false;
  Object? removeError;
  RetentionPeriod globalRetention = RetentionPeriod.never;
  RetentionPeriod? topicRetention;
  final subscription = const Subscription(
    id: 1,
    url: 'https://ntfy.sh/alerts',
    displayName: 'Production alerts',
  );

  @override
  Future<Subscription> add({required String url, String? displayName}) async =>
      subscription;

  @override
  Future<List<Subscription>> all() async => removed ? [] : [subscription];

  @override
  Future<void> remove(int subscriptionId) async {
    if (removeError != null) throw removeError!;
    if (subscriptionId != subscription.id) return;
    removed = true;
    messages.clear();
  }

  @override
  Future<FeedSnapshot> loadFeed(int subscriptionId) async => FeedSnapshot(
    messages: messages,
    cursor: messages.isEmpty ? null : messages.last.eventId,
  );

  @override
  Future<void> deleteMessage(int subscriptionId, int localId) async {
    messages.removeWhere(
      (message) =>
          message.subscriptionId == subscriptionId &&
          message.localId == localId,
    );
  }

  @override
  Future<void> restoreMessage(int subscriptionId, StoredMessage message) async {
    if (messages.every((stored) => stored.eventId != message.eventId)) {
      messages.add(message);
    }
  }

  @override
  Future<void> clearMessages(int subscriptionId) async {
    messages.removeWhere((message) => message.subscriptionId == subscriptionId);
  }

  @override
  Future<RetentionSettings> loadRetention({int? subscriptionId}) async =>
      RetentionSettings(
        global: globalRetention,
        override: subscriptionId == null ? null : topicRetention,
      );

  @override
  Future<void> executeRetention(RetentionCommand command) async {
    switch (command) {
      case SetGlobalRetention(:final period):
        globalRetention = period;
      case SetTopicRetention(:final period):
        topicRetention = period;
      case RunRetentionCleanup():
        break;
    }
    final effective = topicRetention ?? globalRetention;
    if (effective != RetentionPeriod.never) {
      final cutoff = command.now.toUtc().subtract(effective.duration);
      messages.removeWhere((message) => message.time.isBefore(cutoff));
    }
  }

  @override
  Future<StoredMessage?> ingest(
    int subscriptionId,
    IncomingMessage message,
  ) async {
    if (messages.any((stored) => stored.eventId == message.eventId)) {
      return null;
    }
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
    return stored;
  }
}
