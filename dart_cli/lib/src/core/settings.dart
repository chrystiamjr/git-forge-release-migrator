import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'types/settings_scope_data.dart';

export 'types/settings_command_options.dart';
export 'types/settings_scope_data.dart';

const Set<String> supportedSettingsProviders = <String>{'github', 'gitlab', 'bitbucket'};

const Map<String, List<String>> providerEnvAliases = <String, List<String>>{
  'github': <String>['GITHUB_TOKEN', 'GH_TOKEN', 'GH_PERSONAL_TOKEN'],
  'gitlab': <String>['GITLAB_TOKEN', 'GL_TOKEN'],
  'bitbucket': <String>['BITBUCKET_TOKEN', 'BB_TOKEN'],
};

const String settingsActionInit = 'init';
const String settingsActionSetTokenEnv = 'set-token-env';
const String settingsActionSetTokenPlain = 'set-token-plain';
const String settingsActionUnsetToken = 'unset-token';
const String settingsActionShow = 'show';

String _defaultGlobalSettingsPath({Map<String, String>? env, String? homeDir}) {
  final Map<String, String> sourceEnv = env ?? Platform.environment;
  final String xdg = (sourceEnv['XDG_CONFIG_HOME'] ?? '').trim();
  if (xdg.isNotEmpty) {
    return p.join(xdg, 'gfrm', 'settings.yaml');
  }

  final String home = (homeDir ?? sourceEnv['HOME'] ?? '').trim();
  if (home.isNotEmpty) {
    return p.join(home, '.config', 'gfrm', 'settings.yaml');
  }

  return p.join(Directory.current.path, '.gfrm', 'settings.yaml');
}

String _defaultLocalSettingsPath({String? cwd}) {
  final String base = (cwd ?? Directory.current.path).trim();
  return p.join(base, '.gfrm', 'settings.yaml');
}

Map<String, dynamic> _toPlainMap(dynamic payload) {
  if (payload is YamlMap) {
    final Map<String, dynamic> result = <String, dynamic>{};
    payload.forEach((dynamic key, dynamic value) {
      result[key.toString()] = _toPlainValue(value);
    });
    return result;
  }

  if (payload is Map) {
    return payload.map((dynamic key, dynamic value) => MapEntry<String, dynamic>(key.toString(), _toPlainValue(value)));
  }

  return <String, dynamic>{};
}

dynamic _toPlainValue(dynamic payload) {
  if (payload is YamlMap || payload is Map) {
    return _toPlainMap(payload);
  }

  if (payload is YamlList || payload is List) {
    return (payload as List<dynamic>).map<dynamic>(_toPlainValue).toList(growable: false);
  }

  return payload;
}

Map<String, dynamic> _normalizeYamlPayload(dynamic payload, String pathValue) {
  if (payload == null) {
    return <String, dynamic>{};
  }

  if (payload is YamlMap || payload is Map) {
    return _toPlainMap(payload);
  }

  throw ArgumentError('Invalid settings payload in $pathValue: expected mapping');
}

Map<String, dynamic> _loadSettingsFile(String pathValue) {
  final File file = File(pathValue);
  if (!file.existsSync()) {
    return <String, dynamic>{};
  }

  final String text = file.readAsStringSync();
  if (text.trim().isEmpty) {
    return <String, dynamic>{};
  }

  try {
    final dynamic payload = loadYaml(text);
    return _normalizeYamlPayload(payload, pathValue);
  } catch (_) {
    final dynamic payload = jsonDecode(text);
    return _normalizeYamlPayload(payload, pathValue);
  }
}

Map<String, dynamic> _deepMergeMaps(Map<String, dynamic> base, Map<String, dynamic> override) {
  final Map<String, dynamic> merged = <String, dynamic>{...base};
  for (final MapEntry<String, dynamic> entry in override.entries) {
    final dynamic existing = merged[entry.key];
    if (existing is Map<String, dynamic> && entry.value is Map<String, dynamic>) {
      merged[entry.key] = _deepMergeMaps(existing, entry.value as Map<String, dynamic>);
    } else {
      merged[entry.key] = entry.value;
    }
  }

  return merged;
}

