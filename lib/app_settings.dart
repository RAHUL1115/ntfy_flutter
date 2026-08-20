import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

enum AppThemePreference { system, light, dark }

enum AppAccentPreference { ntfyTeal, dynamic, blue, violet, rose, orange }

enum AppFontScalePreference { system, small, standard, large }

double? appFontScaleFactor(AppFontScalePreference preference) =>
    switch (preference) {
      AppFontScalePreference.system => null,
      AppFontScalePreference.small => 0.9,
      AppFontScalePreference.standard => 1.15,
      AppFontScalePreference.large => 1.3,
    };

enum ConnectionProtocol { http, websocket }

enum MessageBarPreference { enabled, disabled }

enum BackupMode { everything, everythingNoUsers, settingsOnly }

const supportedAppLanguages = <(String, String)>[
  ('en', 'English'),
  ('bg', 'Български'),
  ('ca', 'Català'),
  ('cs', 'Čeština'),
  ('de', 'Deutsch'),
  ('es', 'Español'),
  ('et', 'Eesti'),
  ('fi', 'Suomi'),
  ('fr', 'Français'),
  ('gl', 'Galego'),
  ('in', 'Bahasa Indonesia'),
  ('it', 'Italiano'),
  ('iw', 'עברית'),
  ('ja', '日本語'),
  ('ko', '한국어'),
  ('nb-NO', 'Norsk bokmål'),
  ('nl', 'Nederlands'),
  ('pl', 'Polski'),
  ('pt', 'Português'),
  ('pt-BR', 'Português (Brasil)'),
  ('ro', 'Română'),
  ('ru', 'Русский'),
  ('sk', 'Slovenčina'),
  ('sv', 'Svenska'),
  ('ta', 'தமிழ்'),
  ('tr', 'Türkçe'),
  ('uk', 'Українська'),
  ('uz', 'Oʻzbekcha'),
  ('vi', 'Tiếng Việt'),
  ('zh-CN', '简体中文'),
  ('zh-TW', '繁體中文'),
];

class AppSettings {
  const AppSettings({
    this.defaultServer = 'https://ntfy.sh',
    this.languageTag = 'system',
    this.theme = AppThemePreference.system,
    AppAccentPreference accentColor = AppAccentPreference.ntfyTeal,
    bool? dynamicColors,
    this.fontScale = AppFontScalePreference.standard,
    this.messageBar = MessageBarPreference.enabled,
    this.newMessagesAtBottom = false,
    this.connectionAlertSeconds = 0,
    this.protocol = ConnectionProtocol.http,
    this.batteryPromptAfterEpochSeconds = 0,
    this.websocketPromptAfterEpochSeconds = 0,
    this.exactAlarmPromptAfterEpochSeconds = 0,
    this.fullScreenAlertsEnabled = false,
    this.fullScreenAlertTags = const [],
    this.broadcastsEnabled = true,
    this.unifiedPushEnabled = false,
    this.recordLogs = false,
    this.backupMode = BackupMode.everything,
  }) : accentColor = dynamicColors == true
           ? AppAccentPreference.dynamic
           : accentColor;

  final String defaultServer;
  final String languageTag;
  final AppThemePreference theme;
  final AppAccentPreference accentColor;
  bool get dynamicColors => accentColor == AppAccentPreference.dynamic;
  final AppFontScalePreference fontScale;
  final MessageBarPreference messageBar;
  final bool newMessagesAtBottom;
  final int connectionAlertSeconds;
  final ConnectionProtocol protocol;
  final int batteryPromptAfterEpochSeconds;
  final int websocketPromptAfterEpochSeconds;
  final int exactAlarmPromptAfterEpochSeconds;
  final bool fullScreenAlertsEnabled;
  final List<String> fullScreenAlertTags;
  final bool broadcastsEnabled;
  final bool unifiedPushEnabled;
  final bool recordLogs;
  final BackupMode backupMode;

