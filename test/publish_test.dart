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

  test('maps advanced fields and uploads a selected local file', () async {
    final directory = await Directory.systemTemp.createTemp('ntfy_publish');
    final file = File('${directory.path}/report.txt');
    await file.writeAsString('attachment body');
    addTearDown(() => directory.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late HttpRequest received;
    late String body;
    final handled = Completer<void>();
    server.listen((request) async {
      received = request;
      body = await utf8.decoder.bind(request).join();
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      handled.complete();
    });
    addTearDown(() => server.close(force: true));

    await HttpNtfyPublisher().publish(
      'http://${server.address.host}:${server.port}/alerts',
      PublishMessage(
        message: 'See report\n✅',
        markdown: true,
        clickUrl: 'https://example.com/details',
        email: 'ops@example.com',
        delay: '30m',
        phoneCall: '+15551234567',
        attachmentFilePath: file.path,
        attachmentFileName: 'report.txt',
      ),
    );
    await handled.future;

    expect(received.uri.queryParameters['markdown'], 'yes');
    expect(
      received.uri.queryParameters['click'],
      'https://example.com/details',
    );
    expect(received.uri.queryParameters['email'], 'ops@example.com');
    expect(received.uri.queryParameters['delay'], '30m');
    expect(received.uri.queryParameters['call'], '+15551234567');
    expect(received.uri.queryParameters['filename'], 'report.txt');
    expect(received.uri.queryParameters['message'], r'See report\n✅');
    expect(received.headers.value('Filename'), isNull);
    expect(received.headers.value('Message'), isNull);
    expect(body, 'attachment body');
  });

  test('rejects unavailable and oversized local attachments', () async {
    final directory = await Directory.systemTemp.createTemp('ntfy_publish');
    addTearDown(() => directory.delete(recursive: true));
    final oversized = File('${directory.path}/oversized.bin');
    await oversized.openWrite().close();
    await oversized.open(mode: FileMode.write).then((file) async {
      await file.truncate(HttpNtfyPublisher.maxAttachmentBytes + 1);
      await file.close();
    });

    for (final path in ['${directory.path}/missing.bin', oversized.path]) {
      await expectLater(
        HttpNtfyPublisher().publish(
          'http://127.0.0.1:1/alerts',
          PublishMessage(message: 'attachment', attachmentFilePath: path),
        ),
        throwsA(isA<PublishException>()),
      );
    }
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
