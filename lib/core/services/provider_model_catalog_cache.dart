import '../providers/settings_provider.dart';

ProviderConfig cacheFetchedProviderModels(
  ProviderConfig config,
  Iterable<String> fetchedModelIds,
) {
  final fetched = <String>[];
  final seenFetched = <String>{};
  for (final id in fetchedModelIds) {
    final normalized = id.trim();
    if (normalized.isEmpty || !seenFetched.add(normalized)) continue;
    fetched.add(normalized);
  }

  return config.copyWith(cachedModels: fetched);
}
