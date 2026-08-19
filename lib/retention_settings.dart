import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import 'app_settings.dart';
import 'attachments.dart';
import 'background_listening.dart';
import 'design.dart';
import 'l10n.dart';
import 'notification_policy.dart';
import 'notifications.dart';
import 'retention.dart';
import 'subscriptions.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.retention,
    required this.backgroundListening,
    this.policies,
    this.settings,
    this.database,
    this.onSettingsChanged,
    super.key,
  });

  final RetentionSession retention;
  final BackgroundListeningSession backgroundListening;
  final NotificationPolicyRepository? policies;
  final AppSettingsRepository? settings;
  final SubscriptionStore? database;
  final Future<void> Function()? onSettingsChanged;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CollapsibleDesignBody(
      title: const LText('Settings'),
      child: ListView(
        children: [
          if (policies != null)
            _NotificationPolicySettings(
              policies: policies!,
              retention: retention,
              trailingRows: [
                _BackgroundListeningSettings(session: backgroundListening),
              ],
            )
          else ...[
            const _SectionHeader('Notifications'),
            _SettingsPanel(
              children: [
                _RetentionSettings(retention: retention),
                _BackgroundListeningSettings(session: backgroundListening),
              ],
            ),
          ],
          if (settings != null)
            _AppSettingsPanel(
              repository: settings!,
              database: database,
              onChanged: onSettingsChanged,
            ),
        ],
      ),
    ),
  );
}

class TopicSettingsScreen extends StatefulWidget {
  const TopicSettingsScreen({
    required this.subscription,
    required this.retention,
    this.onRename,
    this.policies,
    this.onBackgroundEnabled,
    super.key,
  });

  final Subscription subscription;
  final RetentionSession retention;
  final Future<Subscription> Function(String? displayName)? onRename;
  final NotificationPolicyRepository? policies;
  final Future<Subscription> Function(bool enabled)? onBackgroundEnabled;

  @override
  State<TopicSettingsScreen> createState() => _TopicSettingsScreenState();
}

