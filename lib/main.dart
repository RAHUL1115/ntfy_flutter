import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';
import 'background_listening.dart';
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

final darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xff84d6c2),
    onPrimary: Color(0xff00382e),
    surface: Color(0xff121212),
    onSurface: Color(0xffe0e0e0),
    surfaceContainerHigh: Color(0xff282f33),
    onSurfaceVariant: Color(0xffbfc9c5),
  ),
  scaffoldBackgroundColor: const Color(0xff121212),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xff1b2023),
    foregroundColor: Color(0xffe0e0e0),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: Color(0xff84d6c2),
    foregroundColor: Color(0xff00382e),
  ),
);

final lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.light(
    primary: Color(0xff338574),
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: Color(0xff171d1b),
    surfaceContainerHigh: Color(0xffeeeeee),
    onSurfaceVariant: Color(0xff3f4946),
  ),
  scaffoldBackgroundColor: Colors.white,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: Color(0xff171d1b),
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: Color(0xff338574),
    foregroundColor: Colors.white,
  ),
);

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
          ? lightTheme.copyWith(colorScheme: dynamicLight)
          : lightTheme,
      darkTheme: _appSettings.dynamicColors && dynamicDark != null
          ? darkTheme.copyWith(colorScheme: dynamicDark)
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
      case _HomeAction.rate:
        final package = await PackageInfo.fromPlatform();
        final market = Uri.parse('market://details?id=${package.packageName}');
        if (!await launchUrl(market, mode: LaunchMode.externalApplication)) {
          await _openExternal(
            Uri.parse(
              'https://play.google.com/store/apps/details?id=${package.packageName}',
            ),
          );
        }
      case _HomeAction.reportBug:
        await _openExternal(
          Uri.parse('https://github.com/binwiederhier/ntfy/issues'),
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
    final saved = await showDialog<Subscription>(
      context: context,
      barrierDismissible: false,
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
    return subscription.displayName == null
        ? details.toString()
        : '${subscription.url}\n$details';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const LText('Subscribed topics'),
        actions: [
          if (_connections.any((item) => item.error != null))
            IconButton(
              key: const Key('connection-error'),
              tooltip: tr(context, 'Connection error'),
              onPressed: _showConnectionErrors,
              icon: const Icon(Icons.cloud_off_outlined),
            ),
          if (_globalPolicy != null)
            IconButton(
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
                    ? Icons.notifications
                    : Icons.notifications_off_outlined,
              ),
            ),
          PopupMenuButton<_HomeAction>(
            onSelected: (action) => unawaited(_selectHomeAction(action)),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _HomeAction.settings,
                child: LText('Settings'),
              ),
              PopupMenuItem(
                value: _HomeAction.docs,
                child: LText('Documentation'),
              ),
              PopupMenuItem(value: _HomeAction.rate, child: LText('Rate app')),
              PopupMenuItem(
                value: _HomeAction.reportBug,
                child: LText('Report a bug'),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: Semantics(
        button: true,
        label: tr(context, 'Add subscription'),
        child: FloatingActionButton(
          onPressed: _showSubscribeDialog,
          tooltip: tr(context, 'Add subscription'),
          child: const Icon(Icons.add),
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
      return RefreshIndicator(
        onRefresh: _manualRefresh,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: subscriptions.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
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
              child: ListTile(
                leading: const NtfyTopicIcon(
                  key: Key('ntfy-topic-icon'),
                  size: 35,
                ),
                title: LText(subscription.displayName ?? subscription.url),
                subtitle: LText(_subscriptionSubtitle(context, subscription)),
                trailing:
                    !_hasConnectionError(subscription) &&
                        subscription.unreadCount == 0
                    ? null
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_hasConnectionError(subscription))
                            Icon(
                              Icons.cloud_off_outlined,
                              color: Theme.of(context).colorScheme.error,
                              semanticLabel: tr(context, 'Connection error'),
                            ),
                          if (_hasConnectionError(subscription) &&
                              subscription.unreadCount != 0)
                            const SizedBox(width: 8),
                          if (subscription.unreadCount != 0)
                            _UnreadBadge(subscription.unreadCount),
                        ],
                      ),
                onTap: () => _openSubscription(subscription),
              ),
            );
          },
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NtfyTopicIcon(size: 48),
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

enum _HomeAction { settings, docs, rate, reportBug }

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: tr(context, '$count unread notifications'),
    child: Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LText(
        count > 99 ? '99+' : '$count',
        style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
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
    return PopScope(
      canPop: !_saving,
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: tr(context, 'Cancel'),
              onPressed: _saving ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
            title: const LText('Subscribe to topic'),
            actions: [
              TextButton(
                onPressed: _saving || _urlController.text.trim().isEmpty
                    ? null
                    : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const LText('SUBSCRIBE'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const LText(
                'Enter a topic name or URL to start receiving notifications.',
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('topic-url-field'),
                controller: _urlController,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: tr(context, 'Topic name or URL'),
                  hintText: tr(context, 'mytopic'),
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('display-name-field'),
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: tr(context, 'Display name (optional)'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
