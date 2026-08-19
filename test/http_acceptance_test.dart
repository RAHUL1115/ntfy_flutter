import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/background_listening.dart';
import 'package:ntfy_flutter/publish.dart';
import 'package:ntfy_flutter/retention.dart';
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
      expect(snapshot.messages.map((message) => message.eventId), ['a', 'b']);
      expect(snapshot.messages.first.title, 'Title');
      expect(snapshot.messages.first.priority, 5);
      expect(snapshot.messages.first.tags, ['warning']);
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
        'c',
        'a',
        'b',
      ]);
      expect(snapshot.cursor, 'c');
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test(
    'published message is inserted only when streamed and remains deduped',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ntfy_publish_acceptance',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final publishedBody = Completer<String>();
      final streamReady = Completer<void>();
      final serverDone = server.listen((request) async {
        if (request.method == 'GET') {
          request.response.headers.contentType = ContentType(
            'application',
            'x-ndjson',
            charset: 'utf-8',
          );
          streamReady.complete();
          final event = _event(
            'published',
            30,
            await publishedBody.future,
            title: 'Published title',
            priority: 4,
            tags: ['warning', 'server'],
          );
          request.response
            ..writeln(event)
            ..writeln(event);
          await request.response.close();
          return;
        }
        expect(request.method, 'PUT');
        final body = await utf8.decoder.bind(request).join();
        expect(body, 'Published body');
        expect(request.uri.queryParameters, {
          'priority': '4',
          'title': 'Published title',
          'tags': 'warning,server',
        });
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        publishedBody.complete(body);
      }).asFuture<void>();
      addTearDown(() async {
        await server.close(force: true);
        await serverDone;
        await directory.delete(recursive: true);
      });

      final store = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/ntfy.db',
      );
      final topicUrl = 'http://${server.address.host}:${server.port}/alerts';
      final subscription = await store.add(url: topicUrl);
      final controller = TopicFeedController(
        repository: store,
        subscription: subscription,
        client: HttpNtfyStreamClient(),
      );
      unawaited(controller.start());
      await streamReady.future;

      await HttpNtfyPublisher().publish(
        topicUrl,
        const PublishMessage(
          message: 'Published body',
          title: 'Published title',
          priority: 4,
          tags: ['warning', 'server'],
        ),
      );
      await _until(() => controller.state.messages.isNotEmpty);

      expect(controller.state.messages, hasLength(1));
      final published = controller.state.messages.single;
      expect(published.message, 'Published body');
      expect(published.title, 'Published title');
      expect(published.priority, 4);
      expect(published.tags, ['warning', 'server']);
      expect((await store.loadFeed(subscription.id)).messages, hasLength(1));
      await controller.close();
      await store.close();
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test(
    'background runtime persists across restarts without closing the UI store',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ntfy_background_acceptance',
      );
      final databasePath = '${directory.path}/ntfy.db';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var connections = 0;
      final serverDone = server.listen((request) async {
        connections++;
        request.response.headers.contentType = ContentType(
          'application',
          'x-ndjson',
          charset: 'utf-8',
        );
        request.response.writeln(
          _event(
            'background-$connections',
            connections,
            'Background $connections',
          ),
        );
        await request.response.close();
      }).asFuture<void>();
      addTearDown(() async {
        await server.close(force: true);
        await serverDone;
        await directory.delete(recursive: true);
      });

      final uiStore = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      addTearDown(uiStore.close);
      final subscription = await uiStore.add(
        url: 'http://${server.address.host}:${server.port}/alerts',
      );
      await uiStore.setBackgroundListening(true);

      BackgroundListenerRuntime runtimeFor(AppRepository repository) =>
          BackgroundListenerRuntime(
            repository,
            clientFactory: (_) => HttpNtfyStreamClient(),
            retention: RetentionSession(
              repository,
              cleanupInterval: const Duration(days: 1),
            ),
          );

      final firstServiceStore = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final firstRuntime = runtimeFor(firstServiceStore);
      expect(await firstRuntime.start(), isTrue);
      await _until(() => connections >= 1);
      await _untilAsync(
        () async =>
            (await uiStore.loadFeed(subscription.id)).messages.length == 1,
      );
      await firstRuntime.stop();
      expect(
        (await uiStore.loadFeed(subscription.id)).messages.single.message,
        'Background 1',
      );

      final secondServiceStore = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: databasePath,
      );
      final secondRuntime = runtimeFor(secondServiceStore);
      expect(await secondRuntime.start(), isTrue);
      await _untilAsync(
        () async =>
            (await uiStore.loadFeed(subscription.id)).messages.length == 2,
      );
      await secondRuntime.stop();

      final snapshot = await uiStore.loadFeed(subscription.id);
      expect(snapshot.messages.map((message) => message.eventId), [
        'background-2',
        'background-1',
      ]);
      expect(snapshot.cursor, 'background-2');
      await uiStore.setBackgroundListening(false);
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test(
    'local cleanup and unsubscribe send no deletion requests to ntfy',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ntfy_cleanup_acceptance',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      final serverDone = server.listen((request) async {
        requests.add(request.method);
        request.response.headers.contentType = ContentType(
          'application',
          'x-ndjson',
          charset: 'utf-8',
        );
        request.response.writeln(_event('cleanup', 1, 'Local only'));
        await request.response.close();
      }).asFuture<void>();
      addTearDown(() async {
        await server.close(force: true);
        await serverDone;
        await directory.delete(recursive: true);
      });

      final store = await SubscriptionStore.open(
        factory: databaseFactoryFfi,
        path: '${directory.path}/ntfy.db',
      );
      addTearDown(store.close);
      final subscription = await store.add(
        url: 'http://${server.address.host}:${server.port}/alerts',
      );
      final session = TopicFeedSession(
        controller: TopicFeedController(
          repository: store,
          subscription: subscription,
          client: HttpNtfyStreamClient(),
          retryDelays: const [Duration(seconds: 30)],
        ),
      );
      unawaited(session.start());
      await _until(() => session.state.messages.length == 1);
      final message = session.state.messages.single;

      await session.execute(DeleteLocalMessage(message.localId));
      await session.execute(RestoreLocalMessage(message));
      await store.executeRetention(
        SetTopicRetention(
          subscription.id,
          RetentionPeriod.oneHour,
          now: DateTime.utc(2026),
        ),
      );
      await session.execute(const RefreshLocalMessages());
      expect(session.state.messages, isEmpty);
      await session.execute(const ClearLocalMessages());
      await session.close();
      await store.remove(subscription.id);

      expect(requests, ['GET']);
      expect(await store.all(), isEmpty);
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

Future<void> _untilAsync(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
