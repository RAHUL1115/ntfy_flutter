import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/publish.dart';

void main() {
  test(
    'PUTs raw message and supported query fields to the topic URL',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      late String method;
      late Uri uri;
      late String body;
      final handled = Completer<void>();
      server.listen((request) async {
        method = request.method;
        uri = request.uri;
        body = await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        handled.complete();
      });
      addTearDown(() => server.close(force: true));

      await HttpNtfyPublisher().publish(
        'http://${server.address.host}:${server.port}/alerts',
        const PublishMessage(
          message: 'raw body',
          title: 'Production alert',
          priority: 5,
          tags: ['warning', 'server'],
        ),
      );
      await handled.future;

      expect(method, 'PUT');
      expect(uri.path, '/alerts');
      expect(uri.queryParameters, {
        'priority': '5',
        'title': 'Production alert',
        'tags': 'warning,server',
      });
      expect(body, 'raw body');
    },
  );

  test('rejects invalid input before opening a request', () async {
    await expectLater(
      HttpNtfyPublisher().publish(
        'http://127.0.0.1:1/alerts',
        const PublishMessage(message: '   '),
      ),
      throwsA(
        isA<PublishException>().having(
          (error) => error.message,
          'message',
          'Message is required.',
        ),
      ),
    );
    await expectLater(
      HttpNtfyPublisher().publish(
        'http://127.0.0.1:1/alerts',
        const PublishMessage(message: 'hello', priority: 6),
      ),
      throwsA(isA<PublishException>()),
    );
  });

  test('surfaces server JSON errors and actionable status errors', () async {
    Future<String> failure(int status, String body) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = status;
        request.response.write(body);
        await request.response.close();
      });
      try {
        await HttpNtfyPublisher().publish(
          'http://${server.address.host}:${server.port}/alerts',
          const PublishMessage(message: 'hello'),
        );
        fail('Expected publishing to fail');
      } on PublishException catch (error) {
        return error.message;
      } finally {
        await server.close(force: true);
      }
    }

    expect(await failure(400, '{"error":"bad topic"}'), 'bad topic');
    expect(await failure(403, ''), contains('credentials or access'));
    expect(await failure(413, ''), contains('too large'));
  });
}
