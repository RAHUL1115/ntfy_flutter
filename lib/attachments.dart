import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';
import 'messages.dart';
import 'notification_policy.dart';
import 'subscriptions.dart';

class AttachmentException implements Exception {
  const AttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AttachmentService {
  const AttachmentService({
    this.directoryProvider,
    this.openPath,
    this.profiles,
  });

  final Future<Directory> Function()? directoryProvider;
  final Future<bool> Function(String path)? openPath;
  final AppSettingsRepository? profiles;

  Future<Uint8List> fetchBytes(
    Uri uri, {
    int maxBytes = 5 * 1024 * 1024,
  }) async {
    if ((uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw const AttachmentException('The attachment URL is invalid.');
    }
    final profile = await profiles?.profileFor(uri);
    final client = HttpClient(context: profile?.securityContext)
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      profile?.apply(request);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AttachmentException(
          'Attachment download failed (HTTP ${response.statusCode}).',
        );
      }
      if (response.contentLength > maxBytes) {
        throw const AttachmentException(
          'The attachment is larger than the configured download limit.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) {
          throw const AttachmentException(
            'The attachment is larger than the configured download limit.',
          );
        }
      }
      return bytes.takeBytes();
    } on TimeoutException {
      throw const AttachmentException('The attachment download timed out.');
    } on SocketException {
      throw const AttachmentException('Could not download the attachment.');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> download(
    MessageAttachment attachment, {
    void Function(double progress)? onProgress,
    int maxBytes = 50 * 1024 * 1024,
  }) async {
    final uri = Uri.tryParse(attachment.url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const AttachmentException('The attachment URL is invalid.');
    }
    final root =
        await (directoryProvider?.call() ?? getApplicationSupportDirectory());
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}attachments',
    );
    await directory.create(recursive: true);
    final safeName = attachment.name.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}${attachment.url.hashCode}-$safeName',
    );
    final profile = await profiles?.profileFor(uri);
    final client = HttpClient(context: profile?.securityContext)
      ..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      profile?.apply(request);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AttachmentException(
          'Attachment download failed (HTTP ${response.statusCode}).',
        );
      }
      if (response.contentLength > maxBytes) {
        throw const AttachmentException(
          'The attachment is larger than the configured download limit.',
        );
      }
      sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (received > maxBytes) {
          throw const AttachmentException(
            'The attachment is larger than the configured download limit.',
          );
        }
        sink.add(chunk);
        if (response.contentLength > 0) {
          onProgress?.call(received / response.contentLength);
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      return file.path;
    } on TimeoutException {
      throw const AttachmentException('The attachment download timed out.');
    } on SocketException {
      throw const AttachmentException('Could not download the attachment.');
    } finally {
      await sink?.close();
      client.close(force: true);
      if (sink != null && await file.exists()) await file.delete();
    }
  }

  Future<void> open(String path) async {
    if (openPath != null) {
      if (!await openPath!(path)) {
        throw const AttachmentException('No app can open this attachment.');
      }
      return;
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw AttachmentException(result.message);
    }
  }

  Future<bool> exists(String path) => File(path).exists();

  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

class SubscriptionIconService {
  const SubscriptionIconService({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;

  Future<String> save(String sourcePath, int subscriptionId) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const AttachmentException('The selected icon is unavailable.');
    }
    final root =
        await (directoryProvider?.call() ?? getApplicationSupportDirectory());
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}subscription-icons',
    );
    await directory.create(recursive: true);
    final extension = source.uri.pathSegments.last.contains('.')
        ? '.${source.uri.pathSegments.last.split('.').last}'
        : '';
    final destination = File(
      '${directory.path}${Platform.pathSeparator}$subscriptionId$extension',
    );
    await source.copy(destination.path);
    return destination.path;
  }
}

class AttachmentAutoDownloader {
  AttachmentAutoDownloader({
    required this.policies,
    required this.repository,
    AttachmentService? service,
  }) : service = service ?? const AttachmentService();

  final NotificationPolicyRepository policies;
  final AttachmentRepository repository;
  final AttachmentService service;

  Future<StoredMessage> process(
    Subscription subscription,
    StoredMessage message,
  ) async {
    final attachment = message.attachment;
    if (attachment == null || attachment.localPath != null) return message;
    try {
      final policy = await policies.loadNotificationPolicy(
        subscriptionId: subscription.id,
      );
      final limit = policy.attachmentDownloadMaxBytes;
      if (limit == 0) {
        return message;
      }
      if (limit > 1 && attachment.size != null && attachment.size! > limit) {
        return message;
      }
      final path = await service.download(
        attachment,
        maxBytes: limit == 1 ? 50 * 1024 * 1024 : limit,
      );
      await repository.setAttachmentLocalPath(
        message.subscriptionId,
        message.localId,
        path,
      );
      return StoredMessage(
        localId: message.localId,
        subscriptionId: message.subscriptionId,
        eventId: message.eventId,
        time: message.time,
        message: message.message,
        title: message.title,
        priority: message.priority,
        tags: message.tags,
        attachment: MessageAttachment(
          name: attachment.name,
          url: attachment.url,
          type: attachment.type,
          size: attachment.size,
          expires: attachment.expires,
          localPath: path,
        ),
      );
    } catch (_) {
      return message;
    }
  }
}
