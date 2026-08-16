import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app_controller.dart';
import 'app_database.dart';
import 'delivery_service.dart';
import 'models.dart';
import 'notification_service.dart';
import 'ntfy_client.dart';

const _ntfyGreen = Color(0xFF338574);
const _androidSettings = MethodChannel('dev.rahul.ntfy_flutter/settings');
const _routeDisposalDelay = Duration(milliseconds: 350);
const _retentionOptions = <int>[
  0,
  1 * 60 * 60,
  3 * 60 * 60,
  6 * 60 * 60,
  12 * 60 * 60,
  1 * 24 * 60 * 60,
  3 * 24 * 60 * 60,
  10 * 24 * 60 * 60,
  30 * 24 * 60 * 60,
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  final notifications = NotificationService();
  await notifications.initialize();
  final delivery = DeliveryService()..initialize();
  final controller = AppController(
    database: AppDatabase(),
    client: NtfyClient(),
    credentialStore: CredentialStore(),
    notificationService: notifications,
    deliveryService: delivery,
  );
  await controller.initialize();
  runApp(
    NtfyApp(
      controller: controller,
      notifications: notifications,
      delivery: delivery,
    ),
  );
}

class NtfyApp extends StatefulWidget {
  const NtfyApp({
    super.key,
    required this.controller,
    required this.notifications,
    required this.delivery,
  });

  final AppController controller;
  final NotificationService notifications;
  final DeliveryService delivery;

  @override
  State<NtfyApp> createState() => _NtfyAppState();
}

class _NtfyAppState extends State<NtfyApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<String>? _notificationTaps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.delivery.attach(widget.controller.reload);
    _notificationTaps = widget.notifications.tapPayloads.listen(
      _openNotificationPayload,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final payload = widget.notifications.takeLaunchPayload();
      if (payload != null) _openNotificationPayload(payload);
      unawaited(_startDeliveryForVisibleApp());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_startDeliveryForVisibleApp());
    }
  }

  Future<void> _startDeliveryForVisibleApp() async {
    if (widget.controller.summaries.isEmpty) return;
    try {
      await widget.delivery.ensureRunning();
    } catch (_) {
      // A later visible resume retries the foreground service start.
    }
  }

  void _openNotificationPayload(String payload) {
    final subscriptionId = parseSubscriptionPayload(payload);
    if (subscriptionId == null) return;
    for (final summary in widget.controller.summaries) {
      if (summary.subscription.id != subscriptionId) continue;
      _navigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => TopicFeedPage(
            controller: widget.controller,
            subscription: summary.subscription,
          ),
        ),
      );
      return;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.delivery.detach();
    unawaited(_notificationTaps?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigatorKey,
    title: 'ntfy',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: ThemeMode.system,
    home: SubscriptionListPage(controller: widget.controller),
  );
}

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _ntfyGreen,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
  );
}

class SubscriptionListPage extends StatelessWidget {
  const SubscriptionListPage({super.key, required this.controller});

  final AppController controller;