  AppSettings copyWith({
    String? defaultServer,
    String? languageTag,
    AppThemePreference? theme,
    bool? dynamicColors,
    AppAccentPreference? accentColor,
    AppFontScalePreference? fontScale,
    MessageBarPreference? messageBar,
    bool? newMessagesAtBottom,
    int? connectionAlertSeconds,
    ConnectionProtocol? protocol,
    int? batteryPromptAfterEpochSeconds,
    int? websocketPromptAfterEpochSeconds,
    int? exactAlarmPromptAfterEpochSeconds,
    bool? fullScreenAlertsEnabled,
    List<String>? fullScreenAlertTags,
    bool? broadcastsEnabled,
    bool? unifiedPushEnabled,
    bool? recordLogs,
    BackupMode? backupMode,
  }) => AppSettings(
    defaultServer: defaultServer ?? this.defaultServer,
    languageTag: languageTag ?? this.languageTag,
    theme: theme ?? this.theme,
    accentColor: dynamicColors == null
        ? accentColor ?? this.accentColor
        : dynamicColors
        ? AppAccentPreference.dynamic
        : AppAccentPreference.ntfyTeal,
    fontScale: fontScale ?? this.fontScale,
    messageBar: messageBar ?? this.messageBar,
    newMessagesAtBottom: newMessagesAtBottom ?? this.newMessagesAtBottom,
    connectionAlertSeconds:
        connectionAlertSeconds ?? this.connectionAlertSeconds,
    protocol: protocol ?? this.protocol,
    batteryPromptAfterEpochSeconds:
        batteryPromptAfterEpochSeconds ?? this.batteryPromptAfterEpochSeconds,
    websocketPromptAfterEpochSeconds:
        websocketPromptAfterEpochSeconds ??
        this.websocketPromptAfterEpochSeconds,
    exactAlarmPromptAfterEpochSeconds:
        exactAlarmPromptAfterEpochSeconds ??
        this.exactAlarmPromptAfterEpochSeconds,
    fullScreenAlertsEnabled:
        fullScreenAlertsEnabled ?? this.fullScreenAlertsEnabled,
    fullScreenAlertTags: fullScreenAlertTags ?? this.fullScreenAlertTags,
    broadcastsEnabled: broadcastsEnabled ?? this.broadcastsEnabled,
    unifiedPushEnabled: unifiedPushEnabled ?? this.unifiedPushEnabled,
    recordLogs: recordLogs ?? this.recordLogs,
    backupMode: backupMode ?? this.backupMode,
  );

  Map<String, Object> toJson() => {
    'defaultServer': defaultServer,
    'languageTag': languageTag,
    'theme': theme.name,
    'dynamicColors': dynamicColors,
    'accentColor': accentColor.name,
    'fontScale': fontScale.name,
    'messageBar': messageBar.name,
    'newMessagesAtBottom': newMessagesAtBottom,
    'connectionAlertSeconds': connectionAlertSeconds,
    'protocol': protocol.name,
    'batteryPromptAfterEpochSeconds': batteryPromptAfterEpochSeconds,
    'websocketPromptAfterEpochSeconds': websocketPromptAfterEpochSeconds,
    'exactAlarmPromptAfterEpochSeconds': exactAlarmPromptAfterEpochSeconds,
    'fullScreenAlertsEnabled': fullScreenAlertsEnabled,
    'fullScreenAlertTags': fullScreenAlertTags,
    'broadcastsEnabled': broadcastsEnabled,
    'unifiedPushEnabled': unifiedPushEnabled,
    'recordLogs': recordLogs,
    'backupMode': backupMode.name,
  };

  static AppSettings fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid app settings.');
    T enumValue<T extends Enum>(List<T> values, String key, T fallback) {
      final name = value[key];
      return name is String
          ? values.where((item) => item.name == name).firstOrNull ?? fallback
          : fallback;
    }

