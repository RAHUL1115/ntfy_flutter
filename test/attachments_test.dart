import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/app_settings.dart';
import 'package:ntfy_flutter/attachments.dart';
import 'package:ntfy_flutter/messages.dart';
import 'package:ntfy_flutter/notification_policy.dart';
import 'package:ntfy_flutter/subscriptions.dart';

void main() {
  test(
    'downloads an attachment with progress and opens the local file',
    () async {
      final root = await Directory.systemTemp.createTemp('ntfy-attachment-');
      addTearDown(() => root.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response
          ..contentLength = 5
          ..add([1, 2, 3, 4, 5])
          ..close();
      });
      String? opened;
      final progress = <double>[];
      final service = AttachmentService(
        directoryProvider: () async => root,
        openPath: (path) async {
          opened = path;
          return true;
        },
      );
      final path = await service.download(
        MessageAttachment(
          name: 'report.txt',
          url: 'http://${server.address.host}:${server.port}/file',
        ),
        onProgress: progress.add,
      );

      expect(await File(path).readAsBytes(), [1, 2, 3, 4, 5]);
      expect(progress.last, 1);
      await service.open(path);
      expect(opened, path);
    },
  );

  test('rejects an attachment larger than the managed limit', () async {
    final root = await Directory.systemTemp.createTemp('ntfy-attachment-');
    addTearDown(() => root.delete(recursive: true));
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((socket) {
      socket.listen((_) {
        socket.write(
          'HTTP/1.1 200 OK\r\nContent-Length: ${51 * 1024 * 1024}\r\n\r\n',
        );
      });
    });
    final service = AttachmentService(directoryProvider: () async => root);

    expect(
      () => service.download(
        MessageAttachment(
          name: 'large.bin',
          url: 'http://${server.address.host}:${server.port}/file',
        ),
      ),
      throwsA(isA<AttachmentException>()),
    );
  });

  test('remote bytes apply saved authentication and custom headers', () async {
    final root = await Directory.systemTemp.createTemp('ntfy-auth-file-');
    addTearDown(() => root.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = Completer<HttpHeaders>();
    server.listen((request) {
      received.complete(request.headers);
      request.response
        ..write('content')
        ..close();
    });
    final baseUrl = 'http://${server.address.host}:${server.port}';
    final settings = AppSettingsStore(
      preferences: _MemoryPreferences(),
      secrets: _MemorySecrets(),
    );
    await settings.saveAccount(
      ServerAccount(baseUrl: baseUrl, username: 'user', password: 'pass'),
    );
    await settings.saveHeader(
      CustomHeader(baseUrl: baseUrl, name: 'X-Ntfy-Test', value: 'configured'),
    );
    final service = AttachmentService(
      directoryProvider: () async => root,
      profiles: settings,
    );

    final bytes = await service.fetchBytes(Uri.parse('$baseUrl/icon.png'));

    final headers = await received.future;
    expect(utf8.decode(bytes), 'content');
    expect(
      headers.value(HttpHeaders.authorizationHeader),
      'Basic ${base64Encode(utf8.encode('user:pass'))}',
    );
    expect(headers.value('X-Ntfy-Test'), 'configured');
  });

  test('authenticated attachment requests do not follow redirects', () async {
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => target.close(force: true));
    var targetRequests = 0;
    target.listen((request) {
      targetRequests++;
      request.response.close();
    });
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => source.close(force: true));
    source.listen((request) {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://${target.address.host}:${target.port}/leak',
        )
        ..close();
    });
    final baseUrl = 'http://${source.address.host}:${source.port}';
    final settings = AppSettingsStore(
      preferences: _MemoryPreferences(),
      secrets: _MemorySecrets(),
    );
    await settings.saveAccount(
      ServerAccount(baseUrl: baseUrl, username: 'user', password: 'pass'),
    );

    await expectLater(
      AttachmentService(profiles: settings)
          .fetchBytes(Uri.parse('$baseUrl/file')),
      throwsA(isA<AttachmentException>()),
    );
    expect(targetRequests, 0);
  });

  test(
    'auto-download respects size policy and persists the local path',
    () async {
      final root = await Directory.systemTemp.createTemp('ntfy-auto-file-');
      addTearDown(() => root.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var requests = 0;
      server.listen((request) {
        requests++;
        request.response
          ..write('content')
          ..close();
      });
      final repository = _AttachmentRepository();
      final policies = _PolicyRepository(
        const NotificationPolicy(attachmentDownloadMaxBytes: 102400),
      );
      final message = StoredMessage(
        localId: 3,
        subscriptionId: 7,
        eventId: 'attachment',
        time: DateTime.utc(2026),
        message: 'Report',
        attachment: MessageAttachment(
          name: 'report.txt',
          url: 'http://${server.address.host}:${server.port}/file',
          size: 102401,
        ),
      );
      const subscription = Subscription(id: 7, url: 'https://ntfy.sh/files');
      final downloader = AttachmentAutoDownloader(
        policies: policies,
        repository: repository,
        service: AttachmentService(directoryProvider: () async => root),
      );

      expect(
        (await downloader.process(subscription, message)).attachment!.localPath,
        isNull,
      );
      expect(requests, 0);

      policies.policy = const NotificationPolicy(attachmentDownloadMaxBytes: 1);
      final downloaded = await downloader.process(subscription, message);
      expect(downloaded.attachment!.localPath, isNotNull);
      expect(repository.localPath, downloaded.attachment!.localPath);
      expect(requests, 1);
    },
  );
}

class _PolicyRepository implements NotificationPolicyRepository {
  _PolicyRepository(this.policy);

  NotificationPolicy policy;

  @override
  Future<NotificationPolicy> loadNotificationPolicy({
    int? subscriptionId,
  }) async => policy;

  @override
  Future<void> setGlobalNotificationPolicy(NotificationPolicy policy) async {}

  @override
  Future<void> setTopicNotificationPolicy(
    int subscriptionId,
    NotificationPolicy? policy,
  ) async {}
}

class _AttachmentRepository implements AttachmentRepository {
  String? localPath;

  @override
  Future<void> setAttachmentLocalPath(
    int subscriptionId,
    int localId,
    String localPath,
  ) async {
    this.localPath = localPath;
  }
}

class _MemoryPreferences implements PreferencesBackend {
  final values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }
}

class _MemorySecrets implements SecretBackend {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