Map<String, dynamic> _loadEffectiveSettings({
  String? cwd,
  Map<String, String>? env,
  String? homeDir,
}) {
  final Map<String, dynamic> globalData = _loadSettingsFile(_defaultGlobalSettingsPath(env: env, homeDir: homeDir));
  final Map<String, dynamic> localData = _loadSettingsFile(_defaultLocalSettingsPath(cwd: cwd));
  return _deepMergeMaps(globalData, localData);
}

SettingsScopeData _readScopeSettings({
  required bool local,
  String? cwd,
  Map<String, String>? env,
  String? homeDir,
}) {
  final String pathValue =
      local ? _defaultLocalSettingsPath(cwd: cwd) : _defaultGlobalSettingsPath(env: env, homeDir: homeDir);
  return SettingsScopeData(
    path: pathValue,
    payload: _loadSettingsFile(pathValue),
  );
}

String _resolveProfileName(Map<String, dynamic> settings, String requestedProfile) {
  final String explicit = requestedProfile.trim();
  if (explicit.isNotEmpty) {
    return explicit;
  }

  final dynamic defaultsRaw = settings['defaults'];
  final Map<String, dynamic> defaults = defaultsRaw is Map<String, dynamic> ? defaultsRaw : <String, dynamic>{};
  final String profile = (defaults['profile'] ?? '').toString().trim();
  return profile.isEmpty ? 'default' : profile;
}

Map<String, dynamic> _providerBlock(Map<String, dynamic> settings, String profile, String provider) {
  if (!supportedSettingsProviders.contains(provider)) {
    return <String, dynamic>{};
  }

  final dynamic profilesRaw = settings['profiles'];
  final Map<String, dynamic> profiles = profilesRaw is Map<String, dynamic> ? profilesRaw : <String, dynamic>{};
  final dynamic profileRaw = profiles[profile];
  final Map<String, dynamic> profileData = profileRaw is Map<String, dynamic> ? profileRaw : <String, dynamic>{};
  final dynamic providersRaw = profileData['providers'];
  final Map<String, dynamic> providers = providersRaw is Map<String, dynamic> ? providersRaw : <String, dynamic>{};
  final dynamic providerRaw = providers[provider];
  return providerRaw is Map<String, dynamic> ? providerRaw : <String, dynamic>{};
}

String _tokenFromSettings(
  Map<String, dynamic> settings,
  String profile,
  String provider, {
  Map<String, String>? env,
}) {
  final Map<String, String> sourceEnv = env ?? Platform.environment;
  final Map<String, dynamic> providerData = _providerBlock(settings, profile, provider);

  final String tokenEnvName = (providerData['token_env'] ?? '').toString().trim();
  if (tokenEnvName.isNotEmpty) {
    final String value = (sourceEnv[tokenEnvName] ?? '').trim();
    if (value.isNotEmpty) {
      return value;
    }
  }

  return (providerData['token_plain'] ?? '').toString();
}

String _tokenEnvNameFromSettings(Map<String, dynamic> settings, String profile, String provider) {
  final Map<String, dynamic> providerData = _providerBlock(settings, profile, provider);
  return (providerData['token_env'] ?? '').toString().trim();
}

List<String> _envAliases(String provider, {String sideEnvName = ''}) {
  final List<String> names = <String>[];
  if (sideEnvName.isNotEmpty) {
    names.add(sideEnvName);
  }

  if (sideEnvName != 'GFRM_SOURCE_TOKEN') {
    names.add('GFRM_SOURCE_TOKEN');
  }

  if (sideEnvName != 'GFRM_TARGET_TOKEN') {
    names.add('GFRM_TARGET_TOKEN');
  }

  names.addAll(providerEnvAliases[provider] ?? const <String>[]);

  final Set<String> seen = <String>{};
  final List<String> deduped = <String>[];
  for (final String name in names) {
    if (name.isEmpty || seen.contains(name)) {
      continue;
    }

    seen.add(name);
    deduped.add(name);
  }

  return deduped;
}