  void _openTopic(BuildContext context, Subscription subscription) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TopicFeedPage(controller: controller, subscription: subscription),
      ),
    );
  }

  Future<void> _openActions(
    BuildContext context,
    Subscription subscription,
  ) async {
    final action = await _chooseTopicAction(
      context,
      subscription,
      globalRetentionSeconds: controller.globalRetentionSeconds,
      includeOpen: true,
    );
    if (action == null) return;
    await Future<void>.delayed(_routeDisposalDelay);
    if (!context.mounted) return;
    switch (action) {
      case _TopicAction.open:
        _openTopic(context, subscription);
      case _TopicAction.rename:
        await _renameTopic(context, controller, subscription);
      case _TopicAction.autoDelete:
        await _chooseTopicRetention(context, controller, subscription);
      case _TopicAction.clearMessages:
        return;
      case _TopicAction.unsubscribe:
        await _confirmUnsubscribe(context, controller, subscription);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final summaries = controller.summaries;
      return Scaffold(
        appBar: AppBar(title: const Text('ntfy')),
        body: Column(
          children: [
            if (controller.loading) const LinearProgressIndicator(minHeight: 2),
            if (controller.error case final error?)
              if (summaries.isNotEmpty)
                _InlineError(message: error, onRetry: controller.reload),
            Expanded(
              child: summaries.isEmpty
                  ? _HomeState(controller: controller)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: summaries.length + 1,
                      separatorBuilder: (_, index) =>
                          SizedBox(height: index == 0 ? 20 : 12),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _HomeHeader(
                            topicCount: summaries.length,
                            globalRetentionSeconds:
                                controller.globalRetentionSeconds,
                          );
                        }
                        final summary = summaries[index - 1];
                        return Dismissible(
                          key: ValueKey('topic-${summary.subscription.id}'),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => unawaited(
                            controller.unsubscribe(summary.subscription),
                          ),
                          background: const _SwipeDeleteBackground(),
                          child: _TopicCard(
                            summary: summary,
                            enabled: !controller.loading,
                            onOpen: () =>
                                _openTopic(context, summary.subscription),
                            onActions: () =>
                                _openActions(context, summary.subscription),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        bottomNavigationBar: _HomeActions(
          loading: controller.loading,
          onRefresh: controller.reload,
          onSettings: () => _showAppSettings(context, controller),
          onAdd: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  AddSubscriptionPage(onSubmit: controller.subscribe),
            ),
          ),
        ),
      );
    },
  );
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.topicCount,
    required this.globalRetentionSeconds,
  });

  final int topicCount;
  final int globalRetentionSeconds;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your topics', style: textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          '$topicCount ${topicCount == 1 ? 'topic' : 'topics'}  •  Auto-delete ${_retentionLabel(globalRetentionSeconds).toLowerCase()}',
          style: textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _HomeState extends StatelessWidget {
  const _HomeState({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const _StatusView(
        progress: true,
        title: 'Loading topics',
        message: 'Checking your saved subscriptions…',
      );
    }
    if (controller.error case final error?) {
      return _StatusView(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load topics',
        message: error,
        actionLabel: 'Try again',
        onAction: controller.reload,
      );
    }
    return const _StatusView(
      icon: Icons.notifications_none_rounded,
      title: 'No topics yet',
      message: 'Add a topic to receive and send ntfy messages.',
    );
  }
}

class _HomeActions extends StatelessWidget {
  const _HomeActions({
    required this.loading,
    required this.onRefresh,
    required this.onSettings,
    required this.onAdd,
  });

  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => _BottomSurface(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: loading ? null : onSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Settings'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: loading ? null : onAdd,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add topic'),
          ),
        ),
      ],
    ),
  );
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.summary,
    required this.enabled,
    required this.onOpen,
    required this.onActions,
  });

  final TopicSummary summary;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final subscription = summary.subscription;
    final latest = summary.latestMessage;
    return Card(
      child: InkWell(
        onTap: enabled ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      Icons.notifications_outlined,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subscription.displayNameOrTopic,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.dns_outlined,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _topicAddressLabel(subscription),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (summary.unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(minWidth: 28),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        summary.unreadCount > 99
                            ? '99+'
                            : '${summary.unreadCount}',
                        textAlign: TextAlign.center,
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      latest?.message ?? 'No messages yet',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(
                        color: latest == null
                            ? colors.onSurfaceVariant
                            : colors.onSurface,
                      ),
                    ),
                  ),
                  if (latest != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      _shortTime(latest.time),
                      style: textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: enabled ? onActions : null,
                  icon: const Icon(Icons.more_horiz_rounded),
                  label: const Text('Manage'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(
        Icons.delete_outline_rounded,
        color: colors.onErrorContainer,
        size: 30,
      ),
    );
  }
}

enum _TopicAction { open, rename, autoDelete, clearMessages, unsubscribe }

