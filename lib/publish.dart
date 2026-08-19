import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_settings.dart';

class PublishMessage {
  const PublishMessage({
    required this.message,
    this.title,
    this.priority = 3,
    this.tags = const [],
    this.markdown = false,
    this.clickUrl,
    this.email,
    this.delay,
    this.phoneCall,
    this.attachmentUrl,
    this.attachmentFilePath,
    this.attachmentFileName,
  });

  final String message;
  final String? title;
  final int priority;
  final List<String> tags;
  final bool markdown;
  final String? clickUrl;
  final String? email;
  final String? delay;
  final String? phoneCall;
  final String? attachmentUrl;
  final String? attachmentFilePath;
  final String? attachmentFileName;

  String? get validationError {
    if (message.trim().isEmpty) return 'Message is required.';
    if (priority < 1 || priority > 5) {
      return 'Priority must be between 1 and 5.';
    }
    if (attachmentUrl != null && attachmentFilePath != null) {
      return 'Choose either an attachment URL or a local file.';
    }
    for (final entry in [clickUrl, attachmentUrl]) {
      if (entry != null && entry.trim().isNotEmpty) {
        final uri = Uri.tryParse(entry.trim());
        if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
          return 'Enter a complete HTTP or HTTPS URL.';
        }
        if (uri.scheme != 'http' && uri.scheme != 'https') {
          return 'URLs must use HTTP or HTTPS.';
        }
      }
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
  HttpNtfyPublisher({this.profiles});

  static const maxAttachmentBytes = 50 * 1024 * 1024;

  final AppSettingsRepository? profiles;

  @override
  Future<void> publish(String topicUrl, PublishMessage message) async {
    final validationError = message.validationError;
    if (validationError != null) throw PublishException(validationError);

    final topicUri = Uri.parse(topicUrl);
    await profiles?.addLogSafely('Publishing message to ${topicUri.origin}');
    final parameters = <String, String>{
      'priority': message.priority.toString(),
    };
    final title = message.title?.trim();
    if (title != null && title.isNotEmpty) parameters['title'] = title;
    if (message.tags.isNotEmpty) parameters['tags'] = message.tags.join(',');
    if (message.markdown) parameters['markdown'] = 'yes';
    void add(String key, String? value) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        parameters[key] = normalized;
      }
    }

    add('click', message.clickUrl);
    add('email', message.email);
    add('delay', message.delay);
    add('call', message.phoneCall);
    add('attach', message.attachmentUrl);
    final attachmentPath = message.attachmentFilePath;
    File? attachmentFile;
    if (attachmentPath != null) {
      attachmentFile = File(attachmentPath);
      final stat = await attachmentFile.stat();
      if (stat.type != FileSystemEntityType.file) {
        throw const PublishException('The selected attachment is unavailable.');
      }
      if (stat.size > maxAttachmentBytes) {
        throw const PublishException(
          'The selected attachment is larger than 50 MB.',
        );
      }
      parameters['filename'] =
          message.attachmentFileName ?? attachmentFile.uri.pathSegments.last;
      parameters['message'] = message.message.replaceAll('\n', r'\n');
    }
    final uri = topicUri.replace(queryParameters: parameters, fragment: null);
    final profile = await profiles?.profileFor(topicUri);
    final client = HttpClient(context: profile?.securityContext)
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.putUrl(uri);
      profile?.apply(request);
      if (attachmentFile == null) {
        request.headers.contentType = ContentType.text;
        request.write(message.message);
      } else {
        await request.addStream(attachmentFile.openRead());
      }
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await response.drain<void>().timeout(const Duration(seconds: 30));
        await profiles?.addLogSafely('Published message to ${topicUri.origin}');
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
      await profiles?.addLogSafely(
        'Publishing to ${topicUri.origin} was rejected',
      );
      rethrow;
    } on TimeoutException {
      await profiles?.addLogSafely(
        'Publishing to ${topicUri.origin} timed out',
      );
      throw const PublishException(
        'The server took too long to respond. Check your connection and try again.',
      );
    } on SocketException {
      await profiles?.addLogSafely(
        'Publishing to ${topicUri.origin} failed: socket',
      );
      throw const PublishException(
        'Could not reach the server. Check your connection and try again.',
      );
    } on HandshakeException {
      await profiles?.addLogSafely(
        'Publishing to ${topicUri.origin} failed: TLS',
      );
      throw const PublishException(
        'Could not establish a secure connection. Check the topic URL.',
      );
    } on HttpException {
      await profiles?.addLogSafely(
        'Publishing to ${topicUri.origin} failed: HTTP',
      );
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
