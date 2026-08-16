// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import 'app_database.dart';
import 'delivery_service.dart';
import 'models.dart';
import 'notification_service.dart';
import 'ntfy_client.dart';

class AppController extends ChangeNotifier {
  AppController({
    required AppDatabase database,
    required NtfyClient client,
    required CredentialStore credentialStore,
    required NotificationService notificationService,
    required DeliveryService deliveryService,
  }) : _database = database,
       _client = client,
       _credentialStore = credentialStore,
       _notificationService = notificationService,
       _deliveryService = deliveryService;

  final AppDatabase _database;
  final NtfyClient _client;
  final CredentialStore _credentialStore;
  final NotificationService _notificationService;
  final DeliveryService _deliveryService;

  List<TopicSummary> _summaries = const [];
  int _globalRetentionSeconds = 0;
  bool _loading = false;
  String? _error;

  List<TopicSummary> get summaries => List.unmodifiable(_summaries);
  int get globalRetentionSeconds => _globalRetentionSeconds;
  int effectiveRetentionSeconds(Subscription subscription) =>
      subscription.retentionSeconds ?? _globalRetentionSeconds;
  bool get loading => _loading;
  String? get error => _error;

  Future<bool> initialize() => _run(() async {
    await _database.initialize();
    _globalRetentionSeconds = await _database.readGlobalRetentionSeconds();
    await _database.deleteExpiredMessages();
    await _loadSummaries();
  });

  Future<bool> subscribe(
    String baseUrl,
    String topic,
    String? displayName,
    AuthCredential credential,
  ) => _run(() async {
    final normalized = NtfyClient.normalizeBaseUrl(baseUrl);
    NtfyClient.validateTopic(topic);
    final events = await _client.poll(
      normalized,
      topic,
      since: 'all',
      credential: credential,
    );
    final isFirstSubscription = (await _database.readSubscriptions()).isEmpty;
    await _database.addSubscription(
      normalized,
      topic,
      displayName: displayName,
      initialEvents: events,
    );
    await _credentialStore.write(normalized, credential);
    await _loadSummaries();
    try {
      if (isFirstSubscription) await _notificationService.requestPermission();
      await _deliveryService.startOrRestart();
    } catch (exception) {
      _error = 'Subscription saved, but background delivery failed: $exception';
    }
  });

  Future<bool> refresh(Subscription subscription) => _run(() async {
    final credential = await _credentialStore.read(subscription.baseUrl);
    final events = await _client.poll(
      subscription.baseUrl,
      subscription.topic,
      since: subscription.lastEventId ?? 'all',
      credential: credential,
    );
    await _database.applyEvents(subscription, events);
    await _loadSummaries();
  });

  Future<bool> publish(Subscription subscription, String message) =>
      _run(() async {
        final credential = await _credentialStore.read(subscription.baseUrl);
        final event = await _client.publish(
          subscription.baseUrl,
          subscription.topic,
          message,
          credential: credential,
        );
        if (event != null) {
          await _database.applyEvents(subscription, [event], markRead: true);
        }
        await _loadSummaries();
      });

  Future<bool> markRead(Subscription subscription) => _run(() async {
    await _database.markRead(subscription.id);
    await _loadSummaries();
  });

  Future<bool> deleteMessage(StoredMessage message) => _run(() async {
    await _database.deleteMessage(message.id);
    await _loadSummaries();
  });

  Future<bool> clearMessages(Subscription subscription) => _run(() async {
    await _database.clearMessages(subscription.id);
    await _loadSummaries();
  });

  Future<bool> setDisplayName(Subscription subscription, String? displayName) =>
      _run(() async {
        await _database.setDisplayName(subscription.id, displayName);
        await _loadSummaries();
      });

  Future<bool> setGlobalRetentionSeconds(int seconds) => _run(() async {
    await _database.setGlobalRetentionSeconds(seconds);
    _globalRetentionSeconds = seconds;
    await _database.deleteExpiredMessages();
    await _loadSummaries();
  });

  Future<bool> setSubscriptionRetentionSeconds(
    Subscription subscription,
    int? seconds,
  ) => _run(() async {
    await _database.setSubscriptionRetentionSeconds(subscription.id, seconds);
    await _database.deleteExpiredMessages(subscriptionId: subscription.id);
    await _loadSummaries();
  });

  Future<bool> unsubscribe(Subscription subscription) => _run(() async {
    await _database.unsubscribe(subscription.id);
    if (!await _database.hasSubscriptionsForBase(subscription.baseUrl)) {
      await _credentialStore.delete(subscription.baseUrl);
    }
    await _loadSummaries();
    try {
      if (_summaries.isEmpty) {
        await _deliveryService.stop();
      } else {
        await _deliveryService.startOrRestart();
      }
    } catch (exception) {
      _error = 'Subscription removed, but delivery update failed: $exception';
    }
  });

  Future<bool> reload() => _run(() async {
    await _database.deleteExpiredMessages();
    await _loadSummaries();
  });

  Future<List<StoredMessage>> listMessages(Subscription subscription) =>
      _database.listMessages(subscription.id);

  Future<void> _loadSummaries() async {
    _summaries = await _database.readSummaries();
  }

  Future<bool> _run(Future<void> Function() action) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (exception) {
      _error = exception.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
