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

  group('invalidateFetchedProviderModelsForConnectionChange', () {
    test('clears fetched catalog when base URL changes', () {
      final previous = ProviderConfig.defaultsFor('ExampleAI').copyWith(
        models: const ['selected-model'],
        cachedModels: const ['old-model'],
      );

      final updated = invalidateFetchedProviderModelsForConnectionChange(
        previous,
        previous.copyWith(baseUrl: 'https://new.example.com/v1'),
      );

      expect(updated.models, ['selected-model']);
      expect(updated.cachedModels, isEmpty);
    });

    test('clears fetched catalog when API key changes', () {
      final previous = ProviderConfig.defaultsFor(
        'ExampleAI',
      ).copyWith(apiKey: 'old-key', cachedModels: const ['old-model']);

      final updated = invalidateFetchedProviderModelsForConnectionChange(
        previous,
        previous.copyWith(apiKey: 'new-key'),
      );

      expect(updated.cachedModels, isEmpty);
    });

    test('keeps fetched catalog when effective connection is unchanged', () {
      final previous = ProviderConfig.defaultsFor('ExampleAI').copyWith(
        apiKey: 'same-key',
        baseUrl: 'https://example.com/v1',
        cachedModels: const ['cached-model'],
      );

      final updated = invalidateFetchedProviderModelsForConnectionChange(
        previous,
        previous.copyWith(
          apiKey: ' same-key ',
          baseUrl: ' https://example.com/v1 ',
        ),
      );

      expect(updated.cachedModels, ['cached-model']);
    });
  });
}