String _tokenFromEnvAliases(
  String provider, {
  String sideEnvName = '',
  Map<String, String>? env,
}) {
  final Map<String, String> sourceEnv = env ?? Platform.environment;
  for (final String name in _envAliases(provider, sideEnvName: sideEnvName)) {
    final String value = (sourceEnv[name] ?? '').trim();
    if (value.isNotEmpty) {
      return value;
    }
  }

  return '';
}

List<String> _defaultShellProfilePaths({String? homeDir}) {
  final String home = (homeDir ?? Platform.environment['HOME'] ?? '').trim();
  if (home.isEmpty) {
    return const <String>[];
  }

  return <String>[
    p.join(home, '.zshrc'),
    p.join(home, '.zprofile'),
    p.join(home, '.bashrc'),
    p.join(home, '.bash_profile'),
  ];
}

Set<String> _scanShellExportNames({List<String>? paths}) {
  final List<String> candidates = paths ?? _defaultShellProfilePaths();
  final Set<String> names = <String>{};

  final RegExp exportPattern = RegExp(r'^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)\s*=.*$');
  final RegExp assignmentPattern = RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=.*$');

  for (final String pathValue in candidates) {
    final File file = File(pathValue);
    if (!file.existsSync()) {
      continue;
    }

    String content;
    try {
      content = file.readAsStringSync();
    } catch (_) {
      continue;
    }

    for (final String rawLine in content.split('\n')) {
      final String text = rawLine.trim();
      if (text.isEmpty || text.startsWith('#')) {
        continue;
      }

      final RegExpMatch? exportMatch = exportPattern.firstMatch(text);
      if (exportMatch != null) {
        names.add(exportMatch.group(1) ?? '');
        continue;
      }

      final RegExpMatch? assignmentMatch = assignmentPattern.firstMatch(text);
      if (assignmentMatch != null) {
        names.add(assignmentMatch.group(1) ?? '');
      }
    }
  }

  names.removeWhere((String value) => value.isEmpty);
  return names;
}

String _suggestEnvName(String provider, Set<String> knownNames) {
  for (final String candidate in providerEnvAliases[provider] ?? const <String>[]) {
    if (knownNames.contains(candidate)) {
      return candidate;
    }
  }

  return '';
}

Map<String, dynamic> _ensureProfileProvider(Map<String, dynamic> settings, String profile, String provider) {
  settings['version'] = settings['version'] ?? 1;

  final dynamic defaultsRaw = settings['defaults'];
  final Map<String, dynamic> defaults = defaultsRaw is Map<String, dynamic> ? defaultsRaw : <String, dynamic>{};
  defaults['profile'] = (defaults['profile'] ?? profile).toString();
  settings['defaults'] = defaults;

  final dynamic profilesRaw = settings['profiles'];
  final Map<String, dynamic> profiles = profilesRaw is Map<String, dynamic> ? profilesRaw : <String, dynamic>{};

  final dynamic profileRaw = profiles[profile];
  final Map<String, dynamic> profileData = profileRaw is Map<String, dynamic> ? profileRaw : <String, dynamic>{};

  final dynamic providersRaw = profileData['providers'];
  final Map<String, dynamic> providers = providersRaw is Map<String, dynamic> ? providersRaw : <String, dynamic>{};

  final dynamic providerRaw = providers[provider];
  final Map<String, dynamic> providerData = providerRaw is Map<String, dynamic> ? providerRaw : <String, dynamic>{};

  providers[provider] = providerData;
  profileData['providers'] = providers;
  profiles[profile] = profileData;
  settings['profiles'] = profiles;

  return providerData;
}

Map<String, dynamic> _setProviderTokenEnv(
  Map<String, dynamic> settings, {
  required String profile,
  required String provider,
  required String envName,
}) {
  final Map<String, dynamic> providerData = _ensureProfileProvider(settings, profile, provider);
  providerData['token_env'] = envName.trim();
  providerData.remove('token_plain');
  return settings;
}

