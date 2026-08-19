import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/main.dart';
import 'package:ntfy_flutter/message_actions.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/publish.dart';
import 'package:ntfy_flutter/retention.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:ntfy_flutter/topic_feed.dart';
import 'package:ntfy_flutter/topic_feed_screen.dart';

void main() {
  testWidgets('topic feed title uses the shared page-title typography', (
    tester,
  ) async {
    const titleText =
        'Production alerts for the primary infrastructure monitoring service';
    final repository = _WidgetRepository(messageCount: 1);
    repository.subscription = const Subscription(
      id: 1,
      url: 'https://ntfy.sh/alerts',
      displayName: titleText,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: TopicFeedScreen(
          subscription: repository.subscription,
          feed: TopicFeedSession(
            controller: TopicFeedController(
              repository: repository,
              subscription: repository.subscription,
              client: _WidgetClient(),
            ),
          ),
          retention: RetentionSession(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester
        .widgetList<RichText>(find.byType(RichText))
        .singleWhere((widget) => widget.text.toPlainText() == titleText);
    expect(title.text.style?.fontFamily, 'HankenGrotesk');
    expect(title.text.style?.fontSize, 28);
    expect(title.text.style?.fontWeight, FontWeight.w700);
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('bottom message order shows oldest notification first', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 3);
    await tester.pumpWidget(
      MaterialApp(
        home: TopicFeedScreen(
          subscription: repository.subscription,
          feed: TopicFeedSession(
            controller: TopicFeedController(
              repository: repository,
              subscription: repository.subscription,
              client: _WidgetClient(),
            ),
          ),
          retention: RetentionSession(repository),
          newMessagesAtBottom: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Body 0')).dy,
      lessThan(tester.getTopLeft(find.text('Body 2')).dy),
    );
  });

  testWidgets('markdown content is rendered as markdown', (tester) async {
    final repository = _WidgetRepository(messageCount: 0);
    repository.messages.add(
      StoredMessage(
        localId: 1,
        subscriptionId: 1,
        eventId: 'markdown',
        time: DateTime.utc(2026),
        message: '**Important**\n\n[Open docs](https://example.com)',
        contentType: 'text/markdown',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TopicFeedScreen(
          subscription: repository.subscription,
          feed: TopicFeedSession(
            controller: TopicFeedController(
              repository: repository,
              subscription: repository.subscription,
              client: _WidgetClient(),
            ),
          ),
          retention: RetentionSession(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(
      tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data,
      contains('**Important**'),
    );
  });

  testWidgets('plain message web URLs open when tapped', (tester) async {
    final repository = _WidgetRepository(messageCount: 0);
    repository.messages.add(
      StoredMessage(
        localId: 1,
        subscriptionId: 1,
        eventId: 'plain-link',
        time: DateTime.utc(2026),
        message: 'See https://example.com/docs for details',
      ),
    );
    final platform = _RecordingActionPlatform();
    await tester.pumpWidget(
      MaterialApp(
        home: TopicFeedScreen(
          subscription: repository.subscription,
          feed: TopicFeedSession(
            controller: TopicFeedController(
              repository: repository,
              subscription: repository.subscription,
              client: _WidgetClient(),
            ),
          ),
          retention: RetentionSession(repository),
          actionExecutor: MessageActionExecutor(platform: platform),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final linkify = tester.widget<Linkify>(find.byType(Linkify));
    expect(linkify.text, contains('https://example.com/docs'));
    linkify.onOpen!(UrlElement('https://example.com/docs'));
    await tester.pump();

    expect(platform.opened, [Uri.parse('https://example.com/docs')]);
  });

  testWidgets('message actions stay available without a permanent menu', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: TopicFeedScreen(
          subscription: repository.subscription,
          feed: TopicFeedSession(
            controller: TopicFeedController(
              repository: repository,
              subscription: repository.subscription,
              client: _WidgetClient(),
            ),
          ),
          retention: RetentionSession(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Body 0'));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('advanced message content, click, and actions are interactive', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 0);
    repository.messages.add(
      StoredMessage(
        localId: 1,
        subscriptionId: 1,
        eventId: 'advanced',
        time: DateTime.utc(2026),
        message: base64Encode(utf8.encode('Decoded body')),
        encoding: 'base64',
        click: 'https://example.com/details',
        actions: const [
          MessageAction(
            id: 'send',
            action: 'broadcast',
            label: 'Send',
            intent: 'com.example.ACTION',
            extras: {'result': 'ok'},
          ),
        ],
      ),
    );
    final platform = _RecordingActionPlatform();
    await tester.pumpWidget(
      MaterialApp(
        home: TopicFeedScreen(
          subscription: repository.subscription,
          feed: TopicFeedSession(
            controller: TopicFeedController(
              repository: repository,
              subscription: repository.subscription,
              client: _WidgetClient(),
            ),
          ),
          retention: RetentionSession(repository),
          actionExecutor: MessageActionExecutor(platform: platform),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Decoded body'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    await tester.tap(find.text('Decoded body'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(platform.opened.single.toString(), 'https://example.com/details');
    expect(platform.broadcasts.single.$1, 'com.example.ACTION');
    expect(platform.broadcasts.single.$2, {'result': 'ok'});
  });

  testWidgets('notification target reveals an older off-screen message', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 100);
    final feed = TopicFeedSession(
      controller: TopicFeedController(
        repository: repository,
        subscription: repository.subscription,
        client: _WidgetClient(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TopicFeedScreen(
          subscription: repository.subscription,
          feed: feed,
          retention: RetentionSession(repository),
          initialEventId: 'id-0',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('message-id-0')), findsOneWidget);
  });

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
      expect(find.text('Connected'), findsNothing);
      expect(find.text('Body 2'), findsOneWidget);
      expect(find.text('Priority 5'), findsNothing);
      expect(find.textContaining('Title 2'), findsOneWidget);
      expect(find.text('Tags: warning'), findsNothing);
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

  testWidgets('topic search filters persisted messages and clears cleanly', (
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

    await tester.tap(find.byKey(const Key('topic-search-action')));
    await tester.pump();
    expect(find.byKey(const Key('topic-search-back')), findsOneWidget);
    expect(find.byKey(const Key('topic-notification-state')), findsNothing);
    expect(find.byType(PopupMenuButton), findsNothing);
    await tester.enterText(
      find.byKey(const Key('topic-search-field')),
      'warning',
    );
    await tester.pump();
    expect(find.text('Body 2'), findsOneWidget);
    expect(find.text('Body 1'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('topic-search-field')),
      'missing',
    );
    await tester.pump();
    expect(find.byKey(const Key('topic-search-empty')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('topic-search-field')), findsNothing);
    expect(find.text('Production alerts'), findsOneWidget);
    expect(find.text('Body 1'), findsOneWidget);
  });

  testWidgets('resume reloads messages persisted by the background listener', (
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

    repository.messages.add(
      StoredMessage(
        localId: 2,
        subscriptionId: 1,
        eventId: 'background',
        time: DateTime.utc(2026, 1, 2),
        message: 'Received while backgrounded',
      ),
    );
    expect(find.text('Received while backgrounded'), findsNothing);

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();

    expect(find.text('Received while backgrounded'), findsOneWidget);
  });

  testWidgets('backgrounding pauses the foreground topic connection', (
    tester,
  ) async {
    final repository = _WidgetRepository(messageCount: 0);
    final client = _LifecycleClient();
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
    expect(client.connections, hasLength(1));

    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(client.connections.single.closed, isTrue);

    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(client.connections, hasLength(2));
  });

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

    await tester.pumpAndSettle();
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

  testWidgets('starts at latest and offers new-message action away from top', (
    tester,
  ) async {
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
    final anchor = find.byKey(const ValueKey('message-id-20'));
    await tester.scrollUntilVisible(
      anchor,
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('topic-feed-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
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
  });

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

    await tester.fling(
      find.byKey(const ValueKey('message-id-1')),
      const Offset(-300, 0),
      3000,
    );
    await tester.pumpAndSettle();
    expect(find.text('Body 1'), findsOneWidget);
    expect(find.text('Delete notification?'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('message-id-1')),
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete notification?'), findsOneWidget);
    expect(repository.messages, hasLength(3));

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
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
    expect(find.text('Connected'), findsNothing);
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

    await tester.drag(
      find.byKey(const ValueKey('message-id-0')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production alerts'));
    await tester.pumpAndSettle();

    expect(find.text('NOTIFICATIONS'), findsOneWidget);
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
    await tester.pumpAndSettle();

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

class _RecordingActionPlatform implements MessageActionPlatform {
  final opened = <Uri>[];
  final broadcasts = <(String?, Map<String, String>)>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }

  @override
  Future<void> broadcast(String? intent, Map<String, String> extras) async {
    broadcasts.add((intent, extras));
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

class _LifecycleClient implements NtfyStreamClient {
  final connections = <_LifecycleConnection>[];

  @override
  Future<FeedConnection> connect({
    required String topicUrl,
    String? cursor,
  }) async {
    final connection = _LifecycleConnection();
    connections.add(connection);
    return FeedConnection(
      lines: connection.lines.stream,
      onClose: () async {
        connection.closed = true;
        await connection.lines.close();
      },
    );
  }
}

class _LifecycleConnection {
  final lines = StreamController<String>();
  var closed = false;
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
  bool backgroundListening = false;
  var subscription = const Subscription(
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
  Future<void> markRead(int subscriptionId) async {}

  @override
  Future<Subscription> rename(int subscriptionId, String? displayName) async {
    subscription = Subscription(
      id: subscription.id,
      url: subscription.url,
      displayName: displayName?.trim().isEmpty == true
          ? null
          : displayName?.trim(),
      unreadCount: subscription.unreadCount,
      totalCount: subscription.totalCount,
      lastActivity: subscription.lastActivity,
    );
    return subscription;
  }

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
  Future<bool> loadBackgroundListening() async => backgroundListening;

  @override
  Future<void> setBackgroundListening(bool enabled) async {
    backgroundListening = enabled;
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
