import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/message_actions.dart';
import 'package:ntfy_flutter/messages.dart';

void main() {
  test(
    'view and broadcast actions use only their narrow platform seams',
    () async {
      final platform = _RecordingPlatform();
      final executor = MessageActionExecutor(platform: platform);

      await executor.execute(
        const MessageAction(
          id: 'view',
          action: 'view',
          label: 'Open',
          url: 'https://example.com/details',
        ),
      );
      await executor.execute(
        const MessageAction(
          id: 'broadcast',
          action: 'broadcast',
          label: 'Send',
          intent: 'com.example.ACTION',
          extras: {'result': 'ok'},
        ),
      );

      expect(platform.opened.single.toString(), 'https://example.com/details');
      expect(platform.broadcasts.single.$1, 'com.example.ACTION');
      expect(platform.broadcasts.single.$2, {'result': 'ok'});
      await expectLater(
        executor.openClick('javascript:alert(1)'),
        throwsA(isA<MessageActionException>()),
      );
    },
  );

  test('HTTP actions preserve method, headers, and body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<(String, String?, String)>();
    server.listen((request) async {
      received.complete((
        request.method,
        request.headers.value('X-Action'),
        await utf8.decoder.bind(request).join(),
      ));
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    final executor = MessageActionExecutor(platform: _RecordingPlatform());

    await executor.execute(
      MessageAction(
        id: 'http',
        action: 'http',
        label: 'Acknowledge',
        url: 'http://${server.address.host}:${server.port}/ack',
        method: 'PUT',
        headers: const {'X-Action': 'confirmed'},
        body: 'done',
      ),
    );

    expect(await received.future, ('PUT', 'confirmed', 'done'));
  });
}

class _RecordingPlatform implements MessageActionPlatform {
  final opened = <Uri>[];
  final broadcasts = <(String?, Map<String, String>)>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }

  @override
  Future<void> broadcast(String? intent, Map<String, String> extras) async {
    broadcasts.add((intent, extras));
  }
}
