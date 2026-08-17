import 'package:flutter/material.dart';

import 'retention.dart';
import 'subscriptions.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.retention, super.key});

  final RetentionSession retention;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: _RetentionSettings(retention: retention),
  );
}

class TopicSettingsScreen extends StatelessWidget {
  const TopicSettingsScreen({
    required this.subscription,
    required this.retention,
    super.key,
  });

  final Subscription subscription;
  final RetentionSession retention;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        subscription.displayName ??
            Uri.parse(subscription.url).pathSegments.last,
      ),
    ),
    body: ListView(
      children: [
        _RetentionSettings(
          retention: retention,
          subscriptionId: subscription.id,
        ),
        const Divider(height: 1),
        const _SectionHeader('About'),
        ListTile(
          title: const Text('Topic URL'),
          subtitle: Text(subscription.url),
        ),
      ],
    ),
  );
}

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
        title: const Text('Delete notifications'),
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
                    Expanded(child: Text(choice.label)),
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
            content: Text('Could not update notification retention.'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Notifications'),
        if (settings == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ListTile(
            title: const Text('Delete notifications'),
            subtitle: Text(
              widget.subscriptionId == null
                  ? settings.global.summary
                  : settings.summary,
            ),
            onTap: _select,
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _RetentionChoice {
  const _RetentionChoice(this.label, this.period);

  final String label;
  final RetentionPeriod? period;
}
