import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'attachments.dart';
import 'design.dart';
import 'emojis.dart';
import 'l10n.dart';
import 'message_actions.dart';
import 'messages.dart';
import 'notifications.dart';
import 'ntfy_topic_icon.dart';
import 'notification_policy.dart';
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
    this.notifications,
    this.routeObserver,
    this.initialEventId,
    this.onMessagesViewed,
    this.onRename,
    this.onBackgroundEnabled,
    this.onUnsubscribe,
    this.attachments,
    this.attachmentService = const AttachmentService(),
    this.actionExecutor = const MessageActionExecutor(),
    this.showMessageBar = true,
    this.newMessagesAtBottom = false,
    super.key,
  });

  final Subscription subscription;
  final TopicFeedSession feed;
  final RetentionSession retention;
  final MessageNotificationSession? notifications;
  final RouteObserver<PageRoute<dynamic>>? routeObserver;
  final String? initialEventId;
  final Future<void> Function()? onMessagesViewed;
  final Future<Subscription> Function(String? displayName)? onRename;
  final Future<Subscription> Function(bool enabled)? onBackgroundEnabled;
  final Future<void> Function()? onUnsubscribe;
  final AttachmentRepository? attachments;
  final AttachmentService attachmentService;
  final MessageActionExecutor actionExecutor;
  final bool showMessageBar;
  final bool newMessagesAtBottom;

  @override
  State<TopicFeedScreen> createState() => _TopicFeedScreenState();
}

