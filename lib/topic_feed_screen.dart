import 'dart:async';

import 'package:flutter/material.dart';

import 'messages.dart';
import 'subscriptions.dart';
import 'topic_feed.dart';

class TopicFeedScreen extends StatefulWidget {
  const TopicFeedScreen({
    required this.subscription,
    required this.feed,
    super.key,
  });

  final Subscription subscription;
  final TopicFeedSession feed;

  @override
  State<TopicFeedScreen> createState() => _TopicFeedScreenState();
}

class _TopicFeedScreenState extends State<TopicFeedScreen> {
  final _scrollController = ScrollController();
  StreamSubscription<FeedState>? _stateSubscription;
  late FeedState _state;
  final _messageKeys = <String, GlobalKey>{};
  var _initialScrollDone = false;
  var _showNewMessages = false;

  @override
  void initState() {
    super.initState();
    _state = widget.feed.state;
    _stateSubscription = widget.feed.states.listen(_onState);
    unawaited(widget.feed.start());
  }

  void _onState(FeedState next) {
    if (!mounted) return;
    final hadNewMessage = next.messages.length > _state.messages.length;
    final wasAtBottom =
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter < 48;
    final anchor = hadNewMessage && !wasAtBottom ? _captureAnchor() : null;
    setState(() {
      _state = next;
      if (hadNewMessage && _initialScrollDone && !wasAtBottom) {
        _showNewMessages = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (anchor != null) {
        _restoreAnchor(anchor);
      } else if (!_initialScrollDone || (hadNewMessage && wasAtBottom)) {
        _initialScrollDone = true;
        _scrollToLatest();
      }
    });
  }

  _ScrollAnchor? _captureAnchor() {
    _ScrollAnchor? anchor;
    for (final entry in _messageKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top + box.size.height <= 0) continue;
      if (anchor == null || top < anchor.top) {
        anchor = _ScrollAnchor(entry.key, top);
      }
    }
    return anchor;
  }

  void _restoreAnchor(_ScrollAnchor anchor) {
    final box = _messageKeys[anchor.eventId]?.currentContext
        ?.findRenderObject();
    if (box is! RenderBox || !box.attached || !_scrollController.hasClients) {
      return;
    }
    final movement = box.localToGlobal(Offset.zero).dy - anchor.top;
    if (movement.abs() < 0.5) return;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (position.pixels + movement).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    if (_showNewMessages) setState(() => _showNewMessages = false);
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _scrollController.dispose();
    unawaited(widget.feed.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.light
          ? theme.colorScheme.surfaceContainerHigh
          : theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.subscription.displayName ??
              Uri.parse(widget.subscription.url).pathSegments.last,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _statusLabel(_state),
              key: const Key('feed-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.appBarTheme.foregroundColor),
            ),
          ),
        ),
      ),
      body: _state.messages.isEmpty && _state.status == FeedStatus.loading
          ? const Center(child: CircularProgressIndicator())
          : _buildMessages(),
      floatingActionButton: _showNewMessages
          ? FloatingActionButton.extended(
              key: const Key('new-messages-action'),
              onPressed: _scrollToLatest,
              icon: const Icon(Icons.arrow_downward),
              label: const Text('New messages'),
            )
          : null,
    );
  }

  Widget _buildMessages() {
    if (_state.messages.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.sms_outlined,
                size: 48,
                color: Color(0xff888888),
              ),
              const SizedBox(height: 20),
              Text(
                "You haven't received any notifications for this topic yet.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Send a message to this topic with an HTTP PUT or POST request.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      key: const Key('topic-feed-list'),
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _state.messages.length,
      itemBuilder: (_, index) {
        final message = _state.messages[index];
        return _MessageCard(
          key: _messageKeys.putIfAbsent(message.eventId, GlobalKey.new),
          message: message,
        );
      },
    );
  }
}

class _ScrollAnchor {
  const _ScrollAnchor(this.eventId, this.top);

  final String eventId;
  final double top;
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, super.key});

  final StoredMessage message;

  @override
  Widget build(BuildContext context) {
    final localTime = message.time.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final timestamp =
        '${localizations.formatMediumDate(localTime)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localTime))}';
    final priority = message.priority == 3
        ? null
        : 'Priority ${message.priority}';
    final tags = message.tags.isEmpty
        ? null
        : 'Tags: ${message.tags.join(', ')}';
    final semantics = [
      timestamp,
      ?priority,
      ?message.title,
      message.message,
      ?tags,
    ].join('. ');

    return Semantics(
      label: semantics,
      child: Card(
        key: ValueKey('message-${message.eventId}'),
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      timestamp,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (priority != null) ...[
                    Icon(
                      message.priority >= 4
                          ? Icons.priority_high
                          : Icons.arrow_downward,
                      size: 16,
                    ),
                    Text(priority),
                  ],
                ],
              ),
              if (message.title != null) ...[
                const SizedBox(height: 4),
                Text(
                  message.title!,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 3),
              Text(message.message),
              if (tags != null) ...[
                const SizedBox(height: 6),
                Text(
                  tags,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(FeedState state) => switch (state.status) {
  FeedStatus.loading => 'Loading',
  FeedStatus.connecting => 'Connecting',
  FeedStatus.connected => 'Connected',
  FeedStatus.reconnecting => 'Reconnecting',
  FeedStatus.offline => 'Offline — retrying',
  FeedStatus.error =>
    state.errorMessage == null ? 'Error' : 'Error — ${state.errorMessage}',
};
