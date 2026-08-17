import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PublishMessage {
  const PublishMessage({
    required this.message,
    this.title,
    this.priority = 3,
    this.tags = const [],
  });

  final String message;
  final String? title;
  final int priority;
  final List<String> tags;

  String? get validationError {
    if (message.trim().isEmpty) return 'Message is required.';
    if (priority < 1 || priority > 5) {
      return 'Priority must be between 1 and 5.';
    }
    return null;
  }
}

abstract interface class NtfyPublisher {
  Future<void> publish(String topicUrl, PublishMessage message);
}

class PublishException implements Exception {
  const PublishException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HttpNtfyPublisher implements NtfyPublisher {
  @override
  Future<void> publish(String topicUrl, PublishMessage message) async {
    final validationError = message.validationError;
    if (validationError != null) throw PublishException(validationError);

    final topicUri = Uri.parse(topicUrl);
    final parameters = <String, String>{
      'priority': message.priority.toString(),
    };
    final title = message.title?.trim();
    if (title != null && title.isNotEmpty) parameters['title'] = title;
    if (message.tags.isNotEmpty) parameters['tags'] = message.tags.join(',');
    final uri = topicUri.replace(queryParameters: parameters, fragment: null);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.putUrl(uri);
      request.headers.contentType = ContentType.text;
      request.write(message.message);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await response.drain<void>().timeout(const Duration(seconds: 30));
        return;
      }
      final bytes = await response
          .expand((chunk) => chunk)
          .take(64 * 1024)
          .toList()
          .timeout(const Duration(seconds: 30));
      throw PublishException(
        _httpError(
          response.statusCode,
          utf8.decode(bytes, allowMalformed: true),
        ),
      );
    } on PublishException {
      rethrow;
    } on TimeoutException {
      throw const PublishException(
        'The server took too long to respond. Check your connection and try again.',
      );
    } on SocketException {
      throw const PublishException(
        'Could not reach the server. Check your connection and try again.',
      );
    } on HandshakeException {
      throw const PublishException(
        'Could not establish a secure connection. Check the topic URL.',
      );
    } on HttpException {
      throw const PublishException(
        'The network request failed. Check your connection and try again.',
      );
    } finally {
      client.close(force: true);
    }
  }

  String _httpError(int status, String body) {
    if (status == 401 || status == 403) {
      return 'Publishing was denied. Check the topic credentials or access permissions.';
    }
    if (status == 413) {
      return 'Message is too large. Shorten it and try again.';
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        final error = (decoded['error'] as String).trim();
        if (error.isNotEmpty) return error;
      }
    } catch (_) {
      // Fall back to the status below when the response is not JSON.
    }
    return 'Publishing failed (HTTP $status). Please try again.';
  }
}

List<String> parsePublishTags(String value) => value
    .split(',')
    .map((tag) => tag.trim())
    .where((tag) => tag.isNotEmpty)
    .toList(growable: false);
