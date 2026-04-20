import '../core/types/canonical_link.dart';
import '../core/types/canonical_source.dart';

typedef LinkedResults = ({bool ok, String name, String url, String outputPath});

typedef LinkDownloadPlan = ({CanonicalLink link, String name, String outputPath});

typedef SourceResults = ({
  bool ok,
  bool fallback,
  String format,
  String name,
  String url,
  String outputPath,
});

typedef SourceDownloadPlan = ({CanonicalSource source, String name, String outputPath});

typedef DownloadedAssetResult = ({
  List<String> downloaded,
  List<Map<String, String>> missingLinks,
  List<Map<String, String>> missingSources,
  List<String> sourceFallbackFormats,
});