class _TopicSettingsScreenState extends State<TopicSettingsScreen> {
  late Subscription _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.subscription;
  }

  void _close() => Navigator.pop(context, _subscription);

  Widget _backgroundDelivery() => _SquareSwitchListTile(
    key: const Key('topic-background-listening'),
    title: const LText('Background delivery'),
    subtitle: const LText('Receive this topic while the app is not visible.'),
    value: _subscription.backgroundEnabled,
    onChanged: (enabled) async {
      final updated = await widget.onBackgroundEnabled!(enabled);
      if (mounted) setState(() => _subscription = updated);
    },
  );

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: _subscription.displayName);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Display name'),
        content: TextField(
          key: const Key('display-name-field'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: Uri.parse(_subscription.url).pathSegments.last,
            helperText: tr(context, 'Leave empty to use the topic name.'),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const LText('Save'),
          ),
        ],
      ),
    );
    if (value == null || !context.mounted) return;
    try {
      final updated = await widget.onRename!(value);
      if (mounted) setState(() => _subscription = updated);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: LText('Could not rename this topic.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Subscription>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Scaffold(
      body: CollapsibleDesignBody(
        title: LText(
          _subscription.displayName ??
              Uri.parse(_subscription.url).pathSegments.last,
        ),
        child: ListView(
          children: [
            const _SectionHeader('Notifications'),
            if (widget.policies != null)
              _NotificationPolicySettings(
                policies: widget.policies!,
                subscriptionId: _subscription.id,
                retention: widget.retention,
                showHeader: false,
                showAppearanceHeader: true,
                leadingRows: [
                  if (widget.onBackgroundEnabled != null) _backgroundDelivery(),
                ],
              )
            else
              _SettingsPanel(
                children: [
                  if (widget.onBackgroundEnabled != null) _backgroundDelivery(),
                  _RetentionSettings(
                    retention: widget.retention,
                    subscriptionId: _subscription.id,
                  ),
                ],
              ),
            if (widget.onRename != null) ...[
              if (widget.policies == null) const _SectionHeader('Appearance'),
              _SettingsPanel(
                children: [
                  ListTile(
                    key: const Key('topic-display-name'),
                    title: const LText('Display name'),
                    subtitle: LText(
                      _subscription.displayName ??
                          Uri.parse(_subscription.url).pathSegments.last,
                    ),
                    onTap: () => _rename(context),
                  ),
                ],
              ),
            ],
            const _SectionHeader('About'),
            _SettingsPanel(
              children: [
                ListTile(
                  key: const Key('topic-url'),
                  title: const LText('Topic URL'),
                  subtitle: LText(_subscription.url),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: _subscription.url),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: LText('Topic URL copied.')),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _NotificationPolicySettings extends StatefulWidget {
  const _NotificationPolicySettings({
    required this.policies,
    this.subscriptionId,
    this.retention,
    this.showHeader = true,
    this.showAppearanceHeader = false,
    this.leadingRows = const [],
    this.trailingRows = const [],
  });

  final NotificationPolicyRepository policies;
  final int? subscriptionId;
  final RetentionSession? retention;
  final bool showHeader;
  final bool showAppearanceHeader;

  /// Rows shown above the policy rows inside the same outlined panel.
  final List<Widget> leadingRows;

  /// Rows shown below the policy rows inside the same outlined panel.
  final List<Widget> trailingRows;

  @override
  State<_NotificationPolicySettings> createState() =>
      _NotificationPolicySettingsState();
}

class _NotificationPolicySettingsState
    extends State<_NotificationPolicySettings> {
  NotificationPolicy? _policy;
  TopicNotificationPolicyOverrides? _overrides;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final policy = await widget.policies.loadNotificationPolicy(
      subscriptionId: widget.subscriptionId,
    );
    TopicNotificationPolicyOverrides? overrides;
    final subscriptionId = widget.subscriptionId;
    final repository = widget.policies;
    if (subscriptionId != null &&
        repository is TopicNotificationPolicyRepository) {
      final overrideRepository =
          repository as TopicNotificationPolicyRepository;
      overrides = await overrideRepository.loadTopicNotificationPolicyOverrides(
        subscriptionId,
      );
    }
    if (mounted) {
      setState(() {
        _policy = policy;
        _overrides = overrides;
      });
    }
  }

  Future<void> _saveOverrides(
    TopicNotificationPolicyOverrides overrides,
  ) async {
    final subscriptionId = widget.subscriptionId;
    final repository = widget.policies;
    if (subscriptionId == null ||
        repository is! TopicNotificationPolicyRepository) {
      return;
    }
    await (repository as TopicNotificationPolicyRepository)
        .setTopicNotificationPolicyOverrides(subscriptionId, overrides);
    await _load();
  }

  Future<void> _save(NotificationPolicy policy) async {
    final subscriptionId = widget.subscriptionId;
    if (subscriptionId == null) {
      await widget.policies.setGlobalNotificationPolicy(policy);
    } else {
      await widget.policies.setTopicNotificationPolicy(subscriptionId, policy);
    }
    await _load();
  }

  Future<void> _selectMute() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final choices = <(String, int?)>[
      if (widget.subscriptionId != null) ('Use global setting', null),
      ('Show all notifications', 0),
      (
        '30 minutes',
        now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000,
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
    ];
    final selected = await showDialog<(String, int?)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const LText('Mute notifications'),
        children: [
          for (final choice in choices)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, choice),
              child: LText(choice.$1),
            ),
        ],
      ),
    );
    final policy = _policy;
    final overrides = _overrides;
    if (selected != null && policy != null) {
      if (widget.subscriptionId != null && overrides != null) {
        await _saveOverrides(
          overrides.copyWith(mutedUntilEpochSeconds: selected.$2),
        );
      } else if (selected.$2 != null) {
        await _save(policy.copyWith(mutedUntilEpochSeconds: selected.$2));
      }
    }
  }

  Future<void> _selectPriority() async {
    final selected = await showDialog<(bool, int?)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const LText('Minimum priority'),
        children: [
          if (widget.subscriptionId != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (true, null)),
              child: const LText('Use global setting'),
            ),
          for (var priority = 1; priority <= 5; priority++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (false, priority)),
              child: LText('$priority — ${_priorityName(priority)}'),
            ),
        ],
      ),
    );
    final policy = _policy;
    final overrides = _overrides;
    if (selected != null && policy != null) {
      if (widget.subscriptionId != null && overrides != null) {
        await _saveOverrides(overrides.copyWith(minimumPriority: selected.$2));
      } else if (selected.$2 != null) {
        await _save(policy.copyWith(minimumPriority: selected.$2));
      }
    }
  }

  Future<void> _selectDownloadPolicy() async {
    final selected = await showDialog<(bool, int?)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const LText('Download attachments'),
        children: [
          if (widget.subscriptionId != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (true, null)),
              child: const LText('Use global setting'),
            ),
          for (final value in const [
            (0, 'Never'),
            (1, 'Always'),
            (102400, 'Up to 100 KB'),
            (512000, 'Up to 500 KB'),
            (1048576, 'Up to 1 MB'),
            (5242880, 'Up to 5 MB'),
            (10485760, 'Up to 10 MB'),
            (52428800, 'Up to 50 MB'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (false, value.$1)),
              child: LText(value.$2),
            ),
        ],
      ),
    );
    final policy = _policy;
    final overrides = _overrides;
    if (selected != null && policy != null) {
      if (widget.subscriptionId != null && overrides != null) {
        await _saveOverrides(
          overrides.copyWith(attachmentDownloadMaxBytes: selected.$2),
        );
      } else if (selected.$2 != null) {
        await _save(policy.copyWith(attachmentDownloadMaxBytes: selected.$2));
      }
    }
  }

  Future<void> _selectBooleanOverride({
    required String title,
    required void Function(bool? value) save,
  }) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: LText(title),
        children: [
          for (final value in const [
            ('global', 'Use global setting'),
            ('on', 'Enabled'),
            ('off', 'Disabled'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value.$1),
              child: LText(value.$2),
            ),
        ],
      ),
    );
    if (selected == null) return;
    save(switch (selected) {
      'on' => true,
      'off' => false,
      _ => null,
    });
  }

  Future<void> _selectIcon() async {
    final subscriptionId = widget.subscriptionId;
    if (subscriptionId == null) return;
    final result = await FilePicker.pickFiles(type: FileType.image);
    final sourcePath = result.singleOrNull?.path;
    if (sourcePath == null) return;
    try {
      final path = await const SubscriptionIconService().save(
        sourcePath,
        subscriptionId,
      );
      final overrides = _overrides;
      if (overrides != null) {
        await _saveOverrides(overrides.copyWith(subscriptionIconPath: path));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LText('Could not save subscription icon: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = _policy;
    final overrides = _overrides;
    if (policy == null) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) const _SectionHeader('Notifications'),
        _SettingsPanel(
          children: [
            ...widget.leadingRows,
            ListTile(
              key: const Key('mute-notifications'),
              title: const LText('Mute notifications'),
              subtitle: LText(_muteSummary(policy.mutedUntilEpochSeconds)),
              onTap: _selectMute,
            ),
            ListTile(
              key: const Key('minimum-priority'),
              title: const LText('Minimum priority'),
              subtitle: LText(
                '${policy.minimumPriority == 1 ? 'Showing all notifications' : 'Priority ${policy.minimumPriority} or higher'}${widget.subscriptionId != null && overrides?.minimumPriority == null ? ' (using global setting)' : ''}',
              ),
              onTap: _selectPriority,
            ),
            ListTile(
              key: const Key('attachment-download-policy'),
              title: const LText('Download attachments'),
              subtitle: LText(
                '${_downloadPolicyLabel(policy.attachmentDownloadMaxBytes)}${widget.subscriptionId != null && overrides?.attachmentDownloadMaxBytes == null ? ' (using global setting)' : ''}',
              ),
              onTap: _selectDownloadPolicy,
            ),
            if (widget.retention != null)
              _RetentionSettings(retention: widget.retention!),
            if (widget.subscriptionId == null)
              _SquareSwitchListTile(
                key: const Key('insistent-max-priority'),
                title: const LText('Keep alerting for highest priority'),
                subtitle: const LText(
                  'Max priority notifications keep alerting until opened.',
                ),
                value: policy.insistentMaxPriority,
                onChanged: (value) =>
                    _save(policy.copyWith(insistentMaxPriority: value)),
              )
            else
              ListTile(
                key: const Key('insistent-max-priority'),
                title: const LText('Keep alerting for highest priority'),
                subtitle: LText(
                  '${policy.insistentMaxPriority ? 'Enabled' : 'Disabled'}${overrides?.insistentMaxPriority == null ? ' (using global setting)' : ''}',
                ),
                onTap: overrides == null
                    ? null
                    : () => _selectBooleanOverride(
                        title: 'Keep alerting for highest priority',
                        save: (value) => unawaited(
                          _saveOverrides(
                            overrides.copyWith(insistentMaxPriority: value),
                          ),
                        ),
                      ),
              ),
            if (widget.subscriptionId != null)
              ListTile(
                key: const Key('dedicated-notification-channel'),
                title: const LText('Dedicated notification channel'),
                subtitle: LText(
                  '${policy.dedicatedChannel ? 'Enabled' : 'Disabled'}${overrides?.dedicatedChannel == null ? ' (using global setting)' : ''}',
                ),
                onTap: overrides == null
                    ? null
                    : () => _selectBooleanOverride(
                        title: 'Dedicated notification channel',
                        save: (value) => unawaited(
                          _saveOverrides(
                            overrides.copyWith(dedicatedChannel: value),
                          ),
                        ),
                      ),
              ),
            ListTile(
              key: const Key('message-channel-settings'),
              title: const LText('Notification settings'),
              subtitle: const LText('Open Android notification controls.'),
              onTap: () => const AndroidNotificationSettings().open(
                subscriptionId: policy.dedicatedChannel
                    ? widget.subscriptionId
                    : null,
              ),
            ),
            ...widget.trailingRows,
          ],
        ),
        if (widget.subscriptionId != null) ...[
          if (widget.showAppearanceHeader) const _SectionHeader('Appearance'),
          _SettingsPanel(
            children: [
              ListTile(
                key: const Key('subscription-icon'),
                title: LText(
                  policy.subscriptionIconPath == null
                      ? 'Subscription icon'
                      : 'Subscription icon (tap to remove)',
                ),
                subtitle: LText(
                  policy.subscriptionIconPath == null
                      ? 'Set an icon to be displayed in notifications'
                      : 'Icon displayed in notifications for this topic',
                ),
                onTap: policy.subscriptionIconPath == null
                    ? _selectIcon
                    : overrides == null
                    ? null
                    : () => _saveOverrides(
                        overrides.copyWith(subscriptionIconPath: null),
                      ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _muteSummary(int value) {
  if (value == 0) return 'Showing all notifications';
  if (value == NotificationPolicy.untilResumed) return 'Muted until resumed';
  final time = DateTime.fromMillisecondsSinceEpoch(value * 1000).toLocal();
  return 'Muted until ${time.toString().substring(0, 16)}';
}

String _priorityName(int priority) => switch (priority) {
  1 => 'Min',
  2 => 'Low',
  4 => 'High',
  5 => 'Max',
  _ => 'Default',
};

String _downloadPolicyLabel(int bytes) => switch (bytes) {
  0 => 'Never',
  1 => 'Always',
  >= 1048576 => 'Up to ${bytes ~/ 1048576} MB',
  _ => 'Up to ${bytes ~/ 1024} KB',
};

String _connectionAlertSummary(int seconds) => switch (seconds) {
  0 => 'Never notify when the ntfy server cannot be reached',
  300 => 'Notify after 5 minutes without a connection',
  900 => 'Notify after 15 minutes without a connection',
  3600 => 'Notify after 1 hour without a connection',
  10800 => 'Notify after 3 hours without a connection',
  43200 => 'Notify after 12 hours without a connection',
  _ => 'Notify when disconnected',
};

class _RetentionSettings extends StatefulWidget {
  const _RetentionSettings({required this.retention, this.subscriptionId});

  final RetentionSession retention;
  final int? subscriptionId;

  @override
  State<_RetentionSettings> createState() => _RetentionSettingsState();
}

class _RetentionSettingsState extends State<_RetentionSettings> {
  RetentionSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.retention.load(
      subscriptionId: widget.subscriptionId,
    );
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _select() async {
    final settings = _settings;
    if (settings == null) return;
    final choices = [
      if (widget.subscriptionId != null)
        const _RetentionChoice('Use global setting', null),
      for (final period in RetentionPeriod.values)
        _RetentionChoice(period.label, period),
    ];
    final selected = await showDialog<_RetentionChoice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const LText('Delete notifications'),
        children: [
          for (final choice in choices)
            Semantics(
              selected: _selected(settings, choice.period),
              inMutuallyExclusiveGroup: true,
              child: SimpleDialogOption(
                onPressed: () => Navigator.pop(context, choice),
                child: Row(
                  children: [
                    Icon(
                      _selected(settings, choice.period)
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: LText(choice.label)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    try {
      final now = DateTime.now().toUtc();
      final subscriptionId = widget.subscriptionId;
      await widget.retention.execute(
        subscriptionId == null
            ? SetGlobalRetention(selected.period!, now: now)
            : SetTopicRetention(subscriptionId, selected.period, now: now),
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LText('Could not update notification retention.'),
          ),
        );
      }
    }
  }

  bool _selected(RetentionSettings settings, RetentionPeriod? period) {
    if (widget.subscriptionId == null) return settings.global == period;
    return settings.override == period;
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return ListTile(
      title: const LText('Delete notifications'),
      subtitle: LText(
        widget.subscriptionId == null
            ? settings.global.summary
            : settings.summary,
      ),
      onTap: _select,
    );
  }
}

class _BackgroundListeningSettings extends StatefulWidget {
  const _BackgroundListeningSettings({required this.session});

  final BackgroundListeningSession session;

  @override
  State<_BackgroundListeningSettings> createState() =>
      _BackgroundListeningSettingsState();
}

class _BackgroundListeningSettingsState
    extends State<_BackgroundListeningSettings> {
  BackgroundListeningSettings? _settings;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.session.load();
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _saving = true);
    try {
      await widget.session.execute(SetBackgroundListening(enabled));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LText('Could not update background listening.'),
          ),
        );
      }
    } finally {
      await _load();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openChannelSettings() async {
    try {
      await widget.session.execute(const OpenBackgroundChannelSettings());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LText('Could not open Android notification settings.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _settings?.enabled ?? false;
    return _PanelRows(
      children: [
        _SquareSwitchListTile(
          key: const Key('background-listening-switch'),
          title: const LText('Background listening'),
          subtitle: const LText(
            'Receive messages while the app is closed. Android requires an '
            'ongoing notification while this is enabled, and notification '
            'permission lets ntfy alert you about new messages. If permission '
            'is denied, listening and in-app history continue and Android '
            'shows the service in Task Manager.',
          ),
          value: enabled,
          onChanged: _settings == null || _saving ? null : _setEnabled,
        ),
        ListTile(
          key: const Key('background-channel-settings'),
          title: const LText('Foreground listener notification settings'),
          subtitle: const LText(
            'Control the required ongoing notification in Android.',
          ),
          onTap: _openChannelSettings,
        ),
      ],
    );
  }
}

class _AppSettingsPanel extends StatefulWidget {
  const _AppSettingsPanel({
    required this.repository,
    this.database,
    this.onChanged,
  });

  final AppSettingsRepository repository;
  final SubscriptionStore? database;
  final Future<void> Function()? onChanged;

  @override
  State<_AppSettingsPanel> createState() => _AppSettingsPanelState();
}

class _AppSettingsPanelState extends State<_AppSettingsPanel> {
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await widget.repository.loadSettings();
    if (mounted) setState(() => _settings = settings);
  }

  Future<void> _save(AppSettings settings) async {
    await widget.repository.saveSettings(settings);
    await _load();
    await widget.onChanged?.call();
  }

  Future<void> _editServer() async {
    final settings = _settings;
    if (settings == null) return;
    final controller = TextEditingController(text: settings.defaultServer);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Default server'),
        content: TextField(
          key: const Key('default-server-field'),
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: tr(context, 'https://ntfy.sh'),
            helperText: tr(context, 'Used when subscribing to a new topic.'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const LText('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      final candidate = AppSettings.fromJson({
        ...settings.toJson(),
        'defaultServer': value.trim(),
      });
      await _save(candidate);
    } on FormatException catch (error) {
      _error(error.message);
    }
  }

  Future<T?> _choose<T>(String title, List<(String, T)> values) =>
      showDialog<T>(
        context: context,
        builder: (context) => SimpleDialog(
          title: LText(title),
          children: [
            for (final value in values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, value.$2),
                child: LText(value.$1),
              ),
          ],
        ),
      );

  Future<void> _backup() async {
    final database = widget.database;
    if (database == null) return;
    final dialogTitle = tr(context, 'Back up ntfy');
    final settings = _settings!;
    final mode = await _choose('Back up to file', const [
      ('Everything', BackupMode.everything),
      ('Everything, except users', BackupMode.everythingNoUsers),
      ('Settings only', BackupMode.settingsOnly),
    ]);
    if (mode == null) return;
    final updated = settings.copyWith(backupMode: mode);
    await widget.repository.saveSettings(updated);
    final certificates = widget.repository is CertificateBackupRepository
        ? await (widget.repository as CertificateBackupRepository)
              .exportCertificateBackup(
                includePrivateKeys: mode == BackupMode.everything,
              )
        : const <Map<String, Object?>>[];
    final backup = {
      ...await database.exportBackup(
        includeSubscriptions: mode != BackupMode.settingsOnly,
      ),
      'app': updated.toJson(),
      'certificates': certificates,
      if (mode == BackupMode.everything)
        'users': [
          for (final account in await widget.repository.loadAccounts())
            {
              'baseUrl': account.baseUrl,
              'username': account.username,
              'password': account.password,
            },
        ],
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(backup)));
    await FilePicker.saveFile(
      fileName: 'ntfy-backup.json',
      bytes: bytes,
      mimeType: 'application/json',
      dialogTitle: dialogTitle,
    );
  }

  Future<void> _restore() async {
    final database = widget.database;
    if (database == null) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final file = files.singleOrNull;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('Invalid backup.');
      final app = AppSettings.fromJson(decoded['app']);
      final users = <ServerAccount>[];
      final userValues = decoded['users'];
      if (userValues != null && userValues is! List) {
        throw const FormatException('Invalid users in backup.');
      }
      for (final value in userValues as List? ?? const []) {
        if (value is! Map ||
            value['baseUrl'] is! String ||
            value['username'] is! String ||
            value['password'] is! String) {
          throw const FormatException('Invalid user in backup.');
        }
        users.add(
          ServerAccount(
            baseUrl: value['baseUrl']! as String,
            username: value['username']! as String,
            password: value['password']! as String,
          ),
        );
      }
      await database.restoreBackup(decoded);
      await widget.repository.saveSettings(app);
      for (final user in users) {
        await widget.repository.saveAccount(user);
      }
      if (widget.repository case final CertificateBackupRepository backup) {
        await backup.restoreCertificateBackup(decoded['certificates']);
      }
      await _load();
      await widget.onChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: LText('Backup restored.')));
      }
    } on Object catch (error) {
      _error('Could not restore backup: $error');
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: LText(message)));
    }
  }

  Future<void> _exportLogs() async {
    final action = await _choose('Export logs', const [
      ('Copy original', ('copy', false)),
      ('Copy scrubbed', ('copy', true)),
      ('Share original', ('share', false)),
      ('Share scrubbed', ('share', true)),
    ]);
    if (action == null) return;
    var text = (await widget.repository.loadLogs()).join('\n');
    if (action.$2) {
      for (final account in await widget.repository.loadAccounts()) {
        for (final secret in [
          account.baseUrl,
          account.username,
          account.password,
        ]) {
          if (secret.isNotEmpty) text = text.replaceAll(secret, '<redacted>');
        }
      }
    }
    if (action.$1 == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
    } else {
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) return const LinearProgressIndicator();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('General'),
        _SettingsPanel(
          children: [
            ListTile(
              key: const Key('default-server'),
              title: const LText('Default server'),
              subtitle: LText(settings.defaultServer),
              onTap: _editServer,
            ),
            ListTile(
              key: const Key('users-settings'),
              title: const LText('Manage users'),
              subtitle: const LText('Add/remove users for protected topics'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _AccountsScreen(repository: widget.repository),
                ),
              ),
            ),
            ListTile(
              key: const Key('language-setting'),
              title: const LText('Language'),
              subtitle: LText(
                settings.languageTag == 'system'
                    ? 'Using system default'
                    : supportedAppLanguages
                              .where((item) => item.$1 == settings.languageTag)
                              .map((item) => item.$2)
                              .firstOrNull ??
                          settings.languageTag,
              ),
              onTap: () async {
                final value = await _choose('Language', [
                  const ('System default', 'system'),
                  for (final language in supportedAppLanguages)
                    (language.$2, language.$1),
                ]);
                if (value != null) {
                  await _save(settings.copyWith(languageTag: value));
                }
              },
            ),
          ],
        ),
        const _SectionHeader('Appearance'),
        _SettingsPanel(
          children: [
            ListTile(
              key: const Key('theme-setting'),
              title: const LText('Dark mode'),
              subtitle: LText(switch (settings.theme) {
                AppThemePreference.system => 'Follow system',
                AppThemePreference.light => 'Off',
                AppThemePreference.dark => 'On',
              }),
              onTap: () async {
                final value = await _choose('Dark mode', const [
                  ('Follow system', AppThemePreference.system),
                  ('On', AppThemePreference.dark),
                  ('Off', AppThemePreference.light),
                ]);
                if (value != null) await _save(settings.copyWith(theme: value));
              },
            ),
            _SquareSwitchListTile(
              key: const Key('dynamic-colors-setting'),
              title: const LText('Dynamic colors'),
              subtitle: const LText(
                'Use colors from the Android system theme.',
              ),
              value: settings.dynamicColors,
              onChanged: (value) =>
                  _save(settings.copyWith(dynamicColors: value)),
            ),
            _SquareSwitchListTile(
              key: const Key('message-bar-setting'),
              title: const LText('Show message bar'),
              subtitle: const LText(
                'Show the quick publish bar in topic views.',
              ),
              value: settings.messageBar == MessageBarPreference.enabled,
              onChanged: (value) => _save(
                settings.copyWith(
                  messageBar: value
                      ? MessageBarPreference.enabled
                      : MessageBarPreference.disabled,
                ),
              ),
            ),
            _SquareSwitchListTile(
              key: const Key('new-messages-at-bottom-setting'),
              title: const LText('New messages at bottom'),
              subtitle: const LText(
                'Show older notifications first and append new ones below.',
              ),
              value: settings.newMessagesAtBottom,
              onChanged: (value) =>
                  _save(settings.copyWith(newMessagesAtBottom: value)),
            ),
          ],
        ),
        const _SectionHeader('Backup & Restore'),
        _SettingsPanel(
          children: [
            ListTile(
              key: const Key('backup-setting'),
              title: const LText('Back up to file'),
              subtitle: const LText('Export config, notifications, and users'),
              onTap: _backup,
            ),
            ListTile(
              key: const Key('restore-setting'),
              title: const LText('Restore from file'),
              subtitle: const LText('Import config, notifications and users'),
              onTap: _restore,
            ),
          ],
        ),
        const _SectionHeader('Advanced'),
        _SettingsPanel(
          children: [
            ListTile(
              key: const Key('disconnected-alerts-setting'),
              title: const LText('Alert when disconnected'),
              subtitle: LText(
                _connectionAlertSummary(settings.connectionAlertSeconds),
              ),
              onTap: () async {
                final value = await _choose('Connection alert', const [
                  ('Never', 0),
                  ('After 5 minutes', 300),
                  ('After 15 minutes', 900),
                  ('After 1 hour', 3600),
                  ('After 3 hours', 10800),
                  ('After 12 hours', 43200),
                ]);
                if (value != null) {
                  await _save(settings.copyWith(connectionAlertSeconds: value));
                }
              },
            ),
            ListTile(
              key: const Key('protocol-setting'),
              title: const LText('Connection protocol'),
              subtitle: LText(
                settings.protocol == ConnectionProtocol.http
                    ? 'HTTP stream'
                    : 'WebSocket',
              ),
              onTap: () async {
                final value = await _choose('Connection protocol', const [
                  ('HTTP stream', ConnectionProtocol.http),
                  ('WebSocket', ConnectionProtocol.websocket),
                ]);
                if (value != null) {
                  await _save(settings.copyWith(protocol: value));
                }
              },
            ),
            ListTile(
              key: const Key('custom-headers-setting'),
              title: const LText('Custom headers'),
              subtitle: const LText('Send additional headers to a server.'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _HeadersScreen(repository: widget.repository),
                ),
              ),
            ),
            ListTile(
              key: const Key('certificates-setting'),
              title: const LText('Manage certificates'),
              subtitle: const LText(
                'Add certificates to the trust store and manage client certificates for mTLS',
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _CertificatesScreen(repository: widget.repository),
                ),
              ),
            ),
            _SquareSwitchListTile(
              key: const Key('broadcasts-setting'),
              title: const LText('Broadcast messages'),
              subtitle: const LText(
                'Apps can receive incoming notifications as broadcasts',
              ),
              value: settings.broadcastsEnabled,
              onChanged: (value) =>
                  _save(settings.copyWith(broadcastsEnabled: value)),
            ),
            _SquareSwitchListTile(
              key: const Key('unified-push-setting'),
              title: const LText('Enable UnifiedPush'),
              subtitle: const LText(
                'ntfy will act as a UnifiedPush distributor',
              ),
              value: settings.unifiedPushEnabled,
              onChanged: (value) async {
                try {
                  await const AndroidSettingsPlatform().setUnifiedPushEnabled(
                    value,
                  );
                  await _save(settings.copyWith(unifiedPushEnabled: value));
                } on PlatformException catch (error) {
                  _error('Could not update UnifiedPush: ${error.message}');
                }
              },
            ),
            _SquareSwitchListTile(
              key: const Key('logging-setting'),
              title: const LText('Record logs'),
              subtitle: LText(
                settings.recordLogs
                    ? 'Logging (up to 1,000 entries) to device …'
                    : 'Turn on logging, so you can share logs later to diagnose issues.',
              ),
              value: settings.recordLogs,
              onChanged: (value) => _save(settings.copyWith(recordLogs: value)),
            ),
            if (settings.recordLogs) ...[
              ListTile(
                key: const Key('export-logs-setting'),
                title: const LText('Export logs'),
                subtitle: const LText(
                  'Copy or share original or scrubbed logs',
                ),
                onTap: _exportLogs,
              ),
              ListTile(
                key: const Key('clear-logs-setting'),
                title: const LText('Clear logs'),
                subtitle: const LText('Delete all recorded log entries'),
                onTap: () async {
                  await widget.repository.clearLogs();
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(content: LText('Logs deleted.')),
                  );
                },
              ),
            ],
          ],
        ),
        const _SectionHeader('About'),
        _SettingsPanel(
          children: [
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) => ListTile(
                key: const Key('about-setting'),
                title: const LText('Version'),
                subtitle: LText(
                  snapshot.hasData
                      ? 'ntfy ${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                      : 'Version information',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AccountsScreen extends StatefulWidget {
  const _AccountsScreen({required this.repository});

  final AppSettingsRepository repository;

  @override
  State<_AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<_AccountsScreen> {
  List<ServerAccount>? _accounts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await widget.repository.loadAccounts();
    if (mounted) setState(() => _accounts = accounts);
  }

  Future<void> _add() async {
    final server = TextEditingController(text: 'https://ntfy.sh');
    final username = TextEditingController();
    final password = TextEditingController();
    final account = await showDialog<ServerAccount>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Add user'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: server,
              decoration: InputDecoration(labelText: tr(context, 'Server URL')),
            ),
            TextField(
              controller: username,
              decoration: InputDecoration(labelText: tr(context, 'Username')),
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(labelText: tr(context, 'Password')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              ServerAccount(
                baseUrl: server.text,
                username: username.text,
                password: password.text,
              ),
            ),
            child: const LText('Save'),
          ),
        ],
      ),
    );
    if (account == null) return;
    await widget.repository.saveAccount(account);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton(
      onPressed: _add,
      child: const Icon(Icons.add),
    ),
    body: CollapsibleDesignBody(
      title: const LText('Users'),
      child: _accounts == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                for (final account in _accounts!)
                  ListTile(
                    title: LText(account.username),
                    subtitle: LText(account.baseUrl),
                    trailing: IconButton(
                      tooltip: tr(context, 'Delete user'),
                      onPressed: () async {
                        await widget.repository.deleteAccount(account.baseUrl);
                        await _load();
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class _HeadersScreen extends StatefulWidget {
  const _HeadersScreen({required this.repository});
  final AppSettingsRepository repository;

  @override
  State<_HeadersScreen> createState() => _HeadersScreenState();
}

class _HeadersScreenState extends State<_HeadersScreen> {
  List<CustomHeader>? _headers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final headers = await widget.repository.loadHeaders();
    if (mounted) setState(() => _headers = headers);
  }

  Future<void> _add() async {
    final server = TextEditingController(text: 'https://ntfy.sh');
    final name = TextEditingController();
    final value = TextEditingController();
    final header = await showDialog<CustomHeader>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Add custom header'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: server,
              decoration: InputDecoration(labelText: tr(context, 'Server URL')),
            ),
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: tr(context, 'Header name'),
              ),
            ),
            TextField(
              controller: value,
              decoration: InputDecoration(
                labelText: tr(context, 'Header value'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              CustomHeader(
                baseUrl: server.text,
                name: name.text,
                value: value.text,
              ),
            ),
            child: const LText('Save'),
          ),
        ],
      ),
    );
    if (header == null) return;
    try {
      await widget.repository.saveHeader(header);
      await _load();
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: LText(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton(
      onPressed: _add,
      child: const Icon(Icons.add),
    ),
    body: CollapsibleDesignBody(
      title: const LText('Custom headers'),
      child: _headers == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                for (final header in _headers!)
                  ListTile(
                    title: LText(header.name),
                    subtitle: LText(header.baseUrl),
                    trailing: IconButton(
                      tooltip: tr(context, 'Delete header'),
                      onPressed: () async {
                        await widget.repository.deleteHeader(
                          header.baseUrl,
                          header.name,
                        );
                        await _load();
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class _CertificatesScreen extends StatefulWidget {
  const _CertificatesScreen({required this.repository});
  final AppSettingsRepository repository;

  @override
  State<_CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<_CertificatesScreen> {
  List<CertificateProfile>? _profiles;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profiles = await widget.repository.loadCertificates();
    if (mounted) setState(() => _profiles = profiles);
  }

  Future<void> _addTrusted() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pem', 'crt', 'cer'],
    );
    final file = files.singleOrNull;
    if (file == null || !mounted) return;
    final server = TextEditingController(text: 'https://ntfy.sh');
    final baseUrl = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Trust certificate for server'),
        content: TextField(
          controller: server,
          decoration: InputDecoration(labelText: tr(context, 'Server URL')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, server.text),
            child: const LText('Trust'),
          ),
        ],
      ),
    );
    if (baseUrl == null) return;
    const managedFiles = ManagedCertificateFiles();
    final path = await managedFiles.save(
      bytes: await file.readAsBytes(),
      fileName: file.name,
      label: 'trusted-$baseUrl',
    );
    try {
      final normalized = normalizeServerOrigin(baseUrl);
      final existing = _profiles
          ?.where((profile) => profile.baseUrl == normalized)
          .firstOrNull;
      await widget.repository.saveCertificates(
        CertificateProfile(
          baseUrl: normalized,
          trustedCertificatePath: path,
          clientCertificatePath: existing?.clientCertificatePath,
          clientKeyPath: existing?.clientKeyPath,
          clientKeyPassword: existing?.clientKeyPassword,
        ),
      );
      await _load();
    } catch (error) {
      await managedFiles.delete([path]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LText('Could not load certificate: $error')),
        );
      }
    }
  }

  Future<void> _addClient() async {
    final certificateFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pem', 'crt'],
    );
    final certificate = certificateFiles.singleOrNull;
    if (certificate == null) return;
    final keyFiles = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pem', 'key'],
    );
    final key = keyFiles.singleOrNull;
    if (key == null || !mounted) return;
    final server = TextEditingController(text: 'https://ntfy.sh');
    final password = TextEditingController();
    final value = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const LText('Add client certificate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: server,
              decoration: InputDecoration(labelText: tr(context, 'Server URL')),
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: tr(context, 'Private key password (optional)'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, (server.text, password.text)),
            child: const LText('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    final files = const ManagedCertificateFiles();
    final certificatePath = await files.save(
      bytes: await certificate.readAsBytes(),
      fileName: certificate.name,
      label: 'client-cert-${value.$1}',
    );
    final keyPath = await files.save(
      bytes: await key.readAsBytes(),
      fileName: key.name,
      label: 'client-key-${value.$1}',
    );
    try {
      final normalized = normalizeServerOrigin(value.$1);
      final existing = _profiles
          ?.where((profile) => profile.baseUrl == normalized)
          .firstOrNull;
      await widget.repository.saveCertificates(
        CertificateProfile(
          baseUrl: normalized,
          trustedCertificatePath: existing?.trustedCertificatePath,
          clientCertificatePath: certificatePath,
          clientKeyPath: keyPath,
          clientKeyPassword: value.$2.isEmpty ? null : value.$2,
        ),
      );
      await _load();
    } catch (error) {
      await files.delete([certificatePath, keyPath]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: LText('Could not load client certificate: $error')),
        );
      }
    }
  }

  Future<void> _add() async {
    final type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const LText('Add certificate'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'trusted'),
            child: const LText('Trusted server certificate'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'client'),
            child: const LText('Client certificate'),
          ),
        ],
      ),
    );
    if (type == 'trusted') await _addTrusted();
    if (type == 'client') await _addClient();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton(
      onPressed: _add,
      child: const Icon(Icons.add),
    ),
    body: CollapsibleDesignBody(
      title: const LText('Certificates'),
      child: _profiles == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                const ListTile(
                  title: LText('Trusted and client certificates'),
                  subtitle: LText(
                    'Certificate files are applied only to their matching server.',
                  ),
                ),
                for (final profile in _profiles!)
                  ListTile(
                    title: LText(profile.baseUrl),
                    subtitle: LText(
                      profile.trustedCertificatePath ?? 'Client certificate',
                    ),
                    trailing: IconButton(
                      tooltip: tr(context, 'Delete certificate'),
                      onPressed: () async {
                        await widget.repository.deleteCertificates(
                          profile.baseUrl,
                        );
                        await _load();
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(
      tr(context, label).toUpperCase(),
      style: monoLabel.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// Rows of a settings group, separated by the design's hairline rules.
class _PanelRows extends StatelessWidget {
  const _PanelRows({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < children.length; index++) ...[
        if (index > 0) const Divider(height: 1),
        children[index],
      ],
    ],
  );
}

/// Hairline-outlined surface grouping the rows that follow a section heading.
class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: scheme.shadow, offset: hardShadowOffset),
          ],
        ),
        child: Material(
          color: scheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: scheme.onSurface),
          ),
          child: _PanelRows(children: children),
        ),
      ),
    );
  }
}

class _SquareSwitchListTile extends SwitchListTile {
  const _SquareSwitchListTile({
    required super.title,
    required super.value,
    required super.onChanged,
    super.subtitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    title: title,
    subtitle: subtitle,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    trailing: Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: _SquareSwitch(value: value, enabled: onChanged != null),
    ),
  );
}

class _SquareSwitch extends StatelessWidget {
  const _SquareSwitch({required this.value, required this.enabled});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = enabled ? 1.0 : 0.45;
    return Opacity(
      opacity: active,
      child: Container(
        width: 40,
        height: 22,
        decoration: BoxDecoration(
          color: value ? scheme.primary : scheme.outlineVariant,
          border: Border.all(color: value ? scheme.primary : scheme.outline),
        ),
        child: AnimatedAlign(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : designMotionDuration,
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: value ? scheme.onPrimary : scheme.surfaceContainerLowest,
              border: Border.all(color: scheme.outline),
            ),
          ),
        ),
      ),
    );
  }
}

class _RetentionChoice {
  const _RetentionChoice(this.label, this.period);

  final String label;
  final RetentionPeriod? period;
}