    final server = value['defaultServer'];
    if (server is! String || !_isServerUrl(server)) {
      throw const FormatException('Invalid default server.');
    }
    return AppSettings(
      defaultServer: server,
      languageTag: value['languageTag'] as String? ?? 'system',
      theme: enumValue(
        AppThemePreference.values,
        'theme',
        AppThemePreference.system,
      ),
      accentColor: enumValue(
        AppAccentPreference.values,
        'accentColor',
        value['dynamicColors'] == true
            ? AppAccentPreference.dynamic
            : AppAccentPreference.ntfyTeal,
      ),
      fontScale: value['fontScale'] == 'extraLarge'
          ? AppFontScalePreference.large
          : enumValue(
              AppFontScalePreference.values,
              'fontScale',
              AppFontScalePreference.standard,
            ),
      messageBar: enumValue(
        MessageBarPreference.values,
        'messageBar',
        MessageBarPreference.enabled,
      ),
      newMessagesAtBottom: value['newMessagesAtBottom'] as bool? ?? false,
      connectionAlertSeconds: value['connectionAlertSeconds'] as int? ?? 0,
      protocol: enumValue(
        ConnectionProtocol.values,
        'protocol',
        ConnectionProtocol.http,
      ),
      batteryPromptAfterEpochSeconds:
          value['batteryPromptAfterEpochSeconds'] as int? ?? 0,
      websocketPromptAfterEpochSeconds:
          value['websocketPromptAfterEpochSeconds'] as int? ?? 0,
      exactAlarmPromptAfterEpochSeconds:
          value['exactAlarmPromptAfterEpochSeconds'] as int? ?? 0,
      fullScreenAlertsEnabled:
          value['fullScreenAlertsEnabled'] as bool? ?? false,
      fullScreenAlertTags: switch (value['fullScreenAlertTags']) {
        final List tags => tags.whereType<String>().toList(growable: false),
        _ => const [],
      },
      broadcastsEnabled: value['broadcastsEnabled'] as bool? ?? true,
      unifiedPushEnabled: value['unifiedPushEnabled'] as bool? ?? false,
      recordLogs: value['recordLogs'] as bool? ?? false,
      backupMode: enumValue(
        BackupMode.values,
        'backupMode',
        BackupMode.everything,
      ),
    );
  }
}

class ServerAccount {
  const ServerAccount({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  final String baseUrl;
  final String username;
  final String password;
}

class CustomHeader {
  const CustomHeader({
    required this.baseUrl,
    required this.name,
    required this.value,
  });

  final String baseUrl;
  final String name;
  final String value;
}

class CertificateProfile {
  const CertificateProfile({
    required this.baseUrl,
    this.trustedCertificatePath,
    this.clientCertificatePath,
    this.clientKeyPath,
    this.clientKeyPassword,
  });

  final String baseUrl;
  final String? trustedCertificatePath;
  final String? clientCertificatePath;
  final String? clientKeyPath;
  final String? clientKeyPassword;
}

class ConnectionProfile {
  const ConnectionProfile({
    required this.protocol,
    this.account,
    this.headers = const [],
    this.securityContext,
  });

  final ConnectionProtocol protocol;
  final ServerAccount? account;
  final List<CustomHeader> headers;
  final SecurityContext? securityContext;

  void apply(HttpClientRequest request) {
    final account = this.account;
    if (account != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64Encode(utf8.encode('${account.username}:${account.password}'))}',
      );
    }
    for (final header in headers) {
      request.headers.set(header.name, header.value);
    }
  }
}

abstract interface class AppSettingsRepository {
  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);
  Future<List<ServerAccount>> loadAccounts();
  Future<void> saveAccount(ServerAccount account);
  Future<void> deleteAccount(String baseUrl);
  Future<List<CustomHeader>> loadHeaders();
  Future<void> saveHeader(CustomHeader header);
  Future<void> deleteHeader(String baseUrl, String name);
  Future<List<CertificateProfile>> loadCertificates();
  Future<void> saveCertificates(CertificateProfile profile);
  Future<void> deleteCertificates(String baseUrl);
  Future<ConnectionProfile> profileFor(Uri uri);
  Future<List<String>> loadLogs();
  Future<void> addLog(String message);
  Future<void> clearLogs();
}

