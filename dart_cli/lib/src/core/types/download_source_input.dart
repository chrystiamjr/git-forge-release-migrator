import '../adapters/provider_adapter.dart';
import 'canonical_source.dart';

class DownloadSourceInput {
  DownloadSourceInput({
    required this.providerRef,
    required this.token,
    required this.tag,
    required this.source,
    required this.outputPath,
  });

  final ProviderRef providerRef;
  final String token;
  final String tag;
  final CanonicalSource source;
  final String outputPath;
}
