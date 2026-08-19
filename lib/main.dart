import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';
import 'background_listening.dart';
import 'design.dart';
import 'attachments.dart';
import 'message_actions.dart';
import 'l10n.dart';
import 'messages.dart';
import 'notifications.dart';
import 'ntfy_topic_icon.dart';
import 'notification_policy.dart';
import 'publish.dart';
import 'retention.dart';
import 'retention_settings.dart';
import 'subscriptions.dart';
import 'topic_feed.dart';
import 'topic_feed_screen.dart';

export 'design.dart' show darkTheme, lightTheme;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SubscriptionStore.open();
  final settings = await AppSettingsStore.open();
  runApp(NtfyApp(store: store, settings: settings));
}

class NtfyApp extends StatefulWidget {
  NtfyApp({
    required this.store,
    this.feedFactory,
    NtfyPublisher? publisher,
    this.retention,
    this.backgroundListening,
    this.notifications,
    this.settings,
    super.key,
  }) : publisher = publisher ?? HttpNtfyPublisher(profiles: settings);

  final AppRepository store;
  final TopicFeedFactory? feedFactory;
  final NtfyPublisher publisher;
  final RetentionSession? retention;
  final BackgroundListeningSession? backgroundListening;
  final MessageNotificationSession? notifications;
  final AppSettingsRepository? settings;

  @override
  State<NtfyApp> createState() => _NtfyAppState();
}

class _NtfyAppState extends State<NtfyApp> {
  late final RetentionSession _retention;
  late final BackgroundListeningSession _backgroundListening;
  late final MessageNotificationSession _notifications;
  late final bool _ownsRetention;
  late final bool _ownsNotifications;
  final _routeObserver = RouteObserver<PageRoute<dynamic>>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  AppSettings _appSettings = const AppSettings();

  @override
  void initState() {
    super.initState();
    _ownsRetention = widget.retention == null;
    _ownsNotifications = widget.notifications == null;
    _retention = widget.retention ?? RetentionSession(widget.store);
    _notifications =
        widget.notifications ??
        MessageNotificationSession(
          AndroidNotificationPlatform(),
          policies: widget.store is NotificationPolicyRepository
              ? widget.store as NotificationPolicyRepository
              : null,
          broadcastsEnabled: widget.settings == null
              ? null
              : () async =>
                    (await widget.settings!.loadSettings()).broadcastsEnabled,
          iconLoader: (uri) =>
              AttachmentService(profiles: widget.settings)
                  .fetchBytes(uri, maxBytes: 1024 * 1024),
        );
    _backgroundListening =
        widget.backgroundListening ??
        BackgroundListeningSession(
          widget.store,
          const AndroidBackgroundListeningHost(),
        );
    _retention.start();
    unawaited(_loadSettings());
    unawaited(_startBackgroundListening());
  }

  Future<void> _loadSettings() async {
    final repository = widget.settings;
    if (repository == null) return;
    final settings = await repository.loadSettings();
    if (mounted) setState(() => _appSettings = settings);
  }

