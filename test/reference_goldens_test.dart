import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/app_settings.dart';
import 'package:ntfy_flutter/background_listening.dart';
import 'package:ntfy_flutter/design.dart';
import 'package:ntfy_flutter/main.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/notification_policy.dart';
import 'package:ntfy_flutter/notifications.dart';
import 'package:ntfy_flutter/retention.dart';
import 'package:ntfy_flutter/retention_settings.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:ntfy_flutter/topic_feed.dart';
import 'package:ntfy_flutter/topic_feed_screen.dart';

void main() {
  testWidgets('all design reference states have readable goldens', (
    tester,
  ) async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf')))
        .load()
        .timeout(const Duration(seconds: 5));
    await (FontLoader('HankenGrotesk')
          ..addFont(rootBundle.load('assets/fonts/HankenGrotesk-SemiBold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/HankenGrotesk-Bold.ttf')))
        .load()
        .timeout(const Duration(seconds: 5));
    await (FontLoader('JetBrainsMono')
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/JetBrainsMono-SemiBold.ttf')))
        .load()
        .timeout(const Duration(seconds: 5));
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final iconFont = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    ).readAsBytesSync();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconFont)));
    await iconLoader.load().timeout(const Duration(seconds: 5));
    final store = _GoldenRepository();
    final subscription = await store.add(
      url: 'https://ntfy.sh/rahul',
      displayName: 'Rahul',
    );
    final settings = AppSettingsStore(
      preferences: _MemoryPreferences(),
      secrets: _MemorySecrets(),
    );
    final background = BackgroundListeningSession(store, _BackgroundHost());
    final notifications = MessageNotificationSession(
      _NotificationPlatform(),
      policies: store,
    );
    final observer = RouteObserver<PageRoute<dynamic>>();

    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> pump(
      Widget home, {
      double bottomInset = 0,
      bool asRoute = false,
    }) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: designTheme(brightness: Brightness.light),
          navigatorObservers: [observer],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(viewInsets: EdgeInsets.only(bottom: bottomInset)),
            child: child!,
          ),
          home: asRoute
              ? Builder(
                  builder: (context) => TextButton(
                    key: const Key('open-reference-route'),
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => home),
                    ),
                    child: const Text('Open'),
                  ),
                )
              : home,
        ),
      );
      if (asRoute) {
        await tester.tap(find.byKey(const Key('open-reference-route')));
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    Future<void> pumpTransition() async {
      await tester.pumpAndSettle();
    }

    TopicFeedScreen topic() => TopicFeedScreen(
      subscription: subscription,
      feed: TopicFeedSession(
        controller: TopicFeedController(
          repository: store,
          subscription: subscription,
          client: _SilentClient(),
        ),
      ),
      retention: RetentionSession(store),
      notifications: notifications,
      routeObserver: observer,
      onRename: (name) => store.rename(subscription.id, name),
      onBackgroundEnabled: (enabled) =>
          store.setTopicBackgroundEnabled(subscription.id, enabled),
      onUnsubscribe: () => store.remove(subscription.id),
    );

    await pump(
      SubscriptionsScreen(
        store: store,
        feedFactory: (_) => TopicFeedSession(
          controller: TopicFeedController(
            repository: store,
            subscription: subscription,
            client: _SilentClient(),
          ),
        ),
        retention: RetentionSession(store),
        backgroundListening: background,
        notifications: notifications,
        routeObserver: observer,
      ),
    );
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_home.png'),
    );

    await tester.tap(find.byTooltip('Show menu'));
    await pumpTransition();
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_home_options.png'),
    );

    await pump(
      SubscriptionsScreen(
        store: store,
        feedFactory: (_) => TopicFeedSession(
          controller: TopicFeedController(
            repository: store,
            subscription: subscription,
            client: _SilentClient(),
          ),
        ),
        retention: RetentionSession(store),
        backgroundListening: background,
        notifications: notifications,
        routeObserver: observer,
      ),
    );
    await tester.tap(find.byTooltip('Add subscription'));
    await pumpTransition();
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_subscribe.png'),
    );

    await pump(topic());
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_topic.png'),
    );

    await tester.tap(find.byTooltip('Show menu'));
    await pumpTransition();
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_topic_options.png'),
    );

    await pump(
      TopicSettingsScreen(
        subscription: subscription,
        retention: RetentionSession(store),
        policies: store,
        onRename: (name) => store.rename(subscription.id, name),
        onBackgroundEnabled: (enabled) =>
            store.setTopicBackgroundEnabled(subscription.id, enabled),
      ),
      asRoute: true,
    );
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_topic_settings.png'),
    );

    await pump(topic());
    await tester.tap(find.byKey(const Key('topic-notification-state')));
    await pumpTransition();
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_topic_snooze.png'),
    );

    await pump(topic(), bottomInset: 300);
    await tester.tap(find.byKey(const Key('topic-search-action')));
    await pumpTransition();
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_topic_search_inset.png'),
    );

    await pump(topic(), bottomInset: 300);
    await tester.tap(find.byKey(const Key('expand-composer')));
    await pumpTransition();
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_attachment_composer.png'),
    );

    tester.view.physicalSize = const Size(412, 2200);
    await pump(
      SettingsScreen(
        retention: RetentionSession(store),
        backgroundListening: background,
        policies: store,
        settings: settings,
      ),
      asRoute: true,
    );
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_app_settings.png'),
    );

    tester.view.physicalSize = const Size(412, 915);
    store.messages = [
      StoredMessage(
        localId: 3,
        subscriptionId: subscription.id,
        eventId: 'build-ready',
        time: DateTime(2026, 8, 19, 18, 13),
        title: 'ntfy Flutter build ready',
        message: 'ntfy Flutter: Topic URL tap now copies the URL; high-refresh Android mode request added. 140 tests pass, analyze clean, release APK built and installed on Genymotion.',
        tags: const ['white_check_mark'],
      ),
      StoredMessage(
        localId: 2,
        subscriptionId: subscription.id,
        eventId: 'tickets-ready',
        time: DateTime(2026, 8, 19, 18),
        title: 'ntfy tickets restructured and icon ready',
        message: 'Ticket restructuring complete: only #19 and #20 remain open.',
        tags: const ['white_check_mark', 'art'],
      ),
      StoredMessage(
        localId: 1,
        subscriptionId: subscription.id,
        eventId: 'release-ready',
        time: DateTime(2026, 8, 19, 17, 24),
        title: 'ntfy Flutter release build ready',
        message: 'ntfy Flutter fixes complete. Local signed release APK ready.',
        tags: const ['white_check_mark', 'package'],
      ),
    ];
    await pump(topic(), asRoute: true);
    await expectLater(
      find.byType(Overlay),
      matchesGoldenFile('goldens/reference_topic_with_data.png'),
    );
  }, tags: 'golden');
}

