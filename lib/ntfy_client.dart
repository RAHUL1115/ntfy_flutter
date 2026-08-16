import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

class TopicAddress {
  const TopicAddress({required this.baseUrl, required this.topic});

  final String baseUrl;
  final String topic;
}

class NtfyException implements Exception {
  const NtfyException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

typedef WebSocketConnector = WebSocketChannel Function(
  Uri uri,
  Map<String, String> headers,
);

class NtfyClient {
  NtfyClient({http.Client? httpClient, WebSocketConnector? webSocketConnector})
    : _http = httpClient ?? http.Client(),
      _connectWebSocket = webSocketConnector ?? _defaultWebSocketConnector;

  final http.Client _http;
  final WebSocketConnector _connectWebSocket;

  static final RegExp _topicPattern = RegExp(r'^[-_A-Za-z0-9]{1,64}$');

  static String normalizeBaseUrl(String value) {
    if (value != value.trim() || value.isEmpty) {
      throw const FormatException('Enter a valid server URL');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'Server URL must contain only http(s), host, and optional port',
      );
    }
    return uri.origin;
  }

  static TopicAddress parseTopicUrl(String value) {
    if (value != value.trim() || value.isEmpty) {
      throw const FormatException('Enter a valid topic URL');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.pathSegments.length != 1 ||
        uri.pathSegments.single.isEmpty) {
      throw const FormatException(
        'Use a full topic URL such as https://ntfy.sh/my-topic',
      );
    }
    final topic = uri.pathSegments.single;
    validateTopic(topic);
    return TopicAddress(baseUrl: uri.origin, topic: topic);
  }

  static bool isValidTopic(String topic) => _topicPattern.hasMatch(topic);

  static void validateTopic(String topic) {
    if (!isValidTopic(topic)) {
      throw const FormatException(
        'Topic must be 1-64 letters, numbers, hyphens, or underscores',
      );
    }
  }

  static Map<String, String> authorizationHeaders(
    String baseUrl,
    AuthCredential credential,
  ) {
    final normalized = normalizeBaseUrl(baseUrl);
    if (credential.type == AuthType.none) return const {};
    if (Uri.parse(normalized).scheme != 'https') {
      throw const FormatException('Credentials require HTTPS');
    }
    switch (credential.type) {
      case AuthType.basic:
        final username = credential.username ?? '';
        final password = credential.secret ?? '';
        if (username.isEmpty || password.isEmpty) {
          throw const FormatException('Username and password are required');
        }
        return {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        };
      case AuthType.bearer:
        final token = credential.secret ?? '';
        if (token.isEmpty) {
          throw const FormatException('Bearer token is required');
        }
        return {'Authorization': 'Bearer $token'};
      case AuthType.none:
        return const {};
    }
  }

  static Uri pollUri(String baseUrl, String topic, {required String since}) {
    final normalized = normalizeBaseUrl(baseUrl);
    validateTopic(topic);
    return Uri.parse('$normalized/$topic/json')
        .replace(queryParameters: {'poll': '1', 'since': since});
  }

  static Uri publishUri(String baseUrl, String topic) {
    final normalized = normalizeBaseUrl(baseUrl);
    validateTopic(topic);
    return Uri.parse('$normalized/$topic');
  }

  static Uri webSocketUri(
    String baseUrl,
    String topic, {
    required String since,
  }) {
    final normalized = normalizeBaseUrl(baseUrl);
    validateTopic(topic);
    final uri = Uri.parse('$normalized/$topic/ws')
        .replace(queryParameters: {'since': since});
    return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws');
  }

  static List<NtfyEvent> parseNdjson(String body) {
    final events = <NtfyEvent>[];
    for (final line in const LineSplitter().convert(body)) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }
      events.add(NtfyEvent.fromJson(decoded));
    }
    return events;
  }

  Future<List<NtfyEvent>> poll(
    String baseUrl,
    String topic, {
    required String since,
    AuthCredential credential = const AuthCredential.none(),
  }) async {
    final response = await _http.get(
      pollUri(baseUrl, topic, since: since),
      headers: authorizationHeaders(baseUrl, credential),
    );
    _checkResponse(response);
    return parseNdjson(utf8.decode(response.bodyBytes));
  }

  Future<NtfyEvent?> publish(
    String baseUrl,
    String topic,
    String message, {
    AuthCredential credential = const AuthCredential.none(),
  }) async {
    if (message.trim().isEmpty) {
      throw const FormatException('Message cannot be empty');
    }
    final headers = <String, String>{
      ...authorizationHeaders(baseUrl, credential),
      'Content-Type': 'text/plain; charset=utf-8',
    };
    final response = await _http.put(
      publishUri(baseUrl, topic),
      headers: headers,
      body: message,
      encoding: utf8,
    );
    _checkResponse(response);
    if (response.bodyBytes.isEmpty) return null;
    final events = parseNdjson(utf8.decode(response.bodyBytes));
    return events.isEmpty ? null : events.single;
  }

  Stream<NtfyEvent> stream(
    String baseUrl,
    String topic, {
    required String since,
    AuthCredential credential = const AuthCredential.none(),
  }) {
    final channel = _connectWebSocket(
      webSocketUri(baseUrl, topic, since: since),
      authorizationHeaders(baseUrl, credential),
    );
    return channel.stream.expand((data) {
      final text = data is List<int> ? utf8.decode(data) : data.toString();
      return parseNdjson(text);
    });
  }

  void close() => _http.close();

  static WebSocketChannel _defaultWebSocketConnector(
    Uri uri,
    Map<String, String> headers,
  ) => IOWebSocketChannel.connect(uri, headers: headers);

  static void _checkResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = utf8.decode(response.bodyBytes).trim();
      throw NtfyException(
        detail.isEmpty ? 'ntfy request failed' : detail,
        statusCode: response.statusCode,
      );
    }
  }
}
