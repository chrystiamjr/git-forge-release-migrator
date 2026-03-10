import 'dart:io';

import '../adapters/provider_adapter.dart';
import 'existing_release_info.dart';

class PublishReleaseInput {
  PublishReleaseInput({
    required this.providerRef,
    required this.token,
    required this.tag,
    required this.releaseName,
    required this.notesFile,
    required this.downloadedFiles,
    required this.expectedAssets,
    required this.existingInfo,
  });

  final ProviderRef providerRef;
  final String token;
  final String tag;
  final String releaseName;
  final File notesFile;
  final List<String> downloadedFiles;
  final int expectedAssets;
  final ExistingReleaseInfo existingInfo;
}