class _SilentClient implements NtfyStreamClient {
  final _lines = StreamController<String>();

  @override
  Future<FeedConnection> connect({
    required String topicUrl,
    String? cursor,
  }) async => FeedConnection(
    lines: _lines.stream,
    onClose: () async {
      if (!_lines.isClosed) await _lines.close();
    },
  );
}

class _BackgroundHost implements BackgroundListeningHost {
  @override
  Future<void> openChannelSettings() async {}

  @override
  Future<void> requestNotificationPermission() async {}

  @override
  Future<void> startOrRefresh() async {}

  @override
  Future<BackgroundListeningHostStatus> status() async =>
      const BackgroundListeningHostStatus(
        running: false,
        notificationPresent: false,
      );

  @override
  Future<void> stop() async {}
}

class _NotificationPlatform implements NotificationPlatform {
  @override
  Future<void> close() async {}

  @override
  Future<bool> isSubscriptionVisible(int subscriptionId) async => false;

  @override
  Future<void> setVisibleSubscription(int? subscriptionId) async {}

  @override
  Future<bool> show(MessageNotification notification) async => true;

  @override
  Future<void> start() async {}

  @override
  Stream<NotificationTarget> get taps => const Stream.empty();
}

class _GoldenRepository
    implements
        AppRepository,
        NotificationPolicyRepository,
        TopicNotificationPolicyRepository,
        TopicDeliveryRepository {
  final _subscriptions = <Subscription>[];
  List<StoredMessage> messages = [];
  NotificationPolicy policy = const NotificationPolicy();
  TopicNotificationPolicyOverrides overrides =
      const TopicNotificationPolicyOverrides();
  RetentionPeriod retention = RetentionPeriod.never;
  bool backgroundListening = false;

  @override
  Future<Subscription> add({required String url, String? displayName}) async {
    final subscription = Subscription(
      id: _subscriptions.length + 1,
      url: SubscriptionStore.normalizeUrl(url),
      displayName: displayName,
    );
    _subscriptions.add(subscription);
    return subscription;
  }

  @override
  Future<List<Subscription>> all() async => List.unmodifiable(_subscriptions);

  @override
  Future<void> markRead(int subscriptionId) async {}

  @override
  Future<Subscription> rename(int subscriptionId, String? displayName) async {
    final index = _subscriptions.indexWhere(
      (item) => item.id == subscriptionId,
    );
    final current = _subscriptions[index];
    final renamed = Subscription(
      id: current.id,
      url: current.url,
      displayName: displayName,
      backgroundEnabled: current.backgroundEnabled,
    );
    _subscriptions[index] = renamed;
    return renamed;
  }

  @override
  Future<void> remove(int subscriptionId) async =>
      _subscriptions.removeWhere((item) => item.id == subscriptionId);

  @override
  Future<FeedSnapshot> loadFeed(int subscriptionId) async =>
      FeedSnapshot(messages: messages);

  @override
  Future<StoredMessage?> ingest(
    int subscriptionId,
    IncomingMessage message,
  ) async => null;

  @override
  Future<void> deleteMessage(int subscriptionId, int localId) async {}

  @override
  Future<void> restoreMessage(
    int subscriptionId,
    StoredMessage message,
  ) async {}

  @override
  Future<void> clearMessages(int subscriptionId) async {}

  @override
  Future<bool> loadBackgroundListening() async => backgroundListening;

  @override
  Future<void> setBackgroundListening(bool enabled) async {
    backgroundListening = enabled;
  }

  @override
  Future<RetentionSettings> loadRetention({int? subscriptionId}) async =>
      RetentionSettings(global: retention);

  @override
  Future<void> executeRetention(RetentionCommand command) async {
    if (command case SetGlobalRetention(:final period)) retention = period;
  }

  @override
  Future<NotificationPolicy> loadNotificationPolicy({
    int? subscriptionId,
  }) async => policy;

  @override
  Future<void> setGlobalNotificationPolicy(NotificationPolicy value) async {
    policy = value;
  }

  @override
  Future<void> setTopicNotificationPolicy(
    int subscriptionId,
    NotificationPolicy? value,
  ) async {
    if (value != null) policy = value;
  }

  @override
  Future<TopicNotificationPolicyOverrides> loadTopicNotificationPolicyOverrides(
    int subscriptionId,
  ) async => overrides;

  @override
  Future<void> setTopicNotificationPolicyOverrides(
    int subscriptionId,
    TopicNotificationPolicyOverrides value,
  ) async {
    overrides = value;
  }

  @override
  Future<Subscription> setTopicBackgroundEnabled(
    int subscriptionId,
    bool enabled,
  ) async {
    final index = _subscriptions.indexWhere(
      (item) => item.id == subscriptionId,
    );
    final current = _subscriptions[index];
    final updated = Subscription(
      id: current.id,
      url: current.url,
      displayName: current.displayName,
      backgroundEnabled: enabled,
    );
    _subscriptions[index] = updated;
    return updated;
  }
}

class _MemoryPreferences implements PreferencesBackend {
  final values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }
}

class _MemorySecrets implements SecretBackend {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
