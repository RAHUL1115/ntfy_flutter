import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ntfy_flutter/app_settings.dart';
import 'package:ntfy_flutter/publish.dart';
import 'package:ntfy_flutter/topic_feed.dart';

void main() {
  test(
    'appearance, protocol, integration, and backup settings survive restart',
    () async {
      final preferences = _MemoryPreferences();
      final secrets = _MemorySecrets();
      final first = AppSettingsStore(
        preferences: preferences,
        secrets: secrets,
      );
      const expected = AppSettings(
        defaultServer: 'https://example.com',
        languageTag: 'de',
        theme: AppThemePreference.dark,
        accentColor: AppAccentPreference.rose,
        fontScale: AppFontScalePreference.large,
        messageBar: MessageBarPreference.disabled,
        newMessagesAtBottom: true,
        connectionAlertSeconds: 900,
        protocol: ConnectionProtocol.websocket,
        batteryPromptAfterEpochSeconds: 100,
        websocketPromptAfterEpochSeconds: 200,
        exactAlarmPromptAfterEpochSeconds: dismissedSetupPrompt,
        fullScreenAlertsEnabled: true,
        fullScreenAlertTags: ['urgent', 'call'],
        broadcastsEnabled: false,
        unifiedPushEnabled: true,
        recordLogs: true,
        backupMode: BackupMode.settingsOnly,
      );
      await first.saveSettings(expected);

      final reopened = AppSettingsStore(
        preferences: preferences,
        secrets: secrets,
      );
      expect((await reopened.loadSettings()).toJson(), expected.toJson());
    },
  );

  test('legacy dynamic color setting migrates to the accent selector', () {
    final json = const AppSettings().toJson()
      ..remove('accentColor')
      ..['dynamicColors'] = true;
    final migrated = AppSettings.fromJson(json);

    expect(migrated.accentColor, AppAccentPreference.dynamic);
    expect(migrated.fontScale, AppFontScalePreference.large);
  });

  test('legacy extra-large font size returns to the app baseline', () {
    final json = const AppSettings().toJson()..['fontScale'] = 'extraLarge';

    expect(AppSettings.fromJson(json).fontScale, AppFontScalePreference.large);
  });

  test('setup prompts postpone for seven days and dismiss permanently', () {
    final now = DateTime.utc(2026, 8, 21);

    expect(setupPromptDue(0, now), isTrue);
    expect(setupPromptDue(postponeSetupPrompt(now), now), isFalse);
    expect(
      setupPromptDue(
        postponeSetupPrompt(now),
        now.add(const Duration(days: 7)),
      ),
      isTrue,
    );
    expect(setupPromptDue(dismissedSetupPrompt, now), isFalse);
  });

  test(
    'logging is opt-in and keeps only the newest thousand entries',
    () async {
      final store = AppSettingsStore(
        preferences: _MemoryPreferences(),
        secrets: _MemorySecrets(),
      );
      await store.addLog('ignored');
      expect(await store.loadLogs(), isEmpty);
      await store.saveSettings(const AppSettings(recordLogs: true));
      for (var index = 0; index < 1002; index++) {
        await store.addLog('entry-$index');
      }
      final logs = await store.loadLogs();
      expect(logs, hasLength(1000));
      expect(logs.first, contains('entry-2'));
      expect(logs.last, contains('entry-1001'));
    },
  );

  test(
    'credentials and custom header values stay in the secret backend',
    () async {
      final preferences = _MemoryPreferences();
      final secrets = _MemorySecrets();
      final store = AppSettingsStore(
        preferences: preferences,
        secrets: secrets,
      );

      await store.saveAccount(
        const ServerAccount(
          baseUrl: 'https://example.com',
          username: 'rahul',
          password: 'secret',
        ),
      );
      await store.saveHeader(
        const CustomHeader(
          baseUrl: 'https://example.com',
          name: 'X-Project',
          value: 'private-value',
        ),
      );

      expect(preferences.values.toString(), isNot(contains('secret')));
      expect(preferences.values.toString(), isNot(contains('private-value')));
      expect((await store.loadAccounts()).single.password, 'secret');
      expect((await store.loadHeaders()).single.value, 'private-value');
    },
  );

  test('reserved and injection-prone custom headers are rejected', () async {
    final store = AppSettingsStore(
      preferences: _MemoryPreferences(),
      secrets: _MemorySecrets(),
    );

    await expectLater(
      store.saveHeader(
        const CustomHeader(
          baseUrl: 'https://example.com',
          name: 'Authorization',
          value: 'replacement',
        ),
      ),
      throwsFormatException,
    );
    await expectLater(
      store.saveHeader(
        const CustomHeader(
          baseUrl: 'https://example.com',
          name: 'X-Test',
          value: 'valid\r\ninjected: yes',
        ),
      ),
      throwsFormatException,
    );
  });

  test('client certificates cannot be saved without a matching key', () async {
    final store = AppSettingsStore(
      preferences: _MemoryPreferences(),
      secrets: _MemorySecrets(),
    );

    await expectLater(
      store.saveCertificates(
        const CertificateProfile(
          baseUrl: 'https://example.com',
          clientCertificatePath: 'client.pem',
        ),
      ),
      throwsFormatException,
    );
  });

  test('server origins normalize before certificate profile matching', () {
    expect(
      normalizeServerOrigin(' HTTPS://Example.COM/some/path/ '),
      'https://example.com',
    );
  });

  test('deleting a certificate profile removes only managed files', () async {
    final root = await Directory.systemTemp.createTemp('ntfy-certificates-');
    addTearDown(() => root.delete(recursive: true));
    final files = ManagedCertificateFiles(directoryProvider: () async => root);
    final managed = await files.save(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'client.key',
      label: 'client-key',
    );
    final outside = File('${root.path}/keep.txt');
    await outside.writeAsString('keep');
    final preferences = _MemoryPreferences();
    await preferences.setString(
      'certificates-v1',
      jsonEncode([
        {
          'baseUrl': 'https://example.com',
          'clientCertificatePath': outside.path,
          'clientKeyPath': managed,
        },
      ]),
    );
    final store = AppSettingsStore(
      preferences: preferences,
      secrets: _MemorySecrets(),
      certificateFiles: files,
    );

    await store.deleteCertificates('https://example.com');

    expect(await File(managed).exists(), isFalse);
    expect(await outside.exists(), isTrue);
  });

  test(
    'certificate backups exclude private material unless requested',
    () async {
      final root = await Directory.systemTemp.createTemp('ntfy-cert-backup-');
      addTearDown(() => root.delete(recursive: true));
      final files = ManagedCertificateFiles(
        directoryProvider: () async => root,
      );
      final trusted = await files.save(
        bytes: Uint8List.fromList(utf8.encode(_certificate)),
        fileName: 'trusted.pem',
        label: 'trusted',
      );
      final client = await files.save(
        bytes: Uint8List.fromList(utf8.encode(_certificate)),
        fileName: 'client.pem',
        label: 'client',
      );
      final key = await files.save(
        bytes: Uint8List.fromList(utf8.encode(_privateKey)),
        fileName: 'client.key',
        label: 'key',
      );
      final preferences = _MemoryPreferences();
      final secrets = _MemorySecrets();
      final store = AppSettingsStore(
        preferences: preferences,
        secrets: secrets,
        certificateFiles: files,
      );
      await store.saveCertificates(
        CertificateProfile(
          baseUrl: 'https://example.com',
          trustedCertificatePath: trusted,
          clientCertificatePath: client,
          clientKeyPath: key,
          clientKeyPassword: 'key-password',
        ),
      );

      final settingsOnly = (await store.exportCertificateBackup(
        includePrivateKeys: false,
      )).single;
      expect(settingsOnly['trustedCertificate'], isNotNull);
      expect(settingsOnly, isNot(contains('clientCertificate')));
      expect(settingsOnly, isNot(contains('clientKey')));
      expect(settingsOnly.toString(), isNot(contains('key-password')));

      final everything = (await store.exportCertificateBackup(
        includePrivateKeys: true,
      )).single;
      expect(everything['clientCertificate'], isNotNull);
      expect(everything['clientKey'], isNotNull);
      expect(everything['clientKeyPassword'], 'key-password');
    },
  );

  test('certificate restore is transactional when persistence fails', () async {
    final root = await Directory.systemTemp.createTemp('ntfy-cert-restore-');
    addTearDown(() => root.delete(recursive: true));
    final files = ManagedCertificateFiles(directoryProvider: () async => root);
    final preferences = _FailingOncePreferences();
    final secrets = _MemorySecrets();
    final store = AppSettingsStore(
      preferences: preferences,
      secrets: secrets,
      certificateFiles: files,
    );
    preferences.failNextWrite = true;

    await expectLater(
      store.restoreCertificateBackup([
        {
          'baseUrl': 'https://example.com',
          'trustedCertificate': base64Encode(utf8.encode(_certificate)),
          'clientCertificate': base64Encode(utf8.encode(_certificate)),
          'clientKey': base64Encode(utf8.encode(_privateKey)),
        },
      ]),
      throwsStateError,
    );

    expect(await store.loadCertificates(), isEmpty);
    final managedDirectory = Directory('${root.path}/certificates');
    expect(
      managedDirectory.existsSync()
          ? managedDirectory.listSync().whereType<File>()
          : const <FileSystemEntity>[],
      isEmpty,
    );
  });

  test(
    'post-commit cleanup failure keeps restored certificate files',
    () async {
      final root = await Directory.systemTemp.createTemp('ntfy-cert-restore-');
      addTearDown(() => root.delete(recursive: true));
      final store = AppSettingsStore(
        preferences: _MemoryPreferences(),
        secrets: _MemorySecrets(),
        certificateFiles: _FailingDeleteCertificateFiles(
          directoryProvider: () async => root,
        ),
      );

      await store.restoreCertificateBackup([
        {
          'baseUrl': 'https://example.com',
          'trustedCertificate': base64Encode(utf8.encode(_certificate)),
        },
      ]);

      final restored = (await store.loadCertificates()).single;
      expect(await File(restored.trustedCertificatePath!).exists(), isTrue);
    },
  );

  test(
    'foreground publishing applies saved authentication and headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<HttpHeaders>();
      server.listen((request) async {
        received.complete(request.headers);
        await request.drain<void>();
        await request.response.close();
      });
      final baseUrl = 'http://${server.address.host}:${server.port}';
      final store = AppSettingsStore(
        preferences: _MemoryPreferences(),
        secrets: _MemorySecrets(),
      );
      await store.saveAccount(
        ServerAccount(baseUrl: baseUrl, username: 'user', password: 'pass'),
      );
      await store.saveHeader(
        CustomHeader(
          baseUrl: baseUrl,
          name: 'X-Ntfy-Test',
          value: 'configured',
        ),
      );

      await HttpNtfyPublisher(profiles: store)
          .publish('$baseUrl/topic', const PublishMessage(message: 'hello'));
      final headers = await received.future;
      expect(
        headers.value(HttpHeaders.authorizationHeader),
        'Basic ${base64Encode(utf8.encode('user:pass'))}',
      );
      expect(headers.value('X-Ntfy-Test'), 'configured');
    },
  );

  test('WebSocket preference switches the shared stream transport', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add('websocket-line');
      await socket.close();
    });
    final store = AppSettingsStore(
      preferences: _MemoryPreferences(),
      secrets: _MemorySecrets(),
    );
    await store.saveSettings(
      const AppSettings(protocol: ConnectionProtocol.websocket),
    );
    final client = HttpNtfyStreamClient(profiles: store);
    final connection = await client.connect(
      topicUrl: 'http://${server.address.host}:${server.port}/topic',
    );
    addTearDown(connection.close);

    expect(await connection.lines.first, 'websocket-line');
  });
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