Future<_TopicAction?> _chooseTopicAction(
  BuildContext context,
  Subscription subscription, {
  required int globalRetentionSeconds,
  required bool includeOpen,
  bool includeClearMessages = false,
}) => showModalBottomSheet<_TopicAction>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  builder: (context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subscription.displayNameOrTopic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _topicAddressLabel(subscription),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (includeOpen)
            ListTile(
              minTileHeight: 56,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Open topic'),
              onTap: () => Navigator.pop(context, _TopicAction.open),
            ),
          ListTile(
            minTileHeight: 56,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename display name'),
            subtitle: const Text('The server topic stays unchanged'),
            onTap: () => Navigator.pop(context, _TopicAction.rename),
          ),
          ListTile(
            minTileHeight: 56,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: const Icon(Icons.auto_delete_outlined),
            title: const Text('Auto-delete'),
            subtitle: Text(
              subscription.retentionSeconds == null
                  ? 'Uses global: ${_retentionLabel(globalRetentionSeconds)}'
                  : _retentionLabel(subscription.retentionSeconds!),
            ),
            onTap: () => Navigator.pop(context, _TopicAction.autoDelete),
          ),
          if (includeClearMessages)
            ListTile(
              minTileHeight: 56,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Remove all messages'),
              subtitle: const Text('Keep this topic subscribed'),
              onTap: () => Navigator.pop(context, _TopicAction.clearMessages),
            ),
          ListTile(
            minTileHeight: 56,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textColor: colors.error,
            iconColor: colors.error,
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Unsubscribe'),
            subtitle: const Text('Remove this topic and saved messages'),
            onTap: () => Navigator.pop(context, _TopicAction.unsubscribe),
          ),
        ],
      ),
    );
  },
);

Future<bool> _askToUnsubscribe(
  BuildContext context,
  Subscription subscription,
) async {
  final colors = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.delete_outline_rounded, color: colors.error),
      title: const Text('Unsubscribe?'),
      content: Text(
        'Remove ${subscription.displayNameOrTopic} and all of its saved messages?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Unsubscribe'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

Future<bool> _confirmUnsubscribe(
  BuildContext context,
  AppController controller,
  Subscription subscription,
) async {
  if (!await _askToUnsubscribe(context, subscription)) return false;
  return controller.unsubscribe(subscription);
}

enum _AppSettingsAction { retention, deliveryNotification }

Future<void> _showAppSettings(
  BuildContext context,
  AppController controller,
) async {
  final action = await showModalBottomSheet<_AppSettingsAction>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              'App settings',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            minTileHeight: 64,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: const Icon(Icons.auto_delete_outlined),
            title: const Text('Default auto-delete'),
            subtitle: Text(_retentionLabel(controller.globalRetentionSeconds)),
            onTap: () => Navigator.pop(context, _AppSettingsAction.retention),
          ),
          ListTile(
            minTileHeight: 72,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Listening notification'),
            subtitle: const Text(
              'Open Android channel settings. The service stays active, but Android may still show it under active apps.',
            ),
            onTap: () =>
                Navigator.pop(context, _AppSettingsAction.deliveryNotification),
          ),
        ],
      ),
    ),
  );
  if (action == null) return;
  await Future<void>.delayed(_routeDisposalDelay);
  if (!context.mounted) return;
  switch (action) {
    case _AppSettingsAction.retention:
      await _chooseGlobalRetention(context, controller);
    case _AppSettingsAction.deliveryNotification:
      try {
        await _androidSettings.invokeMethod<void>(
          'openDeliveryNotificationSettings',
        );
      } on PlatformException catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open Android settings: $error')),
          );
        }
      }
  }
}

Future<void> _renameTopic(
  BuildContext context,
  AppController controller,
  Subscription subscription,
) async {
  final editor = TextEditingController(text: subscription.displayName ?? '');
  final displayName = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rename display name',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _topicAddressLabel(subscription),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: editor,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Display name',
              hintText: 'Leave blank to show the real topic name',
              prefixIcon: Icon(Icons.label_outline_rounded),
            ),
            onSubmitted: (value) => Navigator.pop(context, value.trim()),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, editor.text.trim()),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(_routeDisposalDelay);
  editor.dispose();
  if (displayName == null || !context.mounted) return;
  await controller.setDisplayName(subscription, displayName);
}