Map<String, dynamic> _setProviderTokenPlain(
  Map<String, dynamic> settings, {
  required String profile,
  required String provider,
  required String token,
}) {
  final Map<String, dynamic> providerData = _ensureProfileProvider(settings, profile, provider);
  providerData['token_plain'] = token;
  providerData.remove('token_env');
  return settings;
}

Map<String, dynamic> _unsetProviderToken(
  Map<String, dynamic> settings, {
  required String profile,
  required String provider,
}) {
  final dynamic profilesRaw = settings['profiles'];
  if (profilesRaw is! Map<String, dynamic>) {
    return settings;
  }

  final dynamic profileRaw = profilesRaw[profile];
  if (profileRaw is! Map<String, dynamic>) {
    return settings;
  }

  final dynamic providersRaw = profileRaw['providers'];
  if (providersRaw is! Map<String, dynamic>) {
    return settings;
  }

  final dynamic providerRaw = providersRaw[provider];
  if (providerRaw is! Map<String, dynamic>) {
    return settings;
  }

  providerRaw.remove('token_env');
  providerRaw.remove('token_plain');

  if (providerRaw.isEmpty) {
    providersRaw.remove(provider);
  }

  if (providersRaw.isEmpty) {
    profileRaw.remove('providers');
  }

  if (profileRaw.isEmpty) {
    profilesRaw.remove(profile);
  }

  return settings;
}

void _ensureParentSecurity(Directory directory) {
  directory.createSync(recursive: true);
  if (Platform.isWindows) {
    return;
  }

  try {
    Process.runSync('chmod', <String>['700', directory.path]);
  } catch (_) {
    // Ignore permission hardening failures.
  }
}

void _hardenFilePermissions(String pathValue) {
  if (Platform.isWindows) {
    return;
  }

  try {
    Process.runSync('chmod', <String>['600', pathValue]);
  } catch (_) {
    // Ignore permission hardening failures.
  }
}

void _replaceFile(File tmpFile, File targetFile) {
  try {
    tmpFile.renameSync(targetFile.path);
    return;
  } on FileSystemException {
    // Continue to overwrite-safe fallback.
  }

  File? backupFile;
  if (targetFile.existsSync()) {
    backupFile = File('${targetFile.path}.bak-${DateTime.now().microsecondsSinceEpoch}');
    try {
      targetFile.renameSync(backupFile.path);
    } on FileSystemException {
      backupFile = null;
    }
  }

  bool replaced = false;
  try {
    tmpFile.renameSync(targetFile.path);
    replaced = true;
  } on FileSystemException {
    try {
      tmpFile.copySync(targetFile.path);
      tmpFile.deleteSync();
      replaced = true;
    } on FileSystemException {
      replaced = false;
    }
  }

  if (replaced) {
    if (backupFile != null && backupFile.existsSync()) {
      backupFile.deleteSync();
    }
    return;
  }

  if (backupFile != null && backupFile.existsSync() && !targetFile.existsSync()) {
    try {
      backupFile.renameSync(targetFile.path);
      return;
    } on FileSystemException {
      backupFile.copySync(targetFile.path);
      backupFile.deleteSync();
      return;
    }
  }

  throw FileSystemException('Failed to replace file', targetFile.path);
}

void _writeSettingsFile(String pathValue, Map<String, dynamic> payload) {
  final File targetFile = File(pathValue);
  _ensureParentSecurity(targetFile.parent);

  final String tmpPath = '${targetFile.path}.tmp-${DateTime.now().microsecondsSinceEpoch}';
  final File tmpFile = File(tmpPath);
  tmpFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(payload)}\n');
  _hardenFilePermissions(tmpPath);
  _replaceFile(tmpFile, targetFile);
  _hardenFilePermissions(targetFile.path);
}

Map<String, dynamic> _maskSettingsSecrets(Map<String, dynamic> payload) {
  final String jsonPayload = jsonEncode(payload);
  final dynamic decoded = jsonDecode(jsonPayload);
  return _maskRecursive(decoded) as Map<String, dynamic>;
}

