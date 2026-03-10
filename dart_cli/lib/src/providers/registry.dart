import '../core/adapters/provider_adapter.dart';
import 'bitbucket.dart';
import 'github.dart';
import 'gitlab.dart';

class ProviderRegistry {
  ProviderRegistry(this.adapters);

  final Map<String, ProviderAdapter> adapters;

  factory ProviderRegistry.defaults() {
    return ProviderRegistry(<String, ProviderAdapter>{
      'github': GitHubAdapter(),
      'gitlab': GitLabAdapter(),
      'bitbucket': BitbucketAdapter(),
    });
  }

  ProviderAdapter get(String provider) {
    final ProviderAdapter? adapter = adapters[provider];
    if (adapter == null) {
      throw ArgumentError('Unsupported provider: $provider');
    }

    return adapter;
  }

  String pairStatus(String source, String target) {
    const Set<String> known = <String>{'github', 'gitlab', 'bitbucket'};
    if (!known.contains(source) || !known.contains(target)) {
      return 'unsupported';
    }

    if (source == target) {
      return 'unsupported';
    }

    return 'enabled';
  }

  void requireSupportedPair(String source, String target) {
    if (pairStatus(source, target) != 'enabled') {
      throw ArgumentError('Provider pair $source->$target is unsupported.');
    }
  }
}
