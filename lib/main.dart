import 'package:flutter/material.dart';

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

void main() => runApp(const NtfyApp());

class NtfyApp extends StatelessWidget {
  const NtfyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ntfy',
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: ThemeMode.system,
      home: const SubscriptionsScreen(),
    );
  }
}

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 24),
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
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Add subscription',
        child: FloatingActionButton(
          onPressed: () => _showSubscribeDialog(context),
          tooltip: 'Add subscription',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showSubscribeDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Subscribe to topic'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter a topic URL to start receiving notifications.'),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'Topic URL',
                hintText: 'https://ntfy.sh/mytopic',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const TextButton(onPressed: null, child: Text('Subscribe')),
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
