import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ntfy_flutter/background_listening.dart';
import 'package:ntfy_flutter/notifications.dart';
import 'package:ntfy_flutter/subscriptions.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'background notifications map priority, dedupe, and suppress visible feed',
    (tester) async {
      const host = AndroidBackgroundListeningHost();
      final store = await SubscriptionStore.open();
      final notificationPlatform = AndroidNotificationPlatform();
      final notifications = MessageNotificationSession(notificationPlatform);
      final releaseNotifications = Completer<void>();
      final holdConnection = Completer<void>();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final topic = 'background_${DateTime.now().microsecondsSinceEpoch}';
      var requestCount = 0;
      final serverDone = server.listen((request) async {
        final index = requestCount++;
        request.response.headers.contentType = ContentType(
          'application',
          'x-ndjson',
          charset: 'utf-8',
        );
        if (index == 0) {
          request.response.writeln(_event(topic, 'visible', priority: 5));
        } else if (index == 1) {
          await releaseNotifications.future;
          for (var priority = 1; priority <= 5; priority++) {
            request.response.writeln(
              _event(topic, 'priority-$priority', priority: priority),
            );
          }
          request.response.writeln(_event(topic, 'priority-3', priority: 3));
        } else {
          await holdConnection.future;
        }
        await request.response.close();
      }).asFuture<void>();
      final subscription = await store.add(
        url: 'http://${server.address.host}:${server.port}/$topic',
      );
      for (final sequenceId in [
        'visible',
        for (var priority = 1; priority <= 5; priority++) 'priority-$priority',
      ]) {
        await notificationPlatform.cancel(subscription.id, sequenceId);
      }
      addTearDown(() async {
        await store.setBackgroundListening(false);
        await host.stop();
        for (final sequenceId in [
          'visible',
          for (var priority = 1; priority <= 5; priority++)
            'priority-$priority',
        ]) {
          await notificationPlatform.cancel(subscription.id, sequenceId);
        }
        await notifications.setVisibleSubscription(null);
        await notifications.close();
        if (!releaseNotifications.isCompleted) releaseNotifications.complete();
        if (!holdConnection.isCompleted) holdConnection.complete();
        await server.close(force: true);
        await serverDone;
        await store.remove(subscription.id);
        await store.close();
      });

      await notifications.setVisibleSubscription(subscription.id);
      await store.setBackgroundListening(true);
      await host.startOrRefresh();
      await _until(() async {
        final status = await host.status();
        return status.running && status.notificationPresent;
      });
      await _until(
        () async =>
            (await store.loadFeed(subscription.id)).messages.length == 1,
      );
      expect(
        (await host.status()).messageNotifications.where(
          (item) => item.subscriptionId == subscription.id,
        ),
        isEmpty,
      );

      await notifications.setVisibleSubscription(null);
      releaseNotifications.complete();
      await _until(
        () async =>
            (await store.loadFeed(subscription.id)).messages.length == 6,
      );
      await _until(() async {
        final current = (await host.status()).messageNotifications.where(
          (item) => item.subscriptionId == subscription.id,
        );
        return current.length == 5;
      });

      final channels = {
        for (final item in (await host.status()).messageNotifications.where(
          (item) => item.subscriptionId == subscription.id,
        ))
          item.eventId: item.channelId,
      };
      expect(channels, {
        'priority-1': 'ntfy-min',
        'priority-2': 'ntfy-low',
        'priority-3': 'ntfy',
        'priority-4': 'ntfy-high',
        'priority-5': 'ntfy-max',
      });

      await store.setBackgroundListening(false);
      await host.stop();
      await _until(() async {
        final status = await host.status();
        return !status.running && !status.notificationPresent;
      });
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets('foreground service ingests across explicit restart cycles', (
    tester,
  ) async {
    const host = AndroidBackgroundListeningHost();
    final notificationPlatform = AndroidNotificationPlatform();
    final store = await SubscriptionStore.open();
    final gates = [Completer<void>(), Completer<void>()];
    final holdConnections = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final topic = 'restart_${DateTime.now().microsecondsSinceEpoch}';
    var requestCount = 0;
    final serverDone = server.listen((request) async {
      final index = requestCount++;
      request.response.headers.contentType = ContentType(
        'application',
        'x-ndjson',
        charset: 'utf-8',
      );
      request.response.writeln(_event(topic, 'service-$index', priority: 3));
      await request.response.flush();
      if (index < gates.length) {
        await gates[index].future;
      } else {
        await holdConnections.future;
      }
      await request.response.close();
    }).asFuture<void>();
    final subscription = await store.add(
      url: 'http://${server.address.host}:${server.port}/$topic',
    );
    addTearDown(() async {
      await store.setBackgroundListening(false);
      await host.stop();
      for (var index = 0; index < requestCount; index++) {
        await notificationPlatform.cancel(subscription.id, 'service-$index');
      }
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      if (!holdConnections.isCompleted) holdConnections.complete();
      await server.close(force: true);
      await serverDone;
      await store.remove(subscription.id);
      await store.close();
    });

    await store.setBackgroundListening(true);
    for (var cycle = 0; cycle < 2; cycle++) {
      await host.startOrRefresh();
      await _until(() async => requestCount > cycle);
      gates[cycle].complete();
      await _until(
        () async =>
            (await store.loadFeed(subscription.id)).messages.length ==
            cycle + 1,
      );
      await host.stop();
      await _until(() async {
        final status = await host.status();
        return !status.running && !status.notificationPresent;
      });
    }

    expect(
      (await store.loadFeed(subscription.id)).messages
          .map((message) => message.eventId),
      ['service-0', 'service-1'],
    );

    await host.startOrRefresh();
    await _until(() async => (await host.status()).running);
    final stopping = host.stop();
    await Future<void>.delayed(Duration.zero);
    final restarting = host.startOrRefresh();
    await Future.wait([stopping, restarting]);
    await _until(() async => (await host.status()).running);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

String _event(String topic, String id, {required int priority}) => jsonEncode({
  'event': 'message',
  'topic': topic,
  'id': id,
  'time': 1_787_000_000 + priority,
  'message': 'Background $id',
  'priority': priority,
});

Future<void> _until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
