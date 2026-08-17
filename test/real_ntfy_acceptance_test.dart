import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:ntfy_flutter/topic_feed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final ntfyBinary = Platform.environment['NTFY_BIN'];

  test(
    'ingests and resumes against a real local ntfy server',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ntfy_real_acceptance',
      );
      final portProbe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = portProbe.port;
      await portProbe.close();
      final process = await Process.start(ntfyBinary!, [
        'serve',
        '--listen-http',
        '127.0.0.1:$port',
        '--cache-file',
        '${directory.path}/server-cache.db',
        '--web-root',
        'disable',
        '--keepalive-interval',
        '5s',
      ]);
      unawaited(process.stdout.transform(utf8.decoder).drain<void>());
      unawaited(process.stderr.transform(utf8.decoder).drain<void>());
      addTearDown(() async {
        process.kill();
        await process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () => -1,
        );
        await directory.delete(recursive: true);
      });

      final baseUrl = 'http://127.0.0.1:$port';
      await _waitForHealth(baseUrl);
      final databasePath = '${directory.path}/app.db';
      var store = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final subscription = await store.add(url: '$baseUrl/acceptance');
      var controller = TopicFeedController(
        repository: store,
        subscription: subscription,
        client: HttpNtfyStreamClient(),
        retryDelays: const [Duration.zero],
      );
      unawaited(controller.start());
      await _until(() => controller.state.status == FeedStatus.connected);

      await _publish(
        subscription.url,
        'First body',
        title: 'First title',
        priority: 5,
        tags: 'warning,server',
      );
      await _until(() => controller.state.messages.length == 1);
      final firstCursor = controller.state.cursor;
      await controller.close();
      await store.close();

      await _publish(subscription.url, 'Second body');
      store = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      controller = TopicFeedController(
        repository: store,
        subscription: subscription,
        client: HttpNtfyStreamClient(),
        retryDelays: const [Duration.zero],
      );
      unawaited(controller.start());
      await _until(() => controller.state.messages.length == 2);
      await controller.close();

      final snapshot = await store.loadFeed(subscription.id);
      await store.close();
      expect(firstCursor, isNotNull);
      expect(snapshot.messages.map((message) => message.message), [
        'First body',
        'Second body',
      ]);
      expect(snapshot.messages.first.title, 'First title');
      expect(snapshot.messages.first.priority, 5);
      expect(snapshot.messages.first.tags, ['warning', 'server']);
      expect(snapshot.cursor, isNot(firstCursor));
    },
    skip: ntfyBinary == null
        ? 'Set NTFY_BIN to run against a real local ntfy server.'
        : false,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<void> _waitForHealth(String baseUrl) async {
  final client = HttpClient();
  addTearDown(() => client.close(force: true));
  await _until(() async {
    try {
      final response = await (await client.getUrl(
        Uri.parse('$baseUrl/v1/health'),
      )).close();
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  });
}

Future<void> _publish(
  String topicUrl,
  String message, {
  String? title,
  int? priority,
  String? tags,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(topicUrl));
    if (title != null) request.headers.set('Title', title);
    if (priority != null) request.headers.set('Priority', priority);
    if (tags != null) request.headers.set('Tags', tags);
    request.write(message);
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.ok);
  } finally {
    client.close(force: true);
  }
}

Future<void> _until(FutureOr<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}