Future<void> _chooseGlobalRetention(
  BuildContext context,
  AppController controller,
) async {
  final selected = await _showRetentionSheet(
    context,
    title: 'Default auto-delete',
    selectedSeconds: controller.globalRetentionSeconds,
  );
  if (selected == null || !context.mounted) return;
  await controller.setGlobalRetentionSeconds(selected);
}

Future<void> _chooseTopicRetention(
  BuildContext context,
  AppController controller,
  Subscription subscription,
) async {
  final selected = await _showRetentionSheet(
    context,
    title: subscription.displayNameOrTopic,
    selectedSeconds: subscription.retentionSeconds ?? -1,
    globalSeconds: controller.globalRetentionSeconds,
  );
  if (selected == null || !context.mounted) return;
  await controller.setSubscriptionRetentionSeconds(
    subscription,
    selected == -1 ? null : selected,
  );
}

Future<int?> _showRetentionSheet(
  BuildContext context, {
  required String title,
  required int selectedSeconds,
  int? globalSeconds,
}) => showModalBottomSheet<int>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) {
    final options = globalSeconds == null
        ? _retentionOptions
        : [-1, ..._retentionOptions];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text('Messages are removed from this phone only.'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
              itemCount: options.length,
              itemBuilder: (context, index) {
                final seconds = options[index];
                final label = seconds == -1
                    ? 'Use global (${_retentionLabel(globalSeconds!)})'
                    : _retentionLabel(seconds);
                final selected = seconds == selectedSeconds;
                return ListTile(
                  minTileHeight: 56,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: Icon(
                    seconds <= 0
                        ? Icons.all_inclusive_rounded
                        : Icons.schedule_rounded,
                  ),
                  title: Text(label),
                  trailing: selected
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, seconds),
                );
              },
            ),
          ),
        ],
      ),
    );
  },
);

Future<bool> _confirmClearMessages(
  BuildContext context,
  AppController controller,
  Subscription subscription,
) async {
  final colors = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.delete_sweep_outlined, color: colors.error),
      title: const Text('Remove all messages?'),
      content: Text(
        'Clear the saved feed for ${subscription.displayNameOrTopic} on this phone? The subscription stays active.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove all'),
        ),
      ],
    ),
  );
  return confirmed == true && await controller.clearMessages(subscription);
}

typedef AddSubscriptionCallback = Future<bool> Function(
  String baseUrl,
  String topic,
  String? displayName,
  AuthCredential credential,
);

class AddSubscriptionPage extends StatefulWidget {
  const AddSubscriptionPage({super.key, required this.onSubmit});

  final AddSubscriptionCallback onSubmit;

  @override
  State<AddSubscriptionPage> createState() => _AddSubscriptionPageState();
}

class _AddSubscriptionPageState extends State<AddSubscriptionPage> {
  final _formKey = GlobalKey<FormState>();
  final _topicUrl = TextEditingController(text: 'https://ntfy.sh/');
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _secret = TextEditingController();
  AuthType _authType = AuthType.none;
  bool _submitting = false;

