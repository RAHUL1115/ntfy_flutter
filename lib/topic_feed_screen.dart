import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'messages.dart';
import 'publish.dart';
import 'retention.dart';
import 'retention_settings.dart';
import 'subscriptions.dart';
import 'topic_feed.dart';

class TopicFeedScreen extends StatefulWidget {
  const TopicFeedScreen({
    required this.subscription,
    required this.feed,
    required this.retention,
    this.onUnsubscribe,
    super.key,
  });

  final Subscription subscription;
  final TopicFeedSession feed;
  final RetentionSession retention;
  final Future<void> Function()? onUnsubscribe;

  @override
  State<TopicFeedScreen> createState() => _TopicFeedScreenState();
}

class _TopicFeedScreenState extends State<TopicFeedScreen>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  StreamSubscription<FeedState>? _stateSubscription;
  StreamSubscription<void>? _retentionSubscription;
  late FeedState _state;
  final _messageKeys = <String, GlobalKey>{};
  var _initialScrollDone = false;
  var _showNewMessages = false;
  final _quickMessage = TextEditingController();
  String? _publishError;
  var _publishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = widget.feed.state;
    _stateSubscription = widget.feed.states.listen(_onState);
    _retentionSubscription = widget.retention.changes.listen(
      (_) => unawaited(_refreshAfterRetention()),
    );
    unawaited(widget.feed.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAfterRetention());
    }
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

  Future<void> _quickPublish() async {
    final message = PublishMessage(message: _quickMessage.text);
    final error = message.validationError;
    if (error != null) {
      setState(() => _publishError = error);
      return;
    }
    setState(() {
      _publishing = true;
      _publishError = null;
    });
    try {
      await widget.feed.execute(PublishTopicMessage(message));
      if (!mounted) return;
      _quickMessage.clear();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Message published.')));
    } catch (error) {
      if (mounted) setState(() => _publishError = error.toString());
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _openComposer() async {
    final published = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PublishComposer(
          subscription: widget.subscription,
          feed: widget.feed,
          initialMessage: _quickMessage.text,
        ),
      ),
    );
    if (published == true && mounted) {
      _quickMessage.clear();
      setState(() => _publishError = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Message published.')));
    }
  }

  Future<void> _deleteMessage(StoredMessage message) async {
    _messageKeys.remove(message.eventId);
    try {
      await widget.feed.execute(DeleteLocalMessage(message.localId));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Notification deleted'),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => unawaited(_restoreMessage(message)),
            ),
          ),
        );
    } catch (_) {
      _showCleanupError('Could not delete the notification. Try again.');
    }
  }

  Future<void> _restoreMessage(StoredMessage message) async {
    try {
      await widget.feed.execute(RestoreLocalMessage(message));
    } catch (_) {
      _showCleanupError('Could not restore the notification. Try again.');
    }
  }

  Future<void> _openSettings() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => TopicSettingsScreen(
        subscription: widget.subscription,
        retention: widget.retention,
      ),
    ),
  );

  Future<void> _refreshAfterRetention() async {
    try {
      await widget.feed.execute(const RefreshLocalMessages());
    } catch (_) {
      _showCleanupError('Could not refresh notifications. Try again.');
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text('Delete all of the notifications in this topic?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    _messageKeys.clear();
    try {
      await widget.feed.execute(const ClearLocalMessages());
    } catch (_) {
      _showCleanupError('Could not clear notifications. Try again.');
    }
  }

  Future<void> _confirmUnsubscribe() async {
    final callback = widget.onUnsubscribe;
    if (callback == null) return;
    final name = widget.subscription.displayName ?? widget.subscription.url;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsubscribe from topic?'),
        content: Text(
          'Unsubscribe from $name and delete all locally stored notifications?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Unsubscribe'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    try {
      await callback();
      await widget.feed.close();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      _showCleanupError('Could not unsubscribe. Try again.');
    }
  }

  void _showCleanupError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSubscription?.cancel();
    _retentionSubscription?.cancel();
    _scrollController.dispose();
    _quickMessage.dispose();
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
        actions: [
          PopupMenuButton<_TopicAction>(
            onSelected: (action) {
              switch (action) {
                case _TopicAction.settings:
                  unawaited(_openSettings());
                case _TopicAction.clear:
                  unawaited(_confirmClear());
                case _TopicAction.unsubscribe:
                  unawaited(_confirmUnsubscribe());
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _TopicAction.settings,
                child: Text('Subscription settings'),
              ),
              PopupMenuItem(
                value: _TopicAction.clear,
                enabled: _state.messages.isNotEmpty,
                child: const Text('Clear all notifications'),
              ),
              if (widget.onUnsubscribe != null)
                const PopupMenuItem(
                  value: _TopicAction.unsubscribe,
                  child: Text('Unsubscribe'),
                ),
            ],
          ),
        ],
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
      bottomNavigationBar: _MessageBar(
        controller: _quickMessage,
        sending: _publishing,
        error: _publishError,
        onExpand: _openComposer,
        onSend: _quickPublish,
      ),
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
        return Dismissible(
          key: ValueKey('dismiss-message-${message.localId}'),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => _deleteMessage(message),
          background: const _MessageDeleteBackground(
            alignment: Alignment.centerLeft,
          ),
          secondaryBackground: const _MessageDeleteBackground(
            alignment: Alignment.centerRight,
          ),
          child: _MessageCard(
            key: _messageKeys.putIfAbsent(message.eventId, GlobalKey.new),
            message: message,
            onDelete: () => unawaited(_deleteMessage(message)),
          ),
        );
      },
    );
  }
}

