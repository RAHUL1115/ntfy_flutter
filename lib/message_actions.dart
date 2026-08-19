import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_settings.dart';
import 'messages.dart';

const _actionChannelName = 'com.rahul1115.ntfy_flutter/message_notifications';

class MessageActionException implements Exception {
  const MessageActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class MessageActionPlatform {
  Future<bool> open(Uri uri);
  Future<void> broadcast(String? intent, Map<String, String> extras);
}

class AndroidMessageActionPlatform implements MessageActionPlatform {
  const AndroidMessageActionPlatform();

  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Future<void> broadcast(String? intent, Map<String, String> extras) =>
      const MethodChannel(
        _actionChannelName,
      ).invokeMethod('broadcastAction', {'intent': intent, 'extras': extras});
}

class MessageActionExecutor {
  const MessageActionExecutor({
    this.settings,
    this.platform = const AndroidMessageActionPlatform(),
  });

  final AppSettingsRepository? settings;
  final MessageActionPlatform platform;

  Future<void> openClick(String value) async {
    final uri = _safeViewUri(value);
    if (uri == null || !await platform.open(uri)) {
      throw const MessageActionException('Could not open this link.');
    }
  }

  Future<void> execute(MessageAction action) async {
    switch (action.action.toLowerCase()) {
      case 'view':
        final url = action.url;
        if (url == null) {
          throw const MessageActionException('This action has no link.');
        }
        await openClick(url);
        return;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: action.value ?? ''));
        return;
      case 'broadcast':
        await platform.broadcast(action.intent, action.extras);
        return;
      case 'http':
        await _http(action);
        return;
      default:
        throw MessageActionException('Unsupported action: ${action.action}.');
    }
  }

  Future<void> _http(MessageAction action) async {
    final uri = Uri.tryParse(action.url ?? '');
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const MessageActionException('This action has an invalid URL.');
    }
    final method = (action.method ?? 'POST').toUpperCase();
    if (!RegExp(r'^[A-Z]{1,16}$').hasMatch(method)) {
      throw const MessageActionException('This action has an invalid method.');
    }
    final profile = await settings?.profileFor(uri);
    final client = HttpClient(context: profile?.securityContext);
    try {
      final request = await client.openUrl(method, uri);
      profile?.apply(request);
      for (final entry in action.headers.entries) {
        if (entry.key.contains(RegExp(r'[\r\n]')) ||
            entry.value.contains(RegExp(r'[\r\n]'))) {
          throw const MessageActionException(
            'This action contains an invalid header.',
          );
        }
        request.headers.set(entry.key, entry.value);
      }
      if (action.body != null) request.write(action.body);
      final response = await request.close();
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MessageActionException(
          'Action failed with HTTP ${response.statusCode}.',
        );
      }
    } on MessageActionException {
      rethrow;
    } catch (_) {
      throw const MessageActionException('Could not run this action.');
    } finally {
      client.close(force: true);
    }
  }
}

Uri? _safeViewUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const {
        'http',
        'https',
        'mailto',
        'tel',
        'geo',
        'market',
      }.contains(uri.scheme.toLowerCase())) {
    return null;
  }
  return uri;
}
