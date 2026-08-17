import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ntfy_flutter/background_listening.dart';
import 'package:ntfy_flutter/subscriptions.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'foreground service ingests across restarts and removes its notification',
    (tester) async {
      const host = AndroidBackgroundListeningHost();
      final store = await SubscriptionStore.open();
      final gates = [Completer<void>(), Completer<void>()];
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
        request.response.writeln(
          jsonEncode({
            'event': 'message',
            'topic': topic,
            'id': 'service-$index',
            'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'message': 'Background service message $index',
          }),
        );
        await request.response.flush();
        if (index < gates.length) await gates[index].future;
        await request.response.close();
      }).asFuture<void>();
      final subscription = await store.add(
        url: 'http://${server.address.host}:${server.port}/$topic',
      );
      addTearDown(() async {
        await store.setBackgroundListening(false);
        await host.stop();
        for (final gate in gates) {
          if (!gate.isCompleted) gate.complete();
        }
        await server.close(force: true);
        await serverDone;
        await store.remove(subscription.id);
        await store.close();
      });

      await store.setBackgroundListening(true);
      await host.startOrRefresh();
      await _untilAsync(() async {
        final status = await host.status();
        return status.running && status.notificationPresent;
      });
      await _untilAsync(() async => requestCount >= 1);
      gates[0].complete();
      await _untilAsync(
        () async =>
            (await store.loadFeed(subscription.id)).messages.length == 1,
        description: () async {
          final status = await host.status();
          final feed = await store.loadFeed(subscription.id);
          return 'requests=$requestCount, running=${status.running}, '
              'notification=${status.notificationPresent}, '
              'messages=${feed.messages.length}';
        },
      );

      await host.stop();
      await _untilAsync(() async {
        final status = await host.status();
        return !status.running && !status.notificationPresent;
      });
      expect(
        (await store.loadFeed(subscription.id)).messages.single.eventId,
        'service-0',
      );

      await host.startOrRefresh();
      await _untilAsync(() async {
        final status = await host.status();
        return status.running && status.notificationPresent;
      });
      await _untilAsync(() async => requestCount >= 2);
      gates[1].complete();
      await _untilAsync(
        () async =>
            (await store.loadFeed(subscription.id)).messages.length == 2,
      );
      expect(
        (await store.loadFeed(subscription.id)).messages
            .map((message) => message.eventId),
        ['service-0', 'service-1'],
      );

      await store.setBackgroundListening(false);
      await host.stop();
      await _untilAsync(() async {
        final status = await host.status();
        return !status.running && !status.notificationPresent;
      });
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<void> _untilAsync(
  Future<bool> Function() condition, {
  Future<String> Function()? description,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        description == null ? 'condition' : await description(),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
