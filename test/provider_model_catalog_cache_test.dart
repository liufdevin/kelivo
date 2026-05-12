import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/provider_model_catalog_cache.dart';

void main() {
  group('cacheFetchedProviderModels', () {
    test('caches fetched catalog without changing selectable models', () {
      final cfg = ProviderConfig.defaultsFor(
        'ExampleAI',
      ).copyWith(models: const ['existing']);

      final cached = cacheFetchedProviderModels(cfg, const ['new-a', 'new-b']);

      expect(cached.models, ['existing']);
      expect(cached.cachedModels, ['new-a', 'new-b']);
    });

    test('deduplicates blank and repeated fetched model ids', () {
      final cfg = ProviderConfig.defaultsFor(
        'ExampleAI',
      ).copyWith(models: const ['model-a']);

      final cached = cacheFetchedProviderModels(cfg, const [
        ' model-a ',
        '',
        'model-b',
        'model-b',
      ]);

      expect(cached.models, ['model-a']);
      expect(cached.cachedModels, ['model-a', 'model-b']);
    });
  });
}
