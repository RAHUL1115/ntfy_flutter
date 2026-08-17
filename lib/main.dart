import 'package:flutter/material.dart';

import 'publish.dart';
import 'subscriptions.dart';
import 'topic_feed.dart';
import 'topic_feed_screen.dart';

final _darkTheme = ThemeData(
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

final _lightTheme = ThemeData(
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
    backgroundColor: Color(0xff338574),
    foregroundColor: Colors.white,
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: Color(0xff338574),
    foregroundColor: Colors.white,
  ),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await SubscriptionStore.open();
  runApp(NtfyApp(store: store));
}

class NtfyApp extends StatelessWidget {
  NtfyApp({
    required this.store,
    TopicFeedFactory? feedFactory,
    NtfyPublisher? publisher,
    super.key,
  }) : feedFactory =
           feedFactory ??
           ((subscription) => TopicFeedSession(
             controller: TopicFeedController(
               repository: store,
               subscription: subscription,
               client: HttpNtfyStreamClient(),
             ),
             publisher: publisher,
           ));

  final AppRepository store;
  final TopicFeedFactory feedFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ntfy',
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: ThemeMode.system,
      home: SubscriptionsScreen(store: store, feedFactory: feedFactory),
    );
  }
}

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({
    required this.store,
    required this.feedFactory,
    super.key,
  });

  final AppRepository store;
  final TopicFeedFactory feedFactory;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  List<Subscription>? _subscriptions;

  @override
  void initState() {
    super.initState();
    _loadSubscriptions();
  }

  Future<void> _loadSubscriptions() async {
    final subscriptions = await widget.store.all();
    if (mounted) setState(() => _subscriptions = subscriptions);
  }

  Future<void> _showSubscribeDialog() async {
    final saved = await showDialog<Subscription>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SubscribeDialog(store: widget.store),
    );
    if (saved != null) await _loadSubscriptions();
  }

  Future<void> _openSubscription(Subscription subscription) async {
    final feed = widget.feedFactory(subscription);
    final removed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TopicFeedScreen(
          subscription: subscription,
          feed: feed,
          onUnsubscribe: () => widget.store.remove(subscription.id),
        ),
      ),
    );
    if (removed == true) await _loadSubscriptions();
  }

  Future<bool> _confirmRemove(Subscription subscription) async {
    final name = subscription.displayName ?? subscription.url;
    return await showDialog<bool>(
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
    } catch (_) {
      await _loadSubscriptions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove the subscription. Try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscribed topics'),
        actions: [
          PopupMenuButton<void>(
            itemBuilder: (_) => [
              PopupMenuItem<void>(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
                child: const Text('Settings'),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: Semantics(
        button: true,
        label: 'Add subscription',
        child: FloatingActionButton(
          onPressed: _showSubscribeDialog,
          tooltip: 'Add subscription',
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
      return ListView.separated(
        itemCount: subscriptions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, index) {
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
              leading: const Icon(Icons.sms_outlined, size: 36),
              title: Text(subscription.displayName ?? subscription.url),
              subtitle: subscription.displayName == null
                  ? null
                  : Text(subscription.url),
              onTap: () => _openSubscription(subscription),
            ),
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
            const Icon(Icons.sms_outlined, size: 48, color: Color(0xff888888)),
            const SizedBox(height: 20),
            Text(
              "It looks like you don't have any subscriptions yet.",
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Click the + to create or subscribe to a topic. Afterwards you receive notifications on your device when sending messages via PUT or POST.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 7),
            const Text(
              'Detailed instructions available on ntfy.sh, and in the docs.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
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
  const _SubscribeDialog({required this.store});

  final SubscriptionRepository store;

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
      final subscription = await widget.store.add(
        url: _urlController.text,
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
      child: AlertDialog(
        title: const Text('Subscribe to topic'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter a topic URL to start receiving notifications.'),
              const SizedBox(height: 16),
              TextField(
                key: const Key('topic-url-field'),
                controller: _urlController,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Topic URL',
                  hintText: 'https://ntfy.sh/mytopic',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('display-name-field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Display name (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _saving || _urlController.text.trim().isEmpty
                ? null
                : _save,
            child: const Text('Subscribe'),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Settings')));
  }
}