enum _TopicAction { settings, clear, unsubscribe }

class _MessageDeleteBackground extends StatelessWidget {
  const _MessageDeleteBackground({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.error,
      child: Align(
        alignment: alignment,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Icon(Icons.delete_outline, color: Colors.white),
        ),
      ),
    );
  }
}

class _ScrollAnchor {
  const _ScrollAnchor(this.eventId, this.top);

  final String eventId;
  final double top;
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.onDelete,
    super.key,
  });

  final StoredMessage message;
  final VoidCallback onDelete;

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
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Delete notification'): onDelete,
      },
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

class _MessageBar extends StatelessWidget {
  const _MessageBar({
    required this.controller,
    required this.sending,
    required this.error,
    required this.onExpand,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final String? error;
  final VoidCallback onExpand;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            key: const Key('expand-composer'),
                            tooltip: 'Expand composer',
                            onPressed: sending ? null : onExpand,
                            icon: const Icon(Icons.keyboard_arrow_up),
                          ),
                          Expanded(
                            child: Semantics(
                              container: true,
                              explicitChildNodes: true,
                              label: 'Message',
                              child: TextField(
                                key: const Key('quick-message-field'),
                                controller: controller,
                                enabled: !sending,
                                minLines: 1,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  hintText: 'Type a message here',
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: FloatingActionButton.small(
                      key: const Key('quick-send'),
                      tooltip: 'Send message',
                      onPressed: sending ? null : onSend,
                      child: sending
                          ? Semantics(
                              liveRegion: true,
                              label: 'Publishing message',
                              child: SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.send),
                    ),
                  ),
                ],
              ),
              if (error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 52, top: 2),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        key: const Key('quick-publish-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublishComposer extends StatefulWidget {
  const _PublishComposer({
    required this.subscription,
    required this.feed,
    required this.initialMessage,
  });

  final Subscription subscription;
  final TopicFeedSession feed;
  final String initialMessage;

  @override
  State<_PublishComposer> createState() => _PublishComposerState();
}

class _PublishComposerState extends State<_PublishComposer> {
  late final _message = TextEditingController(text: widget.initialMessage);
  final _title = TextEditingController();
  final _tags = TextEditingController();
  var _priority = 3;
  var _showTitle = false;
  var _showTags = false;
  var _showPriority = false;
  var _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _title.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final message = PublishMessage(
      message: _message.text,
      title: _title.text,
      priority: _priority,
      tags: parsePublishTags(_tags.text),
    );
    final validationError = message.validationError;
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.feed.execute(PublishTopicMessage(message));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final target =
        widget.subscription.displayName ??
        Uri.parse(widget.subscription.url).pathSegments.last;
    return PopScope(
      canPop: !_sending,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          leading: IconButton(
            tooltip: 'Close composer',
            onPressed: _sending ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          title: Text('Publish to $target'),
          actions: [
            TextButton(
              key: const Key('publish-action'),
              onPressed: _sending ? null : _publish,
              child: _sending
                  ? Semantics(
                      liveRegion: true,
                      label: 'Publishing message',
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Text('PUBLISH'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_showTitle) ...[
              TextField(
                key: const Key('composer-title-field'),
                controller: _title,
                enabled: !_sending,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              key: const Key('composer-message-field'),
              controller: _message,
              enabled: !_sending,
              autofocus: true,
              minLines: 4,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Type a message here',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_showTags) ...[
              const SizedBox(height: 16),
              TextField(
                key: const Key('composer-tags-field'),
                controller: _tags,
                enabled: !_sending,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'warning, skull',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_showPriority) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                key: const Key('composer-priority-field'),
                initialValue: _priority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 — Max')),
                  DropdownMenuItem(value: 4, child: Text('4 — High')),
                  DropdownMenuItem(value: 3, child: Text('3 — Default')),
                  DropdownMenuItem(value: 2, child: Text('2 — Low')),
                  DropdownMenuItem(value: 1, child: Text('1 — Min')),
                ],
                onChanged: _sending
                    ? null
                    : (value) => setState(() => _priority = value ?? 3),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  key: const Key('composer-title-chip'),
                  label: const Text('Title'),
                  selected: _showTitle,
                  onSelected: _sending
                      ? null
                      : (selected) => setState(() {
                          _showTitle = selected;
                          if (!selected) _title.clear();
                        }),
                ),
                FilterChip(
                  key: const Key('composer-tags-chip'),
                  label: const Text('Tags'),
                  selected: _showTags,
                  onSelected: _sending
                      ? null
                      : (selected) => setState(() {
                          _showTags = selected;
                          if (!selected) _tags.clear();
                        }),
                ),
                FilterChip(
                  key: const Key('composer-priority-chip'),
                  label: const Text('Priority'),
                  selected: _showPriority,
                  onSelected: _sending
                      ? null
                      : (selected) => setState(() {
                          _showPriority = selected;
                          if (!selected) _priority = 3;
                        }),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const Key('composer-publish-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
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