abstract interface class CertificateBackupRepository {
  Future<List<Map<String, Object?>>> exportCertificateBackup({
    required bool includePrivateKeys,
  });

  Future<void> restoreCertificateBackup(Object? value);
}

extension AppSettingsLogging on AppSettingsRepository {
  Future<void> addLogSafely(String message) async {
    try {
      await addLog(message);
    } catch (_) {
      // Logging must never change notification delivery or publishing.
    }
  }
}

abstract interface class PreferencesBackend {
  String? getString(String key);
  Future<bool> setString(String key, String value);
}

abstract interface class SecretBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class AppSettingsStore
    implements AppSettingsRepository, CertificateBackupRepository {
  AppSettingsStore({
    required this.preferences,
    required this.secrets,
    this.certificateFiles = const ManagedCertificateFiles(),
  });

  final PreferencesBackend preferences;
  final SecretBackend secrets;
  final ManagedCertificateFiles certificateFiles;

  static const _settingsKey = 'app-settings-v1';
  static const _accountsKey = 'accounts-v1';
  static const _headersKey = 'headers-v1';
  static const _certificatesKey = 'certificates-v1';
  static const _logsKey = 'logs-v1';

  static Future<AppSettingsStore> open() async => AppSettingsStore(
    preferences: SharedPreferencesBackend(
      await SharedPreferences.getInstance(),
    ),
    secrets: const FlutterSecretBackend(FlutterSecureStorage()),
  );

  @override
  Future<AppSettings> loadSettings() async {
    final saved = preferences.getString(_settingsKey);
    return saved == null
        ? const AppSettings()
        : AppSettings.fromJson(jsonDecode(saved));
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    await preferences.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  @override
  Future<List<ServerAccount>> loadAccounts() async {
    final metadata = _jsonList(_accountsKey);
    final accounts = <ServerAccount>[];
    for (final item in metadata) {
      final baseUrl = item['baseUrl'];
      final username = item['username'];
      if (baseUrl is! String || username is! String) continue;
      final password = await secrets.read(_secretKey('account', baseUrl));
      if (password != null) {
        accounts.add(
          ServerAccount(
            baseUrl: baseUrl,
            username: username,
            password: password,
          ),
        );
      }
    }
    return accounts;
  }

  @override
  Future<void> saveAccount(ServerAccount account) async {
    final baseUrl = normalizeServerOrigin(account.baseUrl);
    final metadata = _jsonList(_accountsKey)
      ..removeWhere((item) => item['baseUrl'] == baseUrl)
      ..add({'baseUrl': baseUrl, 'username': account.username});
    await secrets.write(_secretKey('account', baseUrl), account.password);
    await _saveJsonList(_accountsKey, metadata);
  }

  @override
  Future<void> deleteAccount(String baseUrl) async {
    final normalized = normalizeServerOrigin(baseUrl);
    final metadata = _jsonList(_accountsKey)
      ..removeWhere((item) => item['baseUrl'] == normalized);
    await secrets.delete(_secretKey('account', normalized));
    await _saveJsonList(_accountsKey, metadata);
  }

  @override
  Future<List<CustomHeader>> loadHeaders() async {
    final metadata = _jsonList(_headersKey);
    final headers = <CustomHeader>[];
    for (final item in metadata) {
      final baseUrl = item['baseUrl'];
      final name = item['name'];
      if (baseUrl is! String || name is! String) continue;
      final value = await secrets.read(_secretKey('header', '$baseUrl\n$name'));
      if (value != null) {
        headers.add(CustomHeader(baseUrl: baseUrl, name: name, value: value));
      }
    }
    return headers;
  }

  @override
  Future<void> saveHeader(CustomHeader header) async {
    final baseUrl = normalizeServerOrigin(header.baseUrl);
    final name = header.name.trim();
    if (!_validHeaderName(name) || _reservedHeader(name)) {
      throw const FormatException('This HTTP header cannot be customized.');
    }
    if (header.value.contains('\r') || header.value.contains('\n')) {
      throw const FormatException('Header values cannot contain new lines.');
    }
    final metadata = _jsonList(_headersKey)
      ..removeWhere(
        (item) => item['baseUrl'] == baseUrl && item['name'] == name,
      )
      ..add({'baseUrl': baseUrl, 'name': name});
    await secrets.write(_secretKey('header', '$baseUrl\n$name'), header.value);
    await _saveJsonList(_headersKey, metadata);
  }

  @override
  Future<void> deleteHeader(String baseUrl, String name) async {
    final normalized = normalizeServerOrigin(baseUrl);
    final metadata = _jsonList(_headersKey)
      ..removeWhere(
        (item) => item['baseUrl'] == normalized && item['name'] == name,
      );
    await secrets.delete(_secretKey('header', '$normalized\n$name'));
    await _saveJsonList(_headersKey, metadata);
  }

  @override
  Future<List<CertificateProfile>> loadCertificates() async {
    final metadata = _jsonList(_certificatesKey);
    final profiles = <CertificateProfile>[];
    for (final item in metadata) {
      final baseUrl = item['baseUrl'];
      if (baseUrl is! String) continue;
      profiles.add(
        CertificateProfile(
          baseUrl: baseUrl,
          trustedCertificatePath: item['trustedCertificatePath'] as String?,
          clientCertificatePath: item['clientCertificatePath'] as String?,
          clientKeyPath: item['clientKeyPath'] as String?,
          clientKeyPassword: await secrets.read(_secretKey('cert', baseUrl)),
        ),
      );
    }
    return profiles;
  }

  @override
  Future<void> saveCertificates(CertificateProfile profile) async {
    final baseUrl = normalizeServerOrigin(profile.baseUrl);
    if ((profile.clientCertificatePath == null) !=
        (profile.clientKeyPath == null)) {
      throw const FormatException(
        'A client certificate and private key must be selected together.',
      );
    }
    _createSecurityContext(profile);
    final metadata = _jsonList(_certificatesKey);
    final replacedPaths = metadata
        .where((item) => item['baseUrl'] == baseUrl)
        .expand(_certificatePaths)
        .toSet();
    metadata
      ..removeWhere((item) => item['baseUrl'] == baseUrl)
      ..add({
        'baseUrl': baseUrl,
        'trustedCertificatePath': profile.trustedCertificatePath,
        'clientCertificatePath': profile.clientCertificatePath,
        'clientKeyPath': profile.clientKeyPath,
      });
    final password = profile.clientKeyPassword;
    if (password == null) {
      await secrets.delete(_secretKey('cert', baseUrl));
    } else {
      await secrets.write(_secretKey('cert', baseUrl), password);
    }
    await _saveJsonList(_certificatesKey, metadata);
    final retainedPaths = {
      profile.trustedCertificatePath,
      profile.clientCertificatePath,
      profile.clientKeyPath,
    }.whereType<String>();
    await certificateFiles.delete(
      replacedPaths.difference(retainedPaths.toSet()),
    );
  }

  @override
  Future<void> deleteCertificates(String baseUrl) async {
    final normalized = normalizeServerOrigin(baseUrl);
    final metadata = _jsonList(_certificatesKey);
    final removedPaths = metadata
        .where((item) => item['baseUrl'] == normalized)
        .expand(_certificatePaths)
        .toSet();
    metadata.removeWhere((item) => item['baseUrl'] == normalized);
    await secrets.delete(_secretKey('cert', normalized));
    await _saveJsonList(_certificatesKey, metadata);
    await certificateFiles.delete(removedPaths);
  }

  @override
  Future<List<Map<String, Object?>>> exportCertificateBackup({
    required bool includePrivateKeys,
  }) async {
    final result = <Map<String, Object?>>[];
    for (final profile in await loadCertificates()) {
      Future<String?> read(String? path) async =>
          path == null ? null : base64Encode(await File(path).readAsBytes());
      result.add({
        'baseUrl': profile.baseUrl,
        'trustedCertificate': await read(profile.trustedCertificatePath),
        if (includePrivateKeys) ...{
          'clientCertificate': await read(profile.clientCertificatePath),
          'clientKey': await read(profile.clientKeyPath),
          'clientKeyPassword': profile.clientKeyPassword,
        },
      });
    }
    return result;
  }

  @override
  Future<void> restoreCertificateBackup(Object? value) async {
    if (value == null) return;
    if (value is! List) {
      throw const FormatException('Invalid certificates in backup.');
    }
    final staged = <CertificateProfile>[];
    final stagedPaths = <String>[];
    try {
      for (final item in value) {
        if (item is! Map || item['baseUrl'] is! String) {
          throw const FormatException('Invalid certificate in backup.');
        }
        final baseUrl = normalizeServerOrigin(item['baseUrl']! as String);
        Future<String?> stage(String key, String label) async {
          final encoded = item[key];
          if (encoded == null) return null;
          if (encoded is! String) {
            throw const FormatException('Invalid certificate in backup.');
          }
          final bytes = base64Decode(encoded);
          final path = await certificateFiles.save(
            bytes: Uint8List.fromList(bytes),
            fileName: '$label.pem',
            label: '$baseUrl-$label',
          );
          stagedPaths.add(path);
          return path;
        }

        final profile = CertificateProfile(
          baseUrl: baseUrl,
          trustedCertificatePath: await stage('trustedCertificate', 'trusted'),
          clientCertificatePath: await stage(
            'clientCertificate',
            'client-certificate',
          ),
          clientKeyPath: await stage('clientKey', 'client-key'),
          clientKeyPassword: item['clientKeyPassword'] as String?,
        );
        if ((profile.clientCertificatePath == null) !=
            (profile.clientKeyPath == null)) {
          throw const FormatException(
            'A restored client certificate must include its private key.',
          );
        }
        _createSecurityContext(profile);
        staged.add(profile);
      }

      final previousRaw = preferences.getString(_certificatesKey);
      final metadata = _jsonList(_certificatesKey);
      final replacedPaths = <String>{};
      final previousPasswords = <String, String?>{};
      for (final profile in staged) {
        previousPasswords[profile.baseUrl] = await secrets.read(
          _secretKey('cert', profile.baseUrl),
        );
        replacedPaths.addAll(
          metadata
              .where((item) => item['baseUrl'] == profile.baseUrl)
              .expand(_certificatePaths),
        );
        metadata
          ..removeWhere((item) => item['baseUrl'] == profile.baseUrl)
          ..add({
            'baseUrl': profile.baseUrl,
            'trustedCertificatePath': profile.trustedCertificatePath,
            'clientCertificatePath': profile.clientCertificatePath,
            'clientKeyPath': profile.clientKeyPath,
          });
      }
      try {
        for (final profile in staged) {
          final password = profile.clientKeyPassword;
          if (password == null) {
            await secrets.delete(_secretKey('cert', profile.baseUrl));
          } else {
            await secrets.write(_secretKey('cert', profile.baseUrl), password);
          }
        }
        await _saveJsonList(_certificatesKey, metadata);
      } catch (_) {
        final restored = await preferences.setString(
          _certificatesKey,
          previousRaw ?? '[]',
        );
        if (!restored) throw StateError('Could not roll back certificates.');
        for (final entry in previousPasswords.entries) {
          final key = _secretKey('cert', entry.key);
          if (entry.value == null) {
            await secrets.delete(key);
          } else {
            await secrets.write(key, entry.value!);
          }
        }
        rethrow;
      }
      try {
        await certificateFiles.delete(replacedPaths);
      } catch (_) {
        // The restored metadata already points at the staged files. Cleanup of
        // replaced files is best-effort after that commit.
      }
    } catch (_) {
      await certificateFiles.delete(stagedPaths);
      rethrow;
    }
  }

  @override
  Future<ConnectionProfile> profileFor(Uri uri) async {
    final baseUrl = _origin(uri);
    final account = (await loadAccounts())
        .where((item) => item.baseUrl == baseUrl)
        .firstOrNull;
    final headers = (await loadHeaders())
        .where((item) => item.baseUrl == baseUrl)
        .toList(growable: false);
    final certificate = (await loadCertificates())
        .where((item) => item.baseUrl == baseUrl)
        .firstOrNull;
    final context = certificate == null
        ? null
        : _createSecurityContext(certificate);
    return ConnectionProfile(
      protocol: (await loadSettings()).protocol,
      account: account,
      headers: headers,
      securityContext: context,
    );
  }

  @override
  Future<List<String>> loadLogs() async {
    final raw = preferences.getString(_logsKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List || !decoded.every((item) => item is String)) {
      throw const FormatException('Invalid log data.');
    }
    return decoded.cast<String>();
  }

  @override
  Future<void> addLog(String message) async {
    if (!(await loadSettings()).recordLogs) return;
    final logs = await loadLogs()
      ..add('${DateTime.now().toUtc().toIso8601String()} $message');
    if (logs.length > 1000) logs.removeRange(0, logs.length - 1000);
    await preferences.setString(_logsKey, jsonEncode(logs));
  }

  @override
  Future<void> clearLogs() async {
    await preferences.setString(_logsKey, '[]');
  }

  List<Map<String, Object?>> _jsonList(String key) {
    final raw = preferences.getString(key);
    if (raw == null) return [];
    final value = jsonDecode(raw);
    if (value is! List) throw const FormatException('Invalid settings data.');
    return value.map((item) => Map<String, Object?>.from(item as Map)).toList();
  }

  Future<void> _saveJsonList(
    String key,
    List<Map<String, Object?>> value,
  ) async {
    if (!await preferences.setString(key, jsonEncode(value))) {
      throw StateError('Could not save settings.');
    }
  }
}

SecurityContext? _createSecurityContext(CertificateProfile profile) {
  final trusted = profile.trustedCertificatePath;
  final chain = profile.clientCertificatePath;
  final key = profile.clientKeyPath;
  if (trusted == null && chain == null && key == null) return null;
  final context = SecurityContext(withTrustedRoots: true);
  if (trusted != null) context.setTrustedCertificates(trusted);
  if (chain != null && key != null) {
    context
      ..useCertificateChain(chain)
      ..usePrivateKey(key, password: profile.clientKeyPassword);
  }
  return context;
}

class SharedPreferencesBackend implements PreferencesBackend {
  SharedPreferencesBackend(this.preferences);

  final SharedPreferences preferences;

  @override
  String? getString(String key) => preferences.getString(key);

  @override
  Future<bool> setString(String key, String value) =>
      preferences.setString(key, value);
}

class FlutterSecretBackend implements SecretBackend {
  const FlutterSecretBackend(this.storage);

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

const dismissedSetupPrompt = -1;

int postponeSetupPrompt(DateTime now) =>
    now.add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000;

bool setupPromptDue(int afterEpochSeconds, DateTime now) =>
    afterEpochSeconds >= 0 &&
    afterEpochSeconds <= now.millisecondsSinceEpoch ~/ 1000;

class BackgroundSetupCapabilities {
  const BackgroundSetupCapabilities({
    required this.batteryOptimized,
    required this.exactAlarmAccessRequired,
  });

  final bool batteryOptimized;
  final bool exactAlarmAccessRequired;
}

abstract interface class BackgroundSetupPlatform {
  Future<BackgroundSetupCapabilities> capabilities();
  Future<void> openBatterySettings();
  Future<void> openExactAlarmSettings();
}

abstract interface class FullScreenIntentPlatform {
  Future<bool> isFullScreenIntentAllowed();
  Future<void> openFullScreenIntentSettings();
}

class AndroidSettingsPlatform
    implements BackgroundSetupPlatform, FullScreenIntentPlatform {
  const AndroidSettingsPlatform();

  static const _channel = MethodChannel(
    'com.rahul1115.ntfy_flutter/system_settings',
  );

  Future<void> setUnifiedPushEnabled(bool enabled) =>
      _channel.invokeMethod('setUnifiedPushEnabled', enabled);

  @override
  Future<BackgroundSetupCapabilities> capabilities() async {
    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'backgroundCapabilities',
      );
      return BackgroundSetupCapabilities(
        batteryOptimized: value?['batteryOptimized'] == true,
        exactAlarmAccessRequired: value?['exactAlarmAccessRequired'] == true,
      );
    } on MissingPluginException {
      return const BackgroundSetupCapabilities(
        batteryOptimized: false,
        exactAlarmAccessRequired: false,
      );
    }
  }

  @override
  Future<void> openBatterySettings() =>
      _channel.invokeMethod('openBatterySettings');

  @override
  Future<void> openExactAlarmSettings() =>
      _channel.invokeMethod('openExactAlarmSettings');

  @override
  Future<bool> isFullScreenIntentAllowed() async {
    try {
      return await _channel.invokeMethod<bool>('isFullScreenIntentAllowed') ??
          true;
    } on MissingPluginException {
      return true;
    }
  }

  @override
  Future<void> openFullScreenIntentSettings() =>
      _channel.invokeMethod('openFullScreenIntentSettings');
}

