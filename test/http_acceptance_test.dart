import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/subscriptions.dart';
import 'package:ntfy_flutter/topic_feed.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test(
    'production HTTP stream persists, reconnects, and resumes after restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ntfy_http_acceptance',
      );
      final databasePath = '${directory.path}/ntfy.db';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Uri>[];
      final allowRestartResponse = Completer<void>();
      final serverDone = server.listen((request) async {
        requests.add(request.uri);
        request.response.headers.contentType = ContentType(
          'application',
          'x-ndjson',
          charset: 'utf-8',
        );
        final since = request.uri.queryParameters['since'];
        if (since == 'all') {
          request.response.writeln('{malformed');
          request.response.writeln(
            jsonEncode({'event': 'keepalive', 'topic': 'alerts'}),
          );
          request.response.writeln(
            _event('wrong', 1, 'Wrong topic', topic: 'other'),
          );
          request.response.writeln(
            _event(
              'a',
              20,
              'Later',
              title: 'Title',
              priority: 5,
              tags: ['warning'],
            ),
          );
          request.response.writeln(_event('a', 20, 'Duplicate'));
        } else if (since == 'a') {
          request.response.writeln(_event('b', 10, 'Earlier'));
        } else if (since == 'b') {
          await allowRestartResponse.future;
          request.response.writeln(_event('c', 30, 'After restart'));
        }
        await request.response.close();
      }).asFuture<void>();
      addTearDown(() async {
        await server.close(force: true);
        await serverDone;
        await directory.delete(recursive: true);
      });

      var store = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final subscription = await store.add(
        url: 'http://${server.address.host}:${server.port}/alerts',
      );
      var controller = TopicFeedController(
        repository: store,
        subscription: subscription,
        client: HttpNtfyStreamClient(),
        retryDelays: const [Duration.zero],
      );
      unawaited(controller.start());
      await _until(() => controller.state.messages.length == 2);
      await controller.close();
      allowRestartResponse.complete();

      var snapshot = await store.loadFeed(subscription.id);
      expect(requests[0].path, '/alerts/json');
      expect(requests[0].queryParameters['since'], 'all');
      expect(requests[1].queryParameters['since'], 'a');
      expect(snapshot.messages.map((message) => message.eventId), ['b', 'a']);
      expect(snapshot.messages.last.title, 'Title');
      expect(snapshot.messages.last.priority, 5);
      expect(snapshot.messages.last.tags, ['warning']);
      expect(snapshot.cursor, 'b');
      await store.close();

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
      await _until(() => controller.state.messages.length == 3);
      await controller.close();

      snapshot = await store.loadFeed(subscription.id);
      await store.close();
      expect(
        requests.map((uri) => uri.queryParameters['since']),
        contains('b'),
      );
      expect(snapshot.messages.map((message) => message.eventId), [
        'b',
        'a',
        'c',
      ]);
      expect(snapshot.cursor, 'c');
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}

String _event(
  String id,
  int time,
  String message, {
  String topic = 'alerts',
  String? title,
  int? priority,
  List<String>? tags,
}) {
  final event = <String, Object?>{
    'event': 'message',
    'topic': topic,
    'id': id,
    'time': time,
    'message': message,
  };
  if (title != null) event['title'] = title;
  if (priority != null) event['priority'] = priority;
  if (tags != null) event['tags'] = tags;
  return jsonEncode(event);
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
