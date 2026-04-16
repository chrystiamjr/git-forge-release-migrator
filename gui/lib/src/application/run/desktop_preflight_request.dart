final class DesktopPreflightRequest {
  const DesktopPreflightRequest({
    required this.sourceProvider,
    required this.sourceUrl,
    required this.sourceToken,
    required this.targetProvider,
    required this.targetUrl,
    required this.targetToken,
    this.mode = modeMigrate,
    this.settingsProfile = '',
  });

  static const String modeMigrate = 'migrate';
  static const String modeResume = 'resume';

  final String mode;
  final String sourceProvider;
  final String sourceUrl;
  final String sourceToken;
  final String targetProvider;
  final String targetUrl;
  final String targetToken;
  final String settingsProfile;
}
