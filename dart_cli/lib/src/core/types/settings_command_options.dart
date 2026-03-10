class SettingsCommandOptions {
  const SettingsCommandOptions({
    required this.action,
    required this.profile,
    required this.provider,
    required this.envName,
    required this.token,
    required this.localScope,
    required this.assumeYes,
  });

  final String action;
  final String profile;
  final String provider;
  final String envName;
  final String token;
  final bool localScope;
  final bool assumeYes;
}
