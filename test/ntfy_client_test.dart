import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ntfy_flutter/models.dart';
import 'package:ntfy_flutter/ntfy_client.dart';

void main() {
  group('validation and URL building', () {
    test('normalizes only an HTTP origin and validates topics', () {
      expect(
        NtfyClient.normalizeBaseUrl('https://Example.com:8443/'),
        'https://example.com:8443',
      );
      expect(
        () => NtfyClient.normalizeBaseUrl('https://example.com/path'),
        throwsFormatException,
      );
      expect(
        () => NtfyClient.normalizeBaseUrl('ftp://example.com'),
        throwsFormatException,
      );
      expect(
        () => NtfyClient.normalizeBaseUrl('https://example.com?'),
        throwsFormatException,
      );
      final address = NtfyClient.parseTopicUrl(
        'https://Example.com:8443/a-B_9',
      );
      expect(address.baseUrl, 'https://example.com:8443');
      expect(address.topic, 'a-B_9');
      expect(
        () => NtfyClient.parseTopicUrl('https://ntfy.sh/one/two'),
        throwsFormatException,
      );
      expect(NtfyClient.isValidTopic('a-B_9'), isTrue);
      expect(NtfyClient.isValidTopic('bad topic'), isFalse);
      expect(NtfyClient.isValidTopic(List.filled(65, 'a').join()), isFalse);

      final poll = NtfyClient.pollUri('https://ntfy.sh', 'topic', since: 'abc');
      expect(poll.path, '/topic/json');
      expect(poll.queryParameters, {'poll': '1', 'since': 'abc'});
      expect(
        NtfyClient.webSocketUri(
          'https://ntfy.sh',
          'topic',
          since: 'all',
        ).toString(),
        'wss://ntfy.sh/topic/ws?since=all',
      );
    });
  });

  group('authentication', () {
    test('creates Basic and Bearer headers only for HTTPS', () {
      expect(
        NtfyClient.authorizationHeaders(
          'https://ntfy.sh',
          const AuthCredential.basic(username: 'üser', password: 'päss'),
        )['Authorization'],
        'Basic ${base64Encode(utf8.encode('üser:päss'))}',
      );
      expect(
        NtfyClient.authorizationHeaders(
          'https://ntfy.sh',
          const AuthCredential.bearer('token'),
        ),
        {'Authorization': 'Bearer token'},
      );
      expect(
        () => NtfyClient.authorizationHeaders(
          'http://ntfy.sh',
          const AuthCredential.bearer('token'),
        ),
        throwsFormatException,
      );
    });
  });

  test('parses NDJSON message and control events', () {
    final events = NtfyClient.parseNdjson(
      '${jsonEncode({
        'id': 'm1',
        'time': 1700000000,
        'event': 'message',
        'topic': 'news',
        'message': 'hello',
        'title': 'Greeting',
        'tags': ['wave'],
        'priority': 5,
        'sequence_id': 12,
      })}\n'
      '${jsonEncode({'id': 'k1', 'time': 1700000001, 'event': 'keepalive', 'topic': 'news'})}\n',
    );

    expect(events, hasLength(2));
    expect(events.first.message, 'hello');
    expect(events.first.tags, ['wave']);
    expect(events.first.priority, 5);
    expect(events.first.sequenceId, '12');
    expect(events.last.isMessage, isFalse);
    expect(
      () => NtfyClient.parseNdjson('{"event":"message"}\n'),
      throwsFormatException,
    );
  });

  test('poll sends auth and parses UTF-8 response', () async {
    final client = NtfyClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/news/json');
        expect(request.url.queryParameters['poll'], '1');
        expect(request.url.queryParameters['since'], 'all');
        expect(request.headers['authorization'], 'Bearer token');
        return http.Response.bytes(
          utf8.encode(
            '${jsonEncode({'id': 'm1', 'time': 1700000000, 'event': 'message', 'topic': 'news', 'message': 'héllo'})}\n',
          ),
          200,
        );
      }),
    );

    final events = await client.poll(
      'https://ntfy.sh',
      'news',
      since: 'all',
      credential: const AuthCredential.bearer('token'),
    );
    expect(events.single.message, 'héllo');
  });

  test('publish uses a UTF-8 PUT and parses the response', () async {
    final client = NtfyClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.toString(), 'https://ntfy.sh/news');
        expect(request.headers['content-type'], 'text/plain; charset=utf-8');
        expect(request.bodyBytes, utf8.encode('Grüße 👋'));
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'id': 'm1',
              'time': 1700000000,
              'event': 'message',
              'topic': 'news',
              'message': 'Grüße 👋',
            }),
          ),
          200,
        );
      }),
    );

    final event = await client.publish('https://ntfy.sh', 'news', 'Grüße 👋');
    expect(event?.id, 'm1');
  });

  test('publish exposes HTTP failures', () async {
    final client = NtfyClient(
      httpClient: MockClient((_) async => http.Response('denied', 403)),
    );

    await expectLater(
      client.publish('https://ntfy.sh', 'news', 'hello'),
      throwsA(
        isA<NtfyException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.message, 'message', 'denied'),
      ),
    );
    await expectLater(
      client.publish('https://ntfy.sh', 'news', '  '),
      throwsFormatException,
    );
  });
}