class _FailingOncePreferences extends _MemoryPreferences {
  bool failNextWrite = false;

  @override
  Future<bool> setString(String key, String value) async {
    if (failNextWrite) {
      failNextWrite = false;
      return false;
    }
    return super.setString(key, value);
  }
}

class _FailingDeleteCertificateFiles extends ManagedCertificateFiles {
  const _FailingDeleteCertificateFiles({required super.directoryProvider});

  @override
  Future<void> delete(Iterable<String> paths) async {
    throw StateError('cleanup failed');
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

const _certificate = '''-----BEGIN CERTIFICATE-----
MIICjTCCAfYCCQDR1evIEbvoVjANBgkqhkiG9w0BAQUFADCBijELMAkGA1UEBhMC
VVMxEjAQBgNVBAgMCVNvbWV3aGVyZTERMA8GA1UEBwwIU29tZUNpdHkxDTALBgNV
BAoMBENvcnAxETAPBgNVBAsMCFNvZnR3YXJlMRIwEAYDVQQDDAlsb2NhbGhvc3Qx
HjAcBgkqhkiG9w0BCQEWD2FkbWluQGxvY2FsaG9zdDAeFw0xMjA2MDgxOTE0Mzha
Fw0xMjA3MDgxOTE0MzhaMIGKMQswCQYDVQQGEwJVUzESMBAGA1UECAwJU29tZXdo
ZXJlMREwDwYDVQQHDAhTb21lQ2l0eTENMAsGA1UECgwEQ29ycDERMA8GA1UECwwI
U29mdHdhcmUxEjAQBgNVBAMMCWxvY2FsaG9zdDEeMBwGCSqGSIb3DQEJARYPYWRt
aW5AbG9jYWxob3N0MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC/Vj4UCdQI
N0IMCHDWwDo3QyH9I8sBm/OwIiiJbQ0RpyfWCn4ilzZwu98okwUCu5PwlFQZd67a
DooxhFS2FSw4iRZCUGJlgV7BG1JX9q0xqVy33V6rxFFYQYHw6r7FHPaw2FuRCOoi
uDqE+ua6lbV2YP/eXiRnq5hT5vWfEX5rYwIDAQABMA0GCSqGSIb3DQEBBQUAA4GB
ADQFczkmr+91I3id7HH1voh9YKVqA9nh1yYFCkonsDPXBEJIZEyYa9HaWVkcMMgo
F7bJbWKyaYXW818XPXuOmSBI7dmaMtqITEJWsxdcMVKYCOMtjTLwquPki6xXZxNb
y/zubrV+P4XN0Wi0hoDU/0/RNQOuAF1w7UOQsUmn1ihj
-----END CERTIFICATE-----''';

const _privateKey = '''-----BEGIN RSA PRIVATE KEY-----
MIICXQIBAAKBgQC/Vj4UCdQIN0IMCHDWwDo3QyH9I8sBm/OwIiiJbQ0RpyfWCn4i
lzZwu98okwUCu5PwlFQZd67aDooxhFS2FSw4iRZCUGJlgV7BG1JX9q0xqVy33V6r
xFFYQYHw6r7FHPaw2FuRCOoiuDqE+ua6lbV2YP/eXiRnq5hT5vWfEX5rYwIDAQAB
AoGAaL5oq4WZ2omNkZLJWvbOp9QLdk2y44WhSOnaMSlOvzw3tZf25y7KcbqXdtnN
I2rWmRxKUcrQILVW97aOvUMn+jOCN6+IY1kiT6Un4H1Ow+rVj3CDvCjBCZhfkExK
osTzpwbiRyHueWOLOB3RZUNXC+5OfTBVoYgQp85INykwUHECQQD10XsOKDtkuCh4
yNf68lXC7TUSPAwAjX+I4xJ1UWMO5DWBpuyuA2GSlYHWZg4ae0xm9zUijb6A5WDW
aVTvi9S5AkEAx0MSU2qD837lXAjkcyBS9WqtoJebC263uUaiQ8WZQhDE+R8aeXj+
e80hY8FOc6WogC2VbQgYO52t82KWLDKq+wJAS+2Xl+jfZ53mimBnLhE6YkpIsUgw
4N7T/OE+q1QnR8s/p7t6sclDkzZw81t0kcNx9v/2vqSPqlqvjardXFyRqQJBAIAW
jWExx0BvAeD3lmKrFKjNum7RBcmDknZ3ATevfaUKQpQhelM7g9rxMdV+HYAZrQc4
RiWgXnN0GK2rYf1nVKECQQCo5UHoukW89+UX/SbamoMeUZJxL3bQAqv71B59C6cy
NQuDZlHOqDajyxaX2y8tJWgk3ciGXlIqByHQFXb2Rhuw
-----END RSA PRIVATE KEY-----''';