class ManagedCertificateFiles {
  const ManagedCertificateFiles({this.directoryProvider});

  final Future<Directory> Function()? directoryProvider;

  Future<String> save({
    required Uint8List bytes,
    required String fileName,
    required String label,
  }) async {
    if (bytes.isEmpty) throw const FormatException('Certificate is empty.');
    final root =
        await (directoryProvider?.call() ?? getApplicationSupportDirectory());
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}certificates',
    );
    await directory.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '${directory.path}${Platform.pathSeparator}${label.hashCode}-$safeName';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<void> delete(Iterable<String> paths) async {
    final root =
        await (directoryProvider?.call() ?? getApplicationSupportDirectory());
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}certificates',
    ).absolute;
    for (final path in paths) {
      final file = File(path).absolute;
      if (!_samePath(file.parent.path, directory.path)) continue;
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Metadata removal remains authoritative if an owned file is gone.
      }
    }
  }
}

Iterable<String> _certificatePaths(Map<String, Object?> item) => [
  item['trustedCertificatePath'],
  item['clientCertificatePath'],
  item['clientKeyPath'],
].whereType<String>();

bool _samePath(String left, String right) => Platform.isWindows
    ? left.toLowerCase() == right.toLowerCase()
    : left == right;

bool _isServerUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
}

String normalizeServerOrigin(String value) {
  if (!_isServerUrl(value)) throw const FormatException('Invalid server URL.');
  final uri = Uri.parse(value.trim());
  return _origin(uri);
}

String _origin(Uri uri) => Uri(
  scheme: uri.scheme.toLowerCase(),
  host: uri.host.toLowerCase(),
  port: uri.hasPort ? uri.port : null,
).toString().replaceFirst(RegExp(r'/$'), '');

String _secretKey(String type, String value) =>
    'ntfy.$type.${base64Url.encode(utf8.encode(value))}';

bool _validHeaderName(String name) =>
    name.isNotEmpty && RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(name);

bool _reservedHeader(String name) => const {
  'authorization',
  'host',
  'content-length',
  'connection',
  'upgrade',
  'sec-websocket-key',
  'sec-websocket-version',
  'sec-websocket-protocol',
  'sec-websocket-extensions',
}.contains(name.toLowerCase());