  @override
  void dispose() {
    _topicUrl.dispose();
    _displayName.dispose();
    _username.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add topic')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Text(
            'Subscribe to a topic',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Paste one complete ntfy topic URL and optionally give it a friendly name.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 20),
          _SectionCard(
            title: 'Topic details',
            child: Column(
              children: [
                TextFormField(
                  controller: _topicUrl,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Topic URL',
                    hintText: 'https://ntfy.sh/my-private-topic',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    try {
                      NtfyClient.parseTopicUrl(value ?? '');
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _displayName,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Display name (optional)',
                    hintText: 'Home alerts',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                _PrivacyNotice(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Authentication',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<AuthType>(
                  segments: const [
                    ButtonSegment(
                      value: AuthType.none,
                      label: Text('None'),
                      icon: Icon(Icons.public_rounded),
                    ),
                    ButtonSegment(
                      value: AuthType.basic,
                      label: Text('Basic'),
                      icon: Icon(Icons.person_outline_rounded),
                    ),
                    ButtonSegment(
                      value: AuthType.bearer,
                      label: Text('Bearer'),
                      icon: Icon(Icons.key_rounded),
                    ),
                  ],
                  selected: {_authType},
                  showSelectedIcon: false,
                  onSelectionChanged: _submitting
                      ? null
                      : (selection) =>
                            setState(() => _authType = selection.single),
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(Size(48, 52)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (_authType == AuthType.basic) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _username,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: _required,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _secret,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: _required,
                  ),
                ],
                if (_authType == AuthType.bearer) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _secret,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: 'Token',
                      prefixIcon: Icon(Icons.key_rounded),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: _required,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: _BottomSurface(
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_active_outlined),
              label: Text(_submitting ? 'Subscribing…' : 'Subscribe'),
            ),
          ),
        ],
      ),
    ),
  );

  String? _required(String? value) =>
      value == null || value.isEmpty ? 'This field is required' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final address = NtfyClient.parseTopicUrl(_topicUrl.text);
    setState(() => _submitting = true);
    final credential = switch (_authType) {
      AuthType.none => const AuthCredential.none(),
      AuthType.basic => AuthCredential.basic(
        username: _username.text,
        password: _secret.text,
      ),
      AuthType.bearer => AuthCredential.bearer(_secret.text),
    };
    final added = await widget.onSubmit(
      address.baseUrl,
      address.topic,
      _displayName.text,
      credential,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (added) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not subscribe')));
    }
  }
}

