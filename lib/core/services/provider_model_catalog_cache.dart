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

ProviderConfig invalidateFetchedProviderModelsForConnectionChange(
  ProviderConfig previous,
  ProviderConfig updated,
) {
  final connectionChanged =
      previous.apiKey.trim() != updated.apiKey.trim() ||
      previous.baseUrl.trim() != updated.baseUrl.trim();
  if (!connectionChanged || updated.cachedModels.isEmpty) return updated;
  return updated.copyWith(cachedModels: const []);
}