  Future<void> _startBackgroundListening() async {
    try {
      await _backgroundListening.start();
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: LText('Could not start background listening.'),
          ),
        );
      });
    }
  }

  TopicFeedSession _createFeed(Subscription subscription) => TopicFeedSession(
    controller: TopicFeedController(
      repository: widget.store,
      subscription: subscription,
      client: HttpNtfyStreamClient(profiles: widget.settings),
      notifications: _notifications,
      attachments:
          widget.store is NotificationPolicyRepository &&
              widget.store is AttachmentRepository
          ? AttachmentAutoDownloader(
              policies: widget.store as NotificationPolicyRepository,
              repository: widget.store as AttachmentRepository,
              service: AttachmentService(profiles: widget.settings),
            )
          : null,
    ),
    publisher: widget.publisher,
  );

  @override
  void dispose() {
    if (_ownsRetention) unawaited(_retention.close());
    if (_ownsNotifications) unawaited(_notifications.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DynamicColorBuilder(
    builder: (dynamicLight, dynamicDark) => MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      title: 'ntfy',
      theme: _appSettings.dynamicColors && dynamicLight != null
          ? designTheme(brightness: Brightness.light, colorScheme: dynamicLight)
          : lightTheme,
      darkTheme: _appSettings.dynamicColors && dynamicDark != null
          ? designTheme(brightness: Brightness.dark, colorScheme: dynamicDark)
          : darkTheme,
      themeMode: switch (_appSettings.theme) {
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
        AppThemePreference.system => ThemeMode.system,
      },
      locale: _appSettings.languageTag == 'system'
          ? null
          : _localeFromTag(_appSettings.languageTag),
      supportedLocales: supportedAppLanguages
          .map((language) => _localeFromTag(language.$1))
          .toList(growable: false),
      localizationsDelegates: [
        NtfyLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      navigatorObservers: [_routeObserver],
      home: SubscriptionsScreen(
        store: widget.store,
        feedFactory: widget.feedFactory ?? _createFeed,
        retention: _retention,
        backgroundListening: _backgroundListening,
        notifications: _notifications,
        routeObserver: _routeObserver,
        settings: widget.settings,
        appSettings: _appSettings,
        onSettingsChanged: _loadSettings,
      ),
    ),
  );
}

Locale _localeFromTag(String tag) {
  final parts = tag.split('-');
  return Locale(parts.first, parts.length > 1 ? parts[1] : null);
}

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({
    required this.store,
    required this.feedFactory,
    required this.retention,
    required this.backgroundListening,
    required this.notifications,
    required this.routeObserver,
    this.settings,
    this.appSettings = const AppSettings(),
    this.onSettingsChanged,
    super.key,
  });

  final AppRepository store;
  final TopicFeedFactory feedFactory;
  final RetentionSession retention;
  final BackgroundListeningSession backgroundListening;
  final MessageNotificationSession notifications;
  final RouteObserver<PageRoute<dynamic>> routeObserver;
  final AppSettingsRepository? settings;
  final AppSettings appSettings;
  final Future<void> Function()? onSettingsChanged;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen>
    with WidgetsBindingObserver {
  List<Subscription>? _subscriptions;
  StreamSubscription<NotificationTarget>? _notificationTapSubscription;
  Timer? _refreshTimer;
  Future<void> _navigationTail = Future<void>.value();
  NotificationTarget? _lastNotificationTarget;
  var _loadingSubscriptions = false;
  var _loadingConnectionStatus = false;
  NotificationPolicy? _globalPolicy;
  List<BackgroundServerConnectionStatus> _connections = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationTapSubscription = widget.notifications.taps.listen(
      _onNotificationTarget,
    );
    unawaited(_startNotifications());
    _loadSubscriptions();
    _loadGlobalPolicy();
    // ponytail: SQLite polling bridges UI/background isolates; replace with
    // database invalidation only if topic-list scale makes this measurable.
    _startRefreshTimer();
  }

  void _startRefreshTimer() {
    if (_refreshTimer != null) return;
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_loadSubscriptions()),
    );
  }

  void _stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _loadGlobalPolicy() async {
    final store = widget.store;
    if (store is! NotificationPolicyRepository) return;
    final policies = store as NotificationPolicyRepository;
    final policy = await policies.loadNotificationPolicy();
    if (mounted) setState(() => _globalPolicy = policy);
  }

  Future<void> _toggleGlobalNotifications() async {
    final store = widget.store;
    final policy = _globalPolicy;
    if (store is! NotificationPolicyRepository || policy == null) return;
    final policies = store as NotificationPolicyRepository;
    if (policy.mutedUntilEpochSeconds != 0) {
      await policies.setGlobalNotificationPolicy(
        policy.copyWith(mutedUntilEpochSeconds: 0),
      );
      await _loadGlobalPolicy();
      return;
    }
    final now = DateTime.now();
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const LText('Mute notifications'),
        children: [
          for (final choice in <(String, int)>[
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
            (
              'Until tomorrow',
              DateTime(
                    now.year,
                    now.month,
                    now.day + 1,
                  ).millisecondsSinceEpoch ~/
                  1000,
            ),
            ('Until resumed', NotificationPolicy.untilResumed),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, choice.$2),
              child: LText(choice.$1),
            ),
        ],
      ),
    );
    if (selected != null) {
      await policies.setGlobalNotificationPolicy(
        policy.copyWith(mutedUntilEpochSeconds: selected),
      );
      await _loadGlobalPolicy();
    }
  }

  Future<void> _openExternal(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LText('No app could open this link.')),
      );
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          retention: widget.retention,
          backgroundListening: widget.backgroundListening,
          policies: widget.store is NotificationPolicyRepository
              ? widget.store as NotificationPolicyRepository
              : null,
          settings: widget.settings,
          database: widget.store is SubscriptionStore
              ? widget.store as SubscriptionStore
              : null,
          onSettingsChanged: widget.onSettingsChanged,
        ),
      ),
    );
    await _loadGlobalPolicy();
  }

  Future<void> _selectHomeAction(_HomeAction action) async {
    switch (action) {
      case _HomeAction.settings:
        await _openSettings();
      case _HomeAction.docs:
        await _openExternal(Uri.parse('https://ntfy.sh/docs'));
      case _HomeAction.update:
        await _openExternal(
          Uri.parse(
            'https://github.com/RAHUL1115/ntfy_flutter/releases/latest',
          ),
        );
      case _HomeAction.reportBug:
        await _openExternal(
          Uri.parse('https://github.com/RAHUL1115/ntfy_flutter/issues'),
        );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRefreshTimer();
      unawaited(_loadSubscriptions());
    } else {
      _stopRefreshTimer();
    }
  }

  Future<void> _startNotifications() async {
    try {
      await widget.notifications.start();
    } catch (_) {
      // Notification taps are optional; the app remains usable without them.
    }
  }

  void _onNotificationTarget(NotificationTarget target) {
    if (target == _lastNotificationTarget) return;
    _lastNotificationTarget = target;
    final result = _navigationTail.then((_) => _openNotificationTarget(target));
    _navigationTail = result.then<void>((_) {}, onError: (_, _) {});
  }

  Future<void> _openNotificationTarget(NotificationTarget target) async {
    final subscriptions = _subscriptions ?? await widget.store.all();
    if (!mounted) return;
    _subscriptions ??= subscriptions;
    final subscription = subscriptions
        .where((item) => item.id == target.subscriptionId)
        .firstOrNull;
    if (subscription == null) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    await _openSubscription(subscription, initialEventId: target.eventId);
    if (_lastNotificationTarget == target) _lastNotificationTarget = null;
  }

  Future<void> _loadSubscriptions() async {
    if (_loadingSubscriptions) return;
    _loadingSubscriptions = true;
    try {
      final subscriptions = await widget.store.all();
      if (mounted && !listEquals(_subscriptions, subscriptions)) {
        setState(() => _subscriptions = subscriptions);
      }
    } finally {
      _loadingSubscriptions = false;
    }
    unawaited(_loadConnectionStatus());
  }

  Future<void> _loadConnectionStatus() async {
    if (_loadingConnectionStatus) return;
    _loadingConnectionStatus = true;
    try {
      final connections =
          (await widget.backgroundListening.status()).connections;
      if (mounted && !listEquals(_connections, connections)) {
        setState(() => _connections = connections);
      }
    } catch (_) {
      // Connection state is an optional Android host enhancement.
    } finally {
      _loadingConnectionStatus = false;
    }
  }

  Future<void> _manualRefresh() async {
    await _refreshBackgroundListener();
    await _loadSubscriptions();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: LText('Everything is up to date')),
      );
    }
  }

  Future<void> _showSubscribeDialog() async {
    final saved = await showModalBottomSheet<Subscription>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (_) => _SubscribeDialog(
        store: widget.store,
        defaultServer: widget.appSettings.defaultServer,
      ),
    );
    if (saved != null) {
      await _loadSubscriptions();
      await _refreshBackgroundListener();
    }
  }

  Future<void> _openSubscription(
    Subscription subscription, {
    String? initialEventId,
  }) async {
    _stopRefreshTimer();
    if (subscription.unifiedPushApp != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => TopicSettingsScreen(
            subscription: subscription,
            retention: widget.retention,
            policies: widget.store is NotificationPolicyRepository
                ? widget.store as NotificationPolicyRepository
                : null,
            onRename: (displayName) =>
                widget.store.rename(subscription.id, displayName),
            onBackgroundEnabled: widget.store is TopicDeliveryRepository
                ? (enabled) => (widget.store as TopicDeliveryRepository)
                      .setTopicBackgroundEnabled(subscription.id, enabled)
                : null,
          ),
        ),
      );
      await _loadSubscriptions();
      if (mounted) _startRefreshTimer();
      return;
    }
    await widget.store.markRead(subscription.id);
    await _loadSubscriptions();
    if (!mounted) return;
    final feed = widget.feedFactory(subscription);
    final removed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TopicFeedScreen(
          subscription: subscription,
          feed: feed,
          retention: widget.retention,
          notifications: widget.notifications,
          routeObserver: widget.routeObserver,
          initialEventId: initialEventId,
          showMessageBar:
              widget.appSettings.messageBar == MessageBarPreference.enabled,
          newMessagesAtBottom: widget.appSettings.newMessagesAtBottom,
          onMessagesViewed: () => widget.store.markRead(subscription.id),
          onRename: (displayName) =>
              widget.store.rename(subscription.id, displayName),
          onBackgroundEnabled: widget.store is TopicDeliveryRepository
              ? (enabled) async {
                  final updated =
                      await (widget.store as TopicDeliveryRepository)
                          .setTopicBackgroundEnabled(subscription.id, enabled);
                  await _refreshBackgroundListener();
                  return updated;
                }
              : null,
          onUnsubscribe: () async {
            await widget.store.remove(subscription.id);
            await _refreshBackgroundListener();
          },
          attachments: widget.store is AttachmentRepository
              ? widget.store as AttachmentRepository
              : null,
          attachmentService: AttachmentService(profiles: widget.settings),
          actionExecutor: MessageActionExecutor(settings: widget.settings),
        ),
      ),
    );
    if (removed != true) await widget.store.markRead(subscription.id);
    await _loadSubscriptions();
    if (mounted) _startRefreshTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopRefreshTimer();
    _notificationTapSubscription?.cancel();
    super.dispose();
  }

  Future<bool> _confirmRemove(Subscription subscription) async {
    final name = subscription.displayName ?? subscription.url;
    return await showDialog<bool>(
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
        ) ??
        false;
  }

  Future<void> _removeSubscription(Subscription subscription) async {
    setState(() {
      _subscriptions = _subscriptions
          ?.where((item) => item.id != subscription.id)
          .toList();
    });
    try {
      await widget.store.remove(subscription.id);
      await _refreshBackgroundListener();
    } catch (_) {
      await _loadSubscriptions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LText('Could not remove the subscription. Try again.'),
          ),
        );
      }
    }
  }

  Future<void> _refreshBackgroundListener() async {
    try {
      await widget.backgroundListening.execute(
        const RefreshBackgroundListener(),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LText('Could not refresh background listening.'),
          ),
        );
      }
    }
  }

  Future<void> _showConnectionErrors() async {
    final failed = _connections.where((item) => item.error != null).toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Connection error'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LText(
              'The app will keep trying to reconnect in the background.',
            ),
            const SizedBox(height: 12),
            for (final status in failed) ...[
              LText(
                status.server,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              LText(status.error!),
              const SizedBox(height: 8),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_refreshBackgroundListener());
            },
            child: const LText('Retry now'),
          ),
        ],
      ),
    );
  }

  bool _hasConnectionError(Subscription subscription) {
    final uri = Uri.parse(subscription.url);
    final parent = uri.pathSegments.sublist(0, uri.pathSegments.length - 1);
    final server = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: parent,
    ).toString();
    return _connections.any(
      (item) => item.server == server && item.error != null,
    );
  }

  String _subscriptionSubtitle(
    BuildContext context,
    Subscription subscription,
  ) {
    if (subscription.unifiedPushApp case final application?) {
      return '$application (UnifiedPush)';
    }
    final count = subscription.totalCount;
    final details = StringBuffer(
      count == 0
          ? 'No notifications yet'
          : '$count notification${count == 1 ? '' : 's'}',
    );
    final lastActivity = subscription.lastActivity?.toLocal();
    if (lastActivity != null) {
      final localizations = MaterialLocalizations.of(context);
      details
        ..write(' · ')
        ..write(localizations.formatMediumDate(lastActivity))
        ..write(' ')
        ..write(
          localizations.formatTimeOfDay(TimeOfDay.fromDateTime(lastActivity)),
        );
    }
    return details.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: LText(
          'Subscribed topics',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        actions: [
          if (_connections.any((item) => item.error != null))
            IconButton(
              key: const Key('connection-error'),
              tooltip: tr(context, 'Connection error'),
              onPressed: _showConnectionErrors,
              icon: const Icon(Icons.cloud_off_outlined),
            ),
          if (_globalPolicy != null)
            Hero(
              tag: 'home-notification-to-search',
              transitionOnUserGestures: true,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  key: const Key('global-notification-state'),
                  tooltip: tr(
                    context,
                    _globalPolicy!.mutedUntilEpochSeconds == 0
                        ? 'Notifications enabled'
                        : 'Notifications muted; tap to enable',
                  ),
                  onPressed: _toggleGlobalNotifications,
                  icon: Icon(
                    _globalPolicy!.mutedUntilEpochSeconds == 0
                        ? Icons.notifications_none
                        : Icons.notifications_off_outlined,
                  ),
                ),
              ),
            ),
          PopupMenuButton<_HomeAction>(
            position: PopupMenuPosition.under,
            offset: const Offset(-8, -4),
            constraints: const BoxConstraints.tightFor(width: 200),
            onSelected: (action) => unawaited(_selectHomeAction(action)),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _HomeAction.settings,
                height: 52,
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LText('Settings'),
              ),
              PopupMenuDivider(height: 1),
              PopupMenuItem(
                value: _HomeAction.update,
                height: 52,
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: LText(
                        'Update app',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.system_update_alt,
                      size: 16,
                      color: Color(0xff004f45),
                    ),
                  ],
                ),
              ),
              PopupMenuDivider(height: 1),
              PopupMenuItem(
                value: _HomeAction.reportBug,
                height: 52,
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LText('Report a bug'),
              ),
              PopupMenuDivider(height: 1),
              PopupMenuItem(
                value: _HomeAction.docs,
                height: 52,
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LText('Documentation'),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: Semantics(
        button: true,
        label: tr(context, 'Add subscription'),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(fabRadius),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.shadow,
                offset: hardShadowOffset,
              ),
            ],
          ),
          child: FloatingActionButton(
            onPressed: _showSubscribeDialog,
            tooltip: tr(context, 'Add subscription'),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final subscriptions = _subscriptions;
    if (subscriptions == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (subscriptions.isNotEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final proportionalSpace = constraints.maxHeight * 0.22;
          final topSpace = proportionalSpace < 150 ? 150.0 : proportionalSpace;
          return Column(
            children: [
              SizedBox(height: topSpace),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                  child: RefreshIndicator(
                    onRefresh: _manualRefresh,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: subscriptions.length,
                      separatorBuilder: (_, _) => const SizedBox.shrink(),
                      itemBuilder: (context, index) {
                        final subscription = subscriptions[index];
                        return Dismissible(
                          key: ValueKey('subscription-${subscription.id}'),
                          direction: DismissDirection.horizontal,
                          confirmDismiss: (_) => _confirmRemove(subscription),
                          onDismissed: (_) => _removeSubscription(subscription),
                          background: const _DeleteBackground(
                            alignment: Alignment.centerLeft,
                          ),
                          secondaryBackground: const _DeleteBackground(
                            alignment: Alignment.centerRight,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ),
                            child: InkWell(
                              onTap: () => _openSubscription(subscription),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    const FramedTopicIcon(
                                      key: Key('ntfy-topic-icon'),
                                      size: 40,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Hero(
                                            tag:
                                                'topic-title-${subscription.id}',
                                            transitionOnUserGestures: true,
                                            child: Material(
                                              color: Colors.transparent,
                                              child: LText(
                                                subscription.displayName ??
                                                    Uri.parse(subscription.url)
                                                        .pathSegments
                                                        .last,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(fontSize: 18),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          LText(
                                            _subscriptionSubtitle(
                                              context,
                                              subscription,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  fontSize: 13,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_hasConnectionError(subscription) ||
                                        subscription.unreadCount != 0) ...[
                                      const SizedBox(width: 8),
                                      if (_hasConnectionError(subscription))
                                        Icon(
                                          Icons.cloud_off_outlined,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          semanticLabel: tr(
                                            context,
                                            'Connection error',
                                          ),
                                        ),
                                      if (_hasConnectionError(subscription) &&
                                          subscription.unreadCount != 0)
                                        const SizedBox(width: 8),
                                      if (subscription.unreadCount != 0)
                                        _UnreadBadge(subscription.unreadCount),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FramedTopicIcon(size: 64),
            const SizedBox(height: 20),
            LText(
              "It looks like you don't have any subscriptions yet.",
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const LText(
              'Click the + to create or subscribe to a topic. Afterwards you receive notifications on your device when sending messages via PUT or POST.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 7),
            const LText(
              'Detailed instructions available on ntfy.sh, and in the docs.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

enum _HomeAction { settings, docs, update, reportBug }

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tr(context, '$count unread notifications'),
    child: Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
      child: LText(
        count > 99 ? '99+' : '$count',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onPrimary),
      ),
    ),
  );
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground({required this.alignment});

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

class _SubscribeDialog extends StatefulWidget {
  const _SubscribeDialog({required this.store, required this.defaultServer});

  final SubscriptionRepository store;
  final String defaultServer;

  @override
  State<_SubscribeDialog> createState() => _SubscribeDialogState();
}

class _SubscribeDialogState extends State<_SubscribeDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  String? _error;
  bool _saving = false;
  bool _useAnotherServer = false;

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_urlChanged);
  }

  @override
  void dispose() {
    _urlController
      ..removeListener(_urlChanged)
      ..dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _urlChanged() => setState(() => _error = null);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final input = _urlController.text.trim();
      final uri = Uri.tryParse(input);
      final url = uri != null && uri.hasScheme
          ? input
          : input.split('/').first.contains('.')
          ? 'https://$input'
          : '${widget.defaultServer.replaceFirst(RegExp(r'/+$'), '')}/${input.replaceFirst(RegExp(r'^/+'), '')}';
      final subscription = await widget.store.add(
        url: url,
        displayName: _nameController.text,
      );
      if (mounted) {
        setState(() => _saving = false);
        Navigator.pop(context, subscription);
      }
    } on SubscriptionException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Could not save the subscription. Please try again.');
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() {
        _saving = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSave = !_saving && _urlController.text.trim().isNotEmpty;
    return PopScope(
      canPop: !_saving,
      child: FractionallySizedBox(
        heightFactor: 0.76,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
              child: Row(
                children: [
                  Expanded(
                    child: LText(
                      'Subscribe to topic',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, 'Cancel'),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outline),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                children: [
                  TextField(
                    key: const Key('topic-url-field'),
                    controller: _urlController,
                    autofocus: false,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: tr(
                        context,
                        _useAnotherServer ? 'Topic URL' : 'Topic name',
                      ).toUpperCase(),
                      hintText: tr(
                        context,
                        _useAnotherServer
                            ? 'https://ntfy.sh/my_alerts'
                            : 'my_alerts',
                      ),
                      prefix: _useAnotherServer
                          ? null
                          : Text('${Uri.parse(widget.defaultServer).host}/'),
                      helperText: tr(
                        context,
                        'Topic names are public. Avoid sensitive information.',
                      ),
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(
                              () => _useAnotherServer = !_useAnotherServer,
                            ),
                      icon: Icon(
                        _useAnotherServer
                            ? Icons.keyboard_arrow_left
                            : Icons.keyboard_arrow_right,
                        size: 18,
                      ),
                      label: LText(
                        _useAnotherServer
                            ? 'Use default server'
                            : 'Use another server',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('display-name-field'),
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: tr(
                        context,
                        'Display name (optional)',
                      ).toUpperCase(),
                    ),
                  ),
                ],
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outline)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: canSave
                        ? [
                            BoxShadow(
                              color: scheme.shadow,
                              offset: hardShadowOffset,
                            ),
                          ]
                        : null,
                  ),
                  child: SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: canSave ? _save : null,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const LText('Subscribe'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