class _TopicFeedScreenState extends State<TopicFeedScreen>
    with WidgetsBindingObserver, RouteAware {
  final _scrollController = ScrollController();
  StreamSubscription<FeedState>? _stateSubscription;
  StreamSubscription<void>? _retentionSubscription;
  late FeedState _state;
  final _messageKeys = <String, GlobalKey>{};
  var _initialScrollDone = false;
  var _showNewMessages = false;
  final _quickMessage = TextEditingController();
  final _search = TextEditingController();
  String? _publishError;
  var _publishing = false;
  PageRoute<dynamic>? _route;
  var _routeVisible = false;
  var _appResumed = true;
  var _initialAnchorRevealed = false;
  var _initialRevealAttempts = 0;
  var _feedStarted = false;
  var _searching = false;
  late Subscription _subscription;
  final _attachmentProgress = <int, double>{};
  final _attachmentErrors = <int, String>{};
  NotificationPolicy? _notificationPolicy;

  @override
  void initState() {
    super.initState();
    _subscription = widget.subscription;
    WidgetsBinding.instance.addObserver(this);
    _appResumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _state = widget.feed.state;
    _stateSubscription = widget.feed.states.listen(_onState);
    _retentionSubscription = widget.retention.changes.listen(
      (_) => unawaited(_refreshAfterRetention()),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> || identical(route, _route)) return;
    if (_route != null) {
      widget.routeObserver?.unsubscribe(this);
    }
    _route = route;
    widget.routeObserver?.subscribe(this, route);
    _setRouteVisible(route.isCurrent);
    unawaited(_startFeed());
  }

  Future<void> _startFeed() async {
    if (_feedStarted) return;
    _feedStarted = true;
    unawaited(
      widget.notifications?.setVisibleSubscription(
            _routeVisible && _appResumed ? _subscription.id : null,
          ) ??
          Future<void>.value(),
    );
    if (mounted) unawaited(widget.feed.start());
    await _loadNotificationPolicy();
  }

  Future<void> _loadNotificationPolicy() async {
    final repository = widget.notifications?.policies;
    if (repository == null) return;
    final policy = await repository.loadNotificationPolicy(
      subscriptionId: _subscription.id,
    );
    if (mounted) setState(() => _notificationPolicy = policy);
  }

  Future<void> _selectNotificationMute() async {
    final repository = widget.notifications?.policies;
    final policy = _notificationPolicy;
    if (repository == null || policy == null) return;
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final selected = await showDialog<(bool, int?)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const LText('Mute notifications'),
        children: [
          if (repository is TopicNotificationPolicyRepository)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (true, null)),
              child: const LText('Use global setting'),
            ),
          for (final choice in <(String, int)>[
            ('Show all notifications', 0),
            (
              '30 minutes',
              now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/
                  1000,
            ),
            (
              '1 hour',
              now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
            ),
            (
              '2 hours',
              now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000,
            ),
            (
              '8 hours',
              now.add(const Duration(hours: 8)).millisecondsSinceEpoch ~/ 1000,
            ),
            ('Until tomorrow', tomorrow.millisecondsSinceEpoch ~/ 1000),
            ('Until resumed', NotificationPolicy.untilResumed),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (false, choice.$2)),
              child: LText(choice.$1),
            ),
        ],
      ),
    );
    if (selected == null) return;
    if (repository is TopicNotificationPolicyRepository) {
      final overrideRepository =
          repository as TopicNotificationPolicyRepository;
      final overrides = await overrideRepository
          .loadTopicNotificationPolicyOverrides(_subscription.id);
      await overrideRepository.setTopicNotificationPolicyOverrides(
        _subscription.id,
        overrides.copyWith(mutedUntilEpochSeconds: selected.$2),
      );
    } else if (selected.$2 != null) {
      await repository.setTopicNotificationPolicy(
        _subscription.id,
        policy.copyWith(mutedUntilEpochSeconds: selected.$2),
      );
    }
    await _loadNotificationPolicy();
  }

  @override
  void didPush() => _setRouteVisible(true);

  @override
  void didPopNext() {
    _setRouteVisible(true);
    _markMessagesViewed();
  }

  @override
  void didPushNext() => _setRouteVisible(false);

  @override
  void didPop() => _setRouteVisible(false);

  void _setRouteVisible(bool visible) {
    if (_routeVisible == visible) return;
    _routeVisible = visible;
    _updateVisibleSubscription();
  }

  void _updateVisibleSubscription() {
    if (!_feedStarted) return;
    unawaited(
      widget.notifications?.setVisibleSubscription(
            _routeVisible && _appResumed ? _subscription.id : null,
          ) ??
          Future<void>.value(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _updateVisibleSubscription();
    if (state == AppLifecycleState.resumed) {
      widget.feed.resume();
      _markMessagesViewed();
      unawaited(_refreshAfterRetention());
    } else {
      unawaited(widget.feed.pause());
    }
  }

  void _markMessagesViewed() {
    if (_routeVisible && _appResumed) {
      unawaited(widget.onMessagesViewed?.call());
    }
  }

  void _onState(FeedState next) {
    if (!mounted) return;
    final hadNewMessage = next.messages.length > _state.messages.length;
    final wasAtLatest =
        !_scrollController.hasClients ||
        (widget.newMessagesAtBottom
            ? _scrollController.position.extentAfter < 48
            : _scrollController.position.extentBefore < 48);
    final anchor = hadNewMessage && !wasAtLatest && !widget.newMessagesAtBottom
        ? _captureAnchor()
        : null;
    if (hadNewMessage) _markMessagesViewed();
    setState(() {
      _state = next;
      if (hadNewMessage && _initialScrollDone && !wasAtLatest) {
        _showNewMessages = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (anchor != null) {
        if (!_restoreAnchor(anchor)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _restoreAnchor(anchor);
          });
        }
      } else if (!_initialScrollDone || (hadNewMessage && wasAtLatest)) {
        _initialScrollDone = true;
        _scrollToLatest();
      }
      _revealInitialMessage();
    });
  }

  void _revealInitialMessage() {
    if (_initialAnchorRevealed || widget.initialEventId == null) return;
    final target = _messageKeys[widget.initialEventId]?.currentContext;
    if (target == null) {
      final index = _state.messages.indexWhere(
        (message) => message.eventId == widget.initialEventId,
      );
      if (index < 0 ||
          !_scrollController.hasClients ||
          _initialRevealAttempts++ >= 3) {
        return;
      }
      final lastIndex = _state.messages.length - 1;
      final visibleIndex = widget.newMessagesAtBottom
          ? lastIndex - index
          : index;
      final fraction = lastIndex == 0 ? 0.0 : visibleIndex / lastIndex;
      _scrollController.jumpTo(
        _scrollController.position.maxScrollExtent * fraction,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealInitialMessage();
      });
      return;
    }
    _initialAnchorRevealed = true;
    Scrollable.ensureVisible(target, alignment: 0.5);
  }

  _ScrollAnchor? _captureAnchor() {
    _ScrollAnchor? anchor;
    var anchorOffset = double.infinity;
    final position = _scrollController.position;
    for (final entry in _messageKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final viewport = RenderAbstractViewport.of(box);
      final offset = viewport.getOffsetToReveal(box, 0).offset;
      if (offset + box.size.height <= position.pixels) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (offset < anchorOffset) {
        anchorOffset = offset;
        anchor = _ScrollAnchor(
          entry.key,
          top,
          _state.messages.indexWhere((message) => message.eventId == entry.key),
          _scrollController.position.pixels,
          _scrollController.position.maxScrollExtent,
        );
      }
    }
    return anchor;
  }

  bool _restoreAnchor(_ScrollAnchor anchor) {
    final index = _state.messages.indexWhere(
      (message) => message.eventId == anchor.eventId,
    );
    if (index > anchor.index && _scrollController.hasClients) {
      final position = _scrollController.position;
      final addedExtent = position.maxScrollExtent - anchor.maxScrollExtent;
      if (addedExtent > 0.5) {
        _scrollController.jumpTo(
          (anchor.pixels + addedExtent).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
        return true;
      }
    }
    final box = _messageKeys[anchor.eventId]?.currentContext
        ?.findRenderObject();
    if (box is! RenderBox || !box.attached || !_scrollController.hasClients) {
      return false;
    }
    final movement = box.localToGlobal(Offset.zero).dy - anchor.top;
    if (movement.abs() < 0.5) return false;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (position.pixels + movement).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    return true;
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(
      widget.newMessagesAtBottom
          ? _scrollController.position.maxScrollExtent
          : _scrollController.position.minScrollExtent,
    );
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
          .showSnackBar(const SnackBar(content: LText('Message published.')));
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
          subscription: _subscription,
          feed: widget.feed,
          initialMessage: _quickMessage.text,
        ),
      ),
    );
    if (published == true && mounted) {
      _quickMessage.clear();
      setState(() => _publishError = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: LText('Message published.')));
    }
  }

  Future<void> _sendTestNotification() async {
    const possibleTags = [
      'warning',
      'skull',
      'success',
      'triangular_flag_on_post',
      'dog',
      'rotating_light',
      'cat',
      'bike',
      'backup',
      'rsync',
    ];
    final random = Random();
    final priority = random.nextInt(5) + 1;
    final tags = [...possibleTags]..shuffle(random);
    try {
      await widget.feed.execute(
        PublishTopicMessage(
          PublishMessage(
            message: 'This is a test notification with priority $priority.',
            title: random.nextBool() ? 'Test notification' : null,
            priority: priority,
            tags: tags.take(random.nextInt(4)).toList(),
          ),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LText('Test notification sent.')),
        );
      }
    } catch (error) {
      _showCleanupError('Could not send test notification: $error');
    }
  }

  Future<void> _copyTopicUrl() async {
    await Clipboard.setData(ClipboardData(text: _subscription.url));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: LText('Topic URL copied.')));
    }
  }

  Future<void> _showConnectionError() async {
    final error = _state.error?.toString() ?? _statusLabel(_state);
    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Connection error'),
        content: SelectableText(error),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: error));
              if (context.mounted) Navigator.pop(context, false);
            },
            child: const LText('Copy'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.refresh),
            label: const LText('Retry now'),
          ),
        ],
      ),
    );
    if (retry == true) await widget.feed.execute(const ReconnectTopicFeed());
  }

  Future<void> _deleteMessage(StoredMessage message) async {
    _messageKeys.remove(message.eventId);
    try {
      await widget.feed.execute(DeleteLocalMessage(message.localId));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      final controller = messenger.showSnackBar(
        SnackBar(
          content: const LText('Notification deleted'),
          action: SnackBarAction(
            label: tr(context, 'Undo'),
            onPressed: () => unawaited(_restoreMessage(message)),
          ),
        ),
      );
      final reason = await controller.closed;
      final path = message.attachment?.localPath;
      if (reason != SnackBarClosedReason.action && path != null) {
        try {
          await widget.attachmentService.delete(path);
        } on FileSystemException {
          // The database deletion remains authoritative for cached files.
        }
      }
    } catch (_) {
      _showCleanupError('Could not delete the notification. Try again.');
    }
  }

  Future<void> _openAttachment(StoredMessage message) async {
    final attachment = message.attachment;
    if (attachment == null) return;
    try {
      final localPath = attachment.localPath;
      if (localPath != null &&
          await widget.attachmentService.exists(localPath)) {
        await widget.attachmentService.open(localPath);
        return;
      }
      final repository = widget.attachments;
      if (repository == null) {
        throw const AttachmentException(
          'Attachment downloads are unavailable.',
        );
      }
      setState(() {
        _attachmentErrors.remove(message.localId);
        _attachmentProgress[message.localId] = 0;
      });
      final path = await widget.attachmentService.download(
        attachment,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _attachmentProgress[message.localId] = progress);
          }
        },
      );
      await repository.setAttachmentLocalPath(
        message.subscriptionId,
        message.localId,
        path,
      );
      await widget.feed.execute(const RefreshLocalMessages());
      await widget.attachmentService.open(path);
    } catch (error) {
      if (mounted) {
        setState(() => _attachmentErrors[message.localId] = error.toString());
      }
    } finally {
      if (mounted) setState(() => _attachmentProgress.remove(message.localId));
    }
  }

  Future<void> _runMessageAction(
    StoredMessage message, [
    MessageAction? action,
  ]) async {
    try {
      if (action == null) {
        await widget.actionExecutor.openClick(message.click!);
      } else {
        await widget.actionExecutor.execute(action);
      }
    } on MessageActionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: LText(error.message)));
      }
    }
  }

  Future<void> _restoreMessage(StoredMessage message) async {
    try {
      await widget.feed.execute(RestoreLocalMessage(message));
    } catch (_) {
      _showCleanupError('Could not restore the notification. Try again.');
    }
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<Subscription>(
      MaterialPageRoute(
        builder: (_) => TopicSettingsScreen(
          subscription: _subscription,
          retention: widget.retention,
          onRename: widget.onRename,
          policies: widget.notifications?.policies,
          onBackgroundEnabled: widget.onBackgroundEnabled,
        ),
      ),
    );
    if (updated != null && mounted) setState(() => _subscription = updated);
    await _loadNotificationPolicy();
  }

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
        title: const LText('Clear all notifications?'),
        content: const LText('Delete all of the notifications in this topic?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LText('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const LText('Delete permanently'),
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
    final name = _subscription.displayName ?? _subscription.url;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Unsubscribe from topic?'),
        content: LText(
          'Unsubscribe from $name and delete all locally stored notifications?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LText('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const LText('Unsubscribe'),
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
        .showSnackBar(SnackBar(content: LText(message)));
  }

  @override
  void dispose() {
    if (_routeVisible && _appResumed) {
      unawaited(
        widget.notifications?.setVisibleSubscription(null) ??
            Future<void>.value(),
      );
    }
    widget.routeObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _stateSubscription?.cancel();
    _retentionSubscription?.cancel();
    _scrollController.dispose();
    _quickMessage.dispose();
    _search.dispose();
    unawaited(widget.feed.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _searching) {
          setState(() {
            _searching = false;
            _search.clear();
          });
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: CollapsibleDesignBody(
          scrollController: _scrollController,
          forceCollapsed: _searching,
          onCollapsedTitleTap: _searching
              ? null
              : () => unawaited(_openSettings()),
          leading: IconButton(
            key: _searching ? const Key('topic-search-back') : null,
            tooltip: tr(context, 'Back'),
            onPressed: _searching
                ? () => setState(() {
                    _searching = false;
                    _search.clear();
                  })
                : () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          title: _searching
              ? TextField(
                  key: const Key('topic-search-field'),
                  controller: _search,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18),
                  decoration: InputDecoration(
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintStyle: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    hintText: tr(context, 'Search in notifications'),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onChanged: (_) => setState(() {}),
                )
              : Builder(
                  builder: (context) => Material(
                    color: Colors.transparent,
                    textStyle: DefaultTextStyle.of(context).style,
                    child: LText(
                      _subscription.displayName ??
                          Uri.parse(_subscription.url).pathSegments.last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
          actions: _searching ? const [] : _topicActions(),
          child: Column(
            children: [
              if (!_searching && _state.status != FeedStatus.connected)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: LText(
                    _statusLabel(_state),
                    key: const Key('feed-status'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoLabel.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Expanded(
                child:
                    _state.messages.isEmpty &&
                        _state.status == FeedStatus.loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildMessages(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: widget.showMessageBar
            ? AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: _MessageBar(
                  controller: _quickMessage,
                  sending: _publishing,
                  error: _publishError,
                  onExpand: _openComposer,
                  onSend: _quickPublish,
                ),
              )
            : null,
        floatingActionButton: _showNewMessages
            ? FloatingActionButton.extended(
                key: const Key('new-messages-action'),
                onPressed: _scrollToLatest,
                icon: Icon(
                  widget.newMessagesAtBottom
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                ),
                label: const LText('New messages'),
              )
            : null,
      ),
    );
  }

  List<Widget> _topicActions() => [
    IconButton(
      key: const Key('topic-search-action'),
      tooltip: tr(context, 'Search notifications'),
      onPressed: () => setState(() => _searching = true),
      icon: const Icon(Icons.search),
    ),
    if (_state.status == FeedStatus.error ||
        _state.status == FeedStatus.offline)
      IconButton(
        key: const Key('connection-error-action'),
        tooltip: tr(context, 'Connection error'),
        onPressed: _showConnectionError,
        icon: const Icon(Icons.warning_amber),
      ),
    if (_notificationPolicy != null)
      IconButton(
        key: const Key('topic-notification-state'),
        tooltip: tr(
          context,
          _notificationPolicy!.mutedUntilEpochSeconds == 0
              ? 'Notifications enabled'
              : 'Notifications muted',
        ),
        onPressed: _selectNotificationMute,
        icon: Icon(
          _notificationPolicy!.mutedUntilEpochSeconds == 0
              ? Icons.notifications_none
              : Icons.notifications_off_outlined,
        ),
      ),
    PopupMenuButton<_TopicAction>(
      icon: const Icon(Icons.more_vert),
      position: PopupMenuPosition.under,
      offset: const Offset(-8, -4),
      constraints: const BoxConstraints.tightFor(width: 220),
      onSelected: (action) {
        switch (action) {
          case _TopicAction.settings:
            unawaited(_openSettings());
          case _TopicAction.clear:
            unawaited(_confirmClear());
          case _TopicAction.unsubscribe:
            unawaited(_confirmUnsubscribe());
          case _TopicAction.test:
            unawaited(_sendTestNotification());
          case _TopicAction.copyUrl:
            unawaited(_copyTopicUrl());
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _TopicAction.settings,
          height: 52,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: LText('Subscription settings'),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: _TopicAction.clear,
          enabled: _state.messages.isNotEmpty,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: const LText('Clear all notifications'),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: _TopicAction.test,
          height: 52,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: LText('Send test notification'),
        ),
        if (Uri.parse(_subscription.url).host != 'ntfy.sh') ...[
          const PopupMenuDivider(height: 1),
          const PopupMenuItem(
            value: _TopicAction.copyUrl,
            height: 52,
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LText('Copy topic URL'),
          ),
        ],
        if (widget.onUnsubscribe != null) ...[
          const PopupMenuDivider(height: 1),
          const PopupMenuItem(
            value: _TopicAction.unsubscribe,
            height: 52,
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LText('Unsubscribe'),
          ),
        ],
      ],
    ),
  ];

  Widget _buildMessages() {
    if (_state.messages.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: FramedTopicIcon(size: 64)),
              const SizedBox(height: 16),
              LText(
                "You haven't received any notifications for this topic yet.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              const LText(
                'Send a message to this topic with an HTTP PUT or POST request.',
              ),
              const SizedBox(height: 8),
              const LText('Example (using curl):'),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: LText(
                  '\$ curl -d "Hi" ${_subscription.url}',
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final query = _search.text.trim().toLowerCase();
    final orderedMessages = widget.newMessagesAtBottom
        ? _state.messages.reversed
        : _state.messages;
    final messages = query.isEmpty
        ? orderedMessages.toList(growable: false)
        : orderedMessages.where((message) {
            return message.message.toLowerCase().contains(query) ||
                (message.title?.toLowerCase().contains(query) ?? false) ||
                message.tags.any((tag) => tag.toLowerCase().contains(query));
          }).toList();
    if (messages.isEmpty) {
      return const Center(
        child: LText(
          'No notifications match your search.',
          key: Key('topic-search-empty'),
        ),
      );
    }
    return ListView.builder(
      key: const Key('topic-feed-list'),
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: messages.length,
      itemBuilder: (_, index) {
        final message = messages[index];
        return DesignSwipeToDelete(
          dismissKey: ValueKey('dismiss-message-${message.localId}'),
          onDelete: () => _deleteMessage(message),
          backgroundMargin: const EdgeInsets.fromLTRB(0, 5, 16, 5),
          child: _MessageCard(
            key: _messageKeys.putIfAbsent(message.eventId, GlobalKey.new),
            message: message,
            onDelete: () => unawaited(_deleteMessage(message)),
            attachmentProgress: _attachmentProgress[message.localId],
            attachmentError: _attachmentErrors[message.localId],
            onAttachment: () => unawaited(_openAttachment(message)),
            onClick: message.click == null
                ? null
                : () => unawaited(_runMessageAction(message)),
            onAction: (action) => unawaited(_runMessageAction(message, action)),
            imageService: widget.attachmentService,
          ),
        );
      },
    );
  }
}

enum _TopicAction { settings, clear, unsubscribe, test, copyUrl }

class _ScrollAnchor {
  const _ScrollAnchor(
    this.eventId,
    this.top,
    this.index,
    this.pixels,
    this.maxScrollExtent,
  );

  final String eventId;
  final double top;
  final int index;
  final double pixels;
  final double maxScrollExtent;
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.onDelete,
    required this.onAttachment,
    required this.onAction,
    required this.imageService,
    this.onClick,
    this.attachmentProgress,
    this.attachmentError,
    super.key,
  });

  final StoredMessage message;
  final VoidCallback onDelete;
  final VoidCallback onAttachment;
  final VoidCallback? onClick;
  final ValueChanged<MessageAction> onAction;
  final AttachmentService imageService;
  final double? attachmentProgress;
  final String? attachmentError;

  Future<void> _showActions(BuildContext context) async {
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const LText('Copy'),
              onTap: () => Navigator.pop(context, _MessageAction.copy),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const LText('Share'),
              onTap: () => Navigator.pop(context, _MessageAction.share),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const LText('Delete'),
              onTap: () => Navigator.pop(context, _MessageAction.delete),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case _MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.decodedMessage));
      case _MessageAction.share:
        await SharePlus.instance.share(
          ShareParams(text: message.decodedMessage),
        );
      case _MessageAction.delete:
        onDelete();
      case null:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localTime = message.time.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final timestamp =
        '${localizations.formatShortDate(localTime)} '
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
      message.decodedMessage,
      ?tags,
      ?message.attachment?.name,
    ].join('. ');

    return Semantics(
      label: semantics,
      customSemanticsActions: {
        CustomSemanticsAction(label: tr(context, 'Delete notification')):
            onDelete,
      },
      child: Card(
        key: ValueKey('message-${message.eventId}'),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline),
          left: BorderSide(color: Theme.of(context).colorScheme.outline),
          right: BorderSide(color: Theme.of(context).colorScheme.outline),
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.shadow,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onClick,
          onLongPress: () => unawaited(_showActions(context)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LText(
                        timestamp,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    if (priority != null) ...[
                      ExcludeSemantics(
                        child: _PriorityIndicator(
                          priority: message.priority,
                          size: 24,
                        ),
                      ),
                    ],
                  ],
                ),
                if (message.title != null) ...[
                  const SizedBox(height: 4),
                  FutureBuilder<String>(
                    future: EmojiTags.prefix(message.tags),
                    builder: (context, snapshot) {
                      final emoji = snapshot.data ?? '';
                      final titleStyle = Theme.of(context).textTheme.titleMedium
                          ?.copyWith(
                            fontSize: 15,
                            height: 1.3,
                            fontWeight: FontWeight.bold,
                          );
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (emoji.isNotEmpty) ...[
                            Text(emoji, style: titleStyle),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: LText(message.title!, style: titleStyle),
                          ),
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: 3),
                if (_safeRemoteImage(message.icon) case final icon?) ...[
                  const SizedBox(height: 6),
                  _AuthenticatedImage(uri: icon, service: imageService),
                ],
                if (message.contentType == 'text/markdown')
                  MarkdownBody(
                    data: message.decodedMessage,
                    onTapLink: (_, href, _) {
                      if (href == null) return;
                      onAction(
                        MessageAction(
                          id: 'markdown-link',
                          action: 'view',
                          label: href,
                          url: href,
                        ),
                      );
                    },
                  )
                else
                  Linkify(
                    text: message.decodedMessage,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontSize: 13, height: 1.5),
                    onOpen: (link) => onAction(
                      MessageAction(
                        id: 'message-link',
                        action: 'view',
                        label: link.url,
                        url: link.url,
                      ),
                    ),
                  ),
                if (message.attachment case final attachment?) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: attachmentProgress == null
                        ? Icon(
                            attachment.localPath == null
                                ? Icons.download_outlined
                                : Icons.open_in_new,
                          )
                        : CircularProgressIndicator(value: attachmentProgress),
                    title: LText(attachment.name),
                    subtitle: LText(
                      [
                        if (attachment.size != null) '${attachment.size} bytes',
                        ?attachmentError,
                      ].join('\n'),
                    ),
                    onTap: attachmentProgress == null ? onAttachment : null,
                  ),
                ],
                if (message.actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: message.actions
                        .take(3)
                        .map(
                          (action) => FilledButton.tonal(
                            onPressed: () => onAction(action),
                            child: LText(action.label),
                          ),
                        )
                        .toList(),
                  ),
                ],
                if (tags != null)
                  FutureBuilder<List<String>>(
                    future: EmojiTags.unmatched(message.tags),
                    builder: (context, snapshot) {
                      final unmatched = snapshot.data ?? const <String>[];
                      if (unmatched.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LText(
                          'Tags: ${unmatched.join(', ')}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Uri? _safeRemoteImage(String? value) {
  final uri = Uri.tryParse(value ?? '');
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}

class _AuthenticatedImage extends StatefulWidget {
  const _AuthenticatedImage({required this.uri, required this.service});

  final Uri uri;
  final AttachmentService service;

  @override
  State<_AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends State<_AuthenticatedImage> {
  late Future<Uint8List> _bytes = widget.service.fetchBytes(widget.uri);

  @override
  void didUpdateWidget(_AuthenticatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri || oldWidget.service != widget.service) {
      _bytes = widget.service.fetchBytes(widget.uri);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) => snapshot.data == null
        ? const SizedBox.shrink()
        : Image.memory(
            snapshot.data!,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
  );
}

enum _MessageAction { copy, share, delete }

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
      elevation: 0,
      color: theme.scaffoldBackgroundColor,
      shape: Border(top: BorderSide(color: theme.colorScheme.outline)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    key: const Key('expand-composer-shell'),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: IconButton(
                      key: const Key('expand-composer'),
                      tooltip: tr(context, 'Expand composer'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      onPressed: sending ? null : onExpand,
                      icon: const Icon(Icons.add, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ConstrainedBox(
                      key: const Key('quick-message-field-shell'),
                      constraints: const BoxConstraints(minHeight: 48),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) => Transform.scale(
                          alignment: Alignment.centerRight,
                          scaleX: value,
                          child: Opacity(opacity: value, child: child),
                        ),
                        child: Semantics(
                          container: true,
                          explicitChildNodes: true,
                          label: tr(context, 'Message'),
                          child: TextField(
                            key: const Key('quick-message-field'),
                            controller: controller,
                            enabled: !sending,
                            minLines: 1,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: tr(context, 'Type a message here'),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: tr(context, 'Send message'),
                    child: Material(
                      key: const Key('quick-send'),
                      color: theme.colorScheme.primary,
                      child: InkWell(
                        onTap: sending ? null : onSend,
                        child: SizedBox.square(
                          dimension: 48,
                          child: Center(
                            child: sending
                                ? Semantics(
                                    liveRegion: true,
                                    label: tr(context, 'Publishing message'),
                                    child: SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.onPrimary,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.send,
                                    size: 20,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                          ),
                        ),
                      ),
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
                      child: LText(
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
  final _click = TextEditingController();
  final _email = TextEditingController();
  final _delay = TextEditingController();
  final _call = TextEditingController();
  final _attachmentUrl = TextEditingController();
  var _priority = 3;
  var _showTitle = false;
  var _showTags = false;
  var _showPriority = false;
  var _markdown = false;
  var _showClick = false;
  var _showEmail = false;
  var _showDelay = false;
  var _showCall = false;
  var _showAttachmentUrl = false;
  String? _attachmentFilePath;
  String? _attachmentFileName;
  var _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _title.dispose();
    _tags.dispose();
    _click.dispose();
    _email.dispose();
    _delay.dispose();
    _call.dispose();
    _attachmentUrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final message = PublishMessage(
      message: _message.text,
      title: _title.text,
      priority: _priority,
      tags: parsePublishTags(_tags.text),
      markdown: _markdown,
      clickUrl: _showClick ? _click.text : null,
      email: _showEmail ? _email.text : null,
      delay: _showDelay ? _delay.text : null,
      phoneCall: _showCall ? _call.text : null,
      attachmentUrl: _showAttachmentUrl ? _attachmentUrl.text : null,
      attachmentFilePath: _attachmentFilePath,
      attachmentFileName: _attachmentFileName,
    );
    final validationError = message.validationError;
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
          _error = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: LText(error.toString())));
      }
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.pickFiles();
    final file = result.singleOrNull;
    if (file?.path == null || !mounted) return;
    setState(() {
      _attachmentFilePath = file!.path;
      _attachmentFileName = file.name;
      _showAttachmentUrl = false;
      _attachmentUrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final target =
        widget.subscription.displayName ??
        Uri.parse(widget.subscription.url).pathSegments.last;
    return PopScope(
      canPop: !_sending,
      child: Scaffold(
        body: CollapsibleDesignBody(
          leading: IconButton(
            tooltip: tr(context, 'Close composer'),
            onPressed: _sending ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
          title: LText('Publish to $target'),
          actions: [
            TextButton(
              key: const Key('publish-action'),
              onPressed: _sending ? null : _publish,
              child: _sending
                  ? Semantics(
                      liveRegion: true,
                      label: tr(context, 'Publishing message'),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : LText('PUBLISH', style: monoLabel.copyWith(fontSize: 12)),
            ),
          ],
          collapsedTitleSize: 20,
          expandedTitleSize: 24,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_showTitle) ...[
                TextField(
                  key: const Key('composer-title-field'),
                  controller: _title,
                  enabled: !_sending,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Title').toUpperCase(),
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
                decoration: InputDecoration(
                  labelText: tr(context, 'Message').toUpperCase(),
                  hintText: tr(context, 'Type a message here'),
                  alignLabelWithHint: true,
                ),
              ),
              if (_showTags) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const Key('composer-tags-field'),
                  controller: _tags,
                  enabled: !_sending,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Tags').toUpperCase(),
                    hintText: tr(context, 'warning, skull'),
                  ),
                ),
              ],
              if (_showPriority) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const Key('composer-priority-field'),
                  initialValue: _priority,
                  decoration: InputDecoration(
                    labelText: tr(context, 'Priority').toUpperCase(),
                  ),
                  items: [
                    for (final priority in const [5, 4, 3, 2, 1])
                      DropdownMenuItem(
                        value: priority,
                        child: Row(
                          children: [
                            Icon(
                              _priorityIcon(priority),
                              color: priority >= 4 ? Colors.red : null,
                            ),
                            const SizedBox(width: 8),
                            LText('$priority — ${_priorityName(priority)}'),
                          ],
                        ),
                      ),
                  ],
                  onChanged: _sending
                      ? null
                      : (value) => setState(() => _priority = value ?? 3),
                ),
              ],
              if (_showClick) ...[
                const SizedBox(height: 16),
                _ComposerField(
                  fieldKey: const Key('composer-click-field'),
                  controller: _click,
                  label: 'Click URL',
                  keyboardType: TextInputType.url,
                  enabled: !_sending,
                ),
              ],
              if (_showEmail) ...[
                const SizedBox(height: 16),
                _ComposerField(
                  fieldKey: const Key('composer-email-field'),
                  controller: _email,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_sending,
                ),
              ],
              if (_showDelay) ...[
                const SizedBox(height: 16),
                _ComposerField(
                  fieldKey: const Key('composer-delay-field'),
                  controller: _delay,
                  label: 'Delay',
                  hint: '30m, 2h, or tomorrow 10am',
                  enabled: !_sending,
                ),
              ],
              if (_showCall) ...[
                const SizedBox(height: 16),
                _ComposerField(
                  fieldKey: const Key('composer-call-field'),
                  controller: _call,
                  label: 'Phone call',
                  keyboardType: TextInputType.phone,
                  enabled: !_sending,
                ),
              ],
              if (_showAttachmentUrl) ...[
                const SizedBox(height: 16),
                _ComposerField(
                  fieldKey: const Key('composer-attachment-url-field'),
                  controller: _attachmentUrl,
                  label: 'Attach by URL',
                  keyboardType: TextInputType.url,
                  enabled: !_sending,
                ),
              ],
              if (_attachmentFileName != null) ...[
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: LText(_attachmentFileName!),
                  trailing: IconButton(
                    tooltip: tr(context, 'Remove attachment'),
                    onPressed: _sending
                        ? null
                        : () => setState(() {
                            _attachmentFilePath = null;
                            _attachmentFileName = null;
                          }),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    key: const Key('composer-markdown-chip'),
                    label: const LText('Markdown'),
                    selected: _markdown,
                    onSelected: _sending
                        ? null
                        : (selected) => setState(() => _markdown = selected),
                  ),
                  FilterChip(
                    key: const Key('composer-title-chip'),
                    label: const LText('Title'),
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
                    label: const LText('Tags'),
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
                    label: const LText('Priority'),
                    selected: _showPriority,
                    onSelected: _sending
                        ? null
                        : (selected) => setState(() {
                            _showPriority = selected;
                            if (!selected) _priority = 3;
                          }),
                  ),
                  FilterChip(
                    key: const Key('composer-click-chip'),
                    label: const LText('Click URL'),
                    selected: _showClick,
                    onSelected: _sending
                        ? null
                        : (selected) => setState(() => _showClick = selected),
                  ),
                  FilterChip(
                    key: const Key('composer-email-chip'),
                    label: const LText('Email'),
                    selected: _showEmail,
                    onSelected: _sending
                        ? null
                        : (selected) => setState(() => _showEmail = selected),
                  ),
                  FilterChip(
                    key: const Key('composer-delay-chip'),
                    label: const LText('Delay'),
                    selected: _showDelay,
                    onSelected: _sending
                        ? null
                        : (selected) => setState(() => _showDelay = selected),
                  ),
                  FilterChip(
                    key: const Key('composer-attachment-url-chip'),
                    label: const LText('Attach by URL'),
                    selected: _showAttachmentUrl,
                    onSelected: _sending
                        ? null
                        : (selected) => setState(() {
                            _showAttachmentUrl = selected;
                            if (selected) {
                              _attachmentFilePath = null;
                              _attachmentFileName = null;
                            }
                          }),
                  ),
                  ActionChip(
                    key: const Key('composer-attachment-file-chip'),
                    label: const LText('Attach local file'),
                    onPressed: _sending ? null : _pickAttachment,
                  ),
                  FilterChip(
                    key: const Key('composer-call-chip'),
                    label: const LText('Phone call'),
                    selected: _showCall,
                    onSelected: _sending
                        ? null
                        : (selected) => setState(() => _showCall = selected),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: LText(
                    _error!,
                    key: const Key('composer-publish-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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

class _ComposerField extends StatelessWidget {
  const _ComposerField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.enabled,
    this.hint,
    this.keyboardType,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    enabled: enabled,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: tr(context, label).toUpperCase(),
      hintText: hint == null ? null : tr(context, hint!),
    ),
  );
}

IconData _priorityIcon(int priority) => switch (priority) {
  1 => Icons.keyboard_double_arrow_down,
  2 => Icons.keyboard_arrow_down,
  4 => Icons.keyboard_arrow_up,
  5 => Icons.keyboard_double_arrow_up,
  _ => Icons.remove,
};

class _PriorityIndicator extends StatelessWidget {
  const _PriorityIndicator({required this.priority, this.size = 24});

  final int priority;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _PriorityPainter(priority));
}

class _PriorityPainter extends CustomPainter {
  const _PriorityPainter(this.priority);

  final int priority;

  @override
  void paint(Canvas canvas, Size size) {
    final high = priority >= 4;
    final count = priority == 1 || priority == 5 ? 3 : 2;
    final paint = Paint()
      ..color = high ? const Color(0xffc60000) : const Color(0xff999999)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width / 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final spacing = size.height / 5;
    final center = size.height / 2;
    for (var index = 0; index < count; index++) {
      final offset = (index - (count - 1) / 2) * spacing;
      final y = center + offset;
      final path = Path();
      if (high) {
        path
          ..moveTo(size.width * .25, y + spacing * .3)
          ..lineTo(size.width * .5, y - spacing * .3)
          ..lineTo(size.width * .75, y + spacing * .3);
      } else {
        path
          ..moveTo(size.width * .25, y - spacing * .3)
          ..lineTo(size.width * .5, y + spacing * .3)
          ..lineTo(size.width * .75, y - spacing * .3);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_PriorityPainter oldDelegate) =>
      oldDelegate.priority != priority;
}

String _priorityName(int priority) => switch (priority) {
  1 => 'Min',
  2 => 'Low',
  4 => 'High',
  5 => 'Max',
  _ => 'Default',
};

String _statusLabel(FeedState state) => switch (state.status) {
  FeedStatus.loading => 'Loading',
  FeedStatus.connecting => 'Connecting',
  FeedStatus.connected => 'Connected',
  FeedStatus.reconnecting => 'Reconnecting',
  FeedStatus.offline => 'Offline — retrying',
  FeedStatus.error =>
    state.errorMessage == null ? 'Error' : 'Error — ${state.errorMessage}',
};
