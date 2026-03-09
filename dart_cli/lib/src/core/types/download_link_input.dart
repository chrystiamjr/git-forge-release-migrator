import '../adapters/provider_adapter.dart';
import 'canonical_link.dart';

class DownloadLinkInput {
  DownloadLinkInput({
    required this.providerRef,
    required this.token,
    required this.tag,
    required this.link,
    required this.outputPath,
  });

  final ProviderRef providerRef;
  final String token;
  final String tag;
  final CanonicalLink link;
  final String outputPath;
}