class _PrivacyNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: colors.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Public topic names should be hard to guess. Anyone who knows the name may be able to read or publish messages.',
              style: TextStyle(color: colors.onTertiaryContainer, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

class TopicFeedPage extends StatefulWidget {
  const TopicFeedPage({
    super.key,
    required this.controller,
    required this.subscription,
  });

  final AppController controller;
  final Subscription subscription;

  @override
  State<TopicFeedPage> createState() => _TopicFeedPageState();
}

class _TopicFeedPageState extends State<TopicFeedPage> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  late Subscription _subscription = widget.subscription;
  List<StoredMessage> _messages = const [];
  bool _loading = true;
  bool _loadingMessages = false;
  String? _messageError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_controllerChanged);
    _open();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted) return;
    setState(() {});
    if (!widget.controller.loading) {
      _syncSubscription();
      unawaited(_loadMessages());
    }
  }

  Future<void> _open() async {
    await widget.controller.markRead(_subscription);
    await _loadMessages();
  }

  Future<void> _loadMessages() async {
    if (_loadingMessages) return;
    _loadingMessages = true;
    try {
      final messages = await widget.controller.listMessages(_subscription);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _messageError = null;
        _loading = false;
      });
      _scrollToLatest();
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _messageError = exception.toString();
        _loading = false;
      });
    } finally {
      _loadingMessages = false;
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _refresh() async {
    await widget.controller.refresh(_subscription);
    _syncSubscription();
    await widget.controller.markRead(_subscription);
    await _loadMessages();
  }

  void _syncSubscription() {
    for (final summary in widget.controller.summaries) {
      if (summary.subscription.id == _subscription.id) {
        _subscription = summary.subscription;
        return;
      }
    }
  }

  Future<void> _publish() async {
    final message = _composer.text;
    if (message.trim().isEmpty) return;
    if (await widget.controller.publish(_subscription, message)) {
      _composer.clear();
      _syncSubscription();
      await _loadMessages();
    }
  }

  Future<void> _showMore() async {
    final action = await _chooseTopicAction(
      context,
      _subscription,
      globalRetentionSeconds: widget.controller.globalRetentionSeconds,
      includeOpen: false,
      includeClearMessages: true,
    );
    if (action == null) return;
    await Future<void>.delayed(_routeDisposalDelay);
    if (!mounted) return;
    switch (action) {
      case _TopicAction.rename:
        await _renameTopic(context, widget.controller, _subscription);
        _syncSubscription();
      case _TopicAction.autoDelete:
        await _chooseTopicRetention(context, widget.controller, _subscription);
        _syncSubscription();
      case _TopicAction.clearMessages:
        final cleared = await _confirmClearMessages(
          context,
          widget.controller,
          _subscription,
        );
        if (cleared && mounted) await _loadMessages();
      case _TopicAction.unsubscribe:
        final removed = await _confirmUnsubscribe(
          context,
          widget.controller,
          _subscription,
        );
        if (removed && mounted) Navigator.pop(context);
      case _TopicAction.open:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _messageError ?? widget.controller.error;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _subscription.displayNameOrTopic,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _topicAddressLabel(_subscription),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (widget.controller.loading)
            const LinearProgressIndicator(minHeight: 2),
          if (error != null && _messages.isNotEmpty)
            _InlineError(message: error, onRetry: _refresh),
          Expanded(child: _buildMessages(error)),
          _ComposerPanel(
            controller: _composer,
            enabled: !widget.controller.loading,
            onMore: _showMore,
            onSend: _publish,
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(String? error) {
    Widget state;
    if (_loading) {
      state = const _StatusView(
        progress: true,
        title: 'Loading messages',
        message: 'Opening this topic…',
      );
    } else if (error != null && _messages.isEmpty) {
      state = _StatusView(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load messages',
        message: error,
        actionLabel: 'Try again',
        onAction: _refresh,
      );
    } else if (_messages.isEmpty) {
      state = const _StatusView(
        icon: Icons.forum_outlined,
        title: 'No messages yet',
        message: 'Pull down to refresh or send the first message below.',
      );
    } else {
      final chronologicalMessages = _messages.reversed.toList(growable: false);
      state = SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        sliver: SliverList.separated(
          itemCount: chronologicalMessages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final message = chronologicalMessages[index];
            return Dismissible(
              key: ValueKey('message-${message.id}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) {
                setState(() {
                  _messages = _messages
                      .where((item) => item.id != message.id)
                      .toList(growable: false);
                });
                unawaited(widget.controller.deleteMessage(message));
              },
              background: const _SwipeDeleteBackground(),
              child: _MessageCard(message: message),
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (state is SliverPadding)
            state
          else
            SliverFillRemaining(hasScrollBody: false, child: state),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final StoredMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: message.title == null
                      ? Text(
                          'Message',
                          style: textTheme.labelLarge?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : Text(
                          message.title!,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Text(
                  _messageTime(message.time),
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              message.message,
              style: textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
            if (message.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                message.tags.join('  •  '),
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComposerPanel extends StatelessWidget {
  const _ComposerPanel({
    required this.controller,
    required this.enabled,
    required this.onMore,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onMore;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => _BottomSurface(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: enabled ? onMore : null,
            icon: const Icon(Icons.more_horiz_rounded),
            label: const Text('Topic options'),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Write a message',
                  prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Send message',
              child: FilledButton(
                onPressed: enabled ? onSend : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  padding: EdgeInsets.zero,
                ),
                child: const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({
    this.icon,
    required this.title,
    required this.message,
    this.progress = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData? icon;
  final String title;
  final String message;
  final bool progress;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (progress)
                const CircularProgressIndicator()
              else
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 34, color: colors.onPrimaryContainer),
                ),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: colors.onSurfaceVariant, height: 1.4),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomSurface extends StatelessWidget {
  const _BottomSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: child,
      ),
    );
  }
}

String _retentionLabel(int seconds) => switch (seconds) {
  0 => 'Never',
  3600 => '1 hour',
  10800 => '3 hours',
  21600 => '6 hours',
  43200 => '12 hours',
  86400 => '1 day',
  259200 => '3 days',
  864000 => '10 days',
  2592000 => '30 days',
  _ => '${Duration(seconds: seconds).inHours} hours',
};

String _topicAddressLabel(Subscription subscription) =>
    '${_serverLabel(subscription.baseUrl)}/${subscription.topic}';

String _serverLabel(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || uri.host.isEmpty) return baseUrl;
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

String _shortTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return _clockTime(local);
  }
  if (local.year == now.year) return '${_month(local.month)} ${local.day}';
  return '${_month(local.month)} ${local.day}, ${local.year}';
}

String _messageTime(DateTime value) {
  final local = value.toLocal();
  return '${_month(local.month)} ${local.day} · ${_clockTime(local)}';
}

String _clockTime(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _month(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];