dynamic _maskRecursive(dynamic payload) {
  if (payload is Map<String, dynamic>) {
    final Map<String, dynamic> masked = <String, dynamic>{};
    for (final MapEntry<String, dynamic> entry in payload.entries) {
      if (entry.key == 'token_plain' && entry.value is String && (entry.value as String).isNotEmpty) {
        masked[entry.key] = '***';
      } else {
        masked[entry.key] = _maskRecursive(entry.value);
      }
    }
    return masked;
  }

  if (payload is List) {
    return payload.map<dynamic>(_maskRecursive).toList(growable: false);
  }

  return payload;
}

final class SettingsManager {
  const SettingsManager._();

  static String defaultGlobalSettingsPath({Map<String, String>? env, String? homeDir}) {
    return _defaultGlobalSettingsPath(env: env, homeDir: homeDir);
  }

  static String defaultLocalSettingsPath({String? cwd}) {
    return _defaultLocalSettingsPath(cwd: cwd);
  }

  static Map<String, dynamic> loadSettingsFile(String pathValue) {
    return _loadSettingsFile(pathValue);
  }

  static Map<String, dynamic> loadEffectiveSettings({
    String? cwd,
    Map<String, String>? env,
    String? homeDir,
  }) {
    return _loadEffectiveSettings(cwd: cwd, env: env, homeDir: homeDir);
  }

  static SettingsScopeData readScopeSettings({
    required bool local,
    String? cwd,
    Map<String, String>? env,
    String? homeDir,
  }) {
    return _readScopeSettings(local: local, cwd: cwd, env: env, homeDir: homeDir);
  }

  static String resolveProfileName(Map<String, dynamic> settings, String requestedProfile) {
    return _resolveProfileName(settings, requestedProfile);
  }

  static String tokenFromSettings(
    Map<String, dynamic> settings,
    String profile,
    String provider, {
    Map<String, String>? env,
  }) {
    return _tokenFromSettings(settings, profile, provider, env: env);
  }

  static String tokenEnvNameFromSettings(Map<String, dynamic> settings, String profile, String provider) {
    return _tokenEnvNameFromSettings(settings, profile, provider);
  }

  static List<String> envAliases(String provider, {String sideEnvName = ''}) {
    return _envAliases(provider, sideEnvName: sideEnvName);
  }

  static String tokenFromEnvAliases(
    String provider, {
    String sideEnvName = '',
    Map<String, String>? env,
  }) {
    return _tokenFromEnvAliases(provider, sideEnvName: sideEnvName, env: env);
  }

  static List<String> defaultShellProfilePaths({String? homeDir}) {
    return _defaultShellProfilePaths(homeDir: homeDir);
  }

  static Set<String> scanShellExportNames({List<String>? paths}) {
    return _scanShellExportNames(paths: paths);
  }

  static String suggestEnvName(String provider, Set<String> knownNames) {
    return _suggestEnvName(provider, knownNames);
  }

  static Map<String, dynamic> setProviderTokenEnv(
    Map<String, dynamic> settings, {
    required String profile,
    required String provider,
    required String envName,
  }) {
    return _setProviderTokenEnv(settings, profile: profile, provider: provider, envName: envName);
  }

  static Map<String, dynamic> setProviderTokenPlain(
    Map<String, dynamic> settings, {
    required String profile,
    required String provider,
    required String token,
  }) {
    return _setProviderTokenPlain(settings, profile: profile, provider: provider, token: token);
  }

  static Map<String, dynamic> unsetProviderToken(
    Map<String, dynamic> settings, {
    required String profile,
    required String provider,
  }) {
    return _unsetProviderToken(settings, profile: profile, provider: provider);
  }

  static void writeSettingsFile(String pathValue, Map<String, dynamic> payload) {
    _writeSettingsFile(pathValue, payload);
  }

  static Map<String, dynamic> maskSettingsSecrets(Map<String, dynamic> payload) {
    return _maskSettingsSecrets(payload);
  }
}
