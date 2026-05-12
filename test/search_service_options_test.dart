import 'package:Kelivo/core/services/search/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchServiceOptions', () {
    test('GoogleSearchOptions round trips through JSON', () {
      final options = GoogleSearchOptions(
        id: 'google-1',
        apiKey: 'google-key',
        searchEngineId: 'cx-123',
      );

      final decoded = SearchServiceOptions.fromJson(options.toJson());

      expect(decoded, isA<GoogleSearchOptions>());
      final google = decoded as GoogleSearchOptions;
      expect(google.id, 'google-1');
      expect(google.apiKey, 'google-key');
      expect(google.searchEngineId, 'cx-123');
    });

    test('GoogleSearchOptions reads legacy cx key', () {
      final decoded = SearchServiceOptions.fromJson({
        'type': 'google',
        'id': 'google-legacy',
        'apiKey': 'google-key',
        'cx': 'legacy-cx',
      });

      expect(decoded, isA<GoogleSearchOptions>());
      expect((decoded as GoogleSearchOptions).searchEngineId, 'legacy-cx');
    });

    test('GrokSearchOptions preserves custom model and URL', () {
      final options = GrokSearchOptions(
        id: 'grok-1',
        apiKey: 'grok-key',
        model: 'grok-4-latest',
        url: 'https://api.example.com/v1/chat/completions',
      );

      final decoded = SearchServiceOptions.fromJson(options.toJson());

      expect(decoded, isA<GrokSearchOptions>());
      final grok = decoded as GrokSearchOptions;
      expect(grok.id, 'grok-1');
      expect(grok.apiKey, 'grok-key');
      expect(grok.model, 'grok-4-latest');
      expect(grok.resolvedModel, 'grok-4-latest');
      expect(grok.url, 'https://api.example.com/v1/chat/completions');
      expect(grok.resolvedUrl, 'https://api.example.com/v1/chat/completions');
    });

    test('GrokSearchOptions uses defaults for blank optional fields', () {
      final decoded = SearchServiceOptions.fromJson({
        'type': 'grok',
        'id': 'grok-default',
        'apiKey': 'grok-key',
      });

      expect(decoded, isA<GrokSearchOptions>());
      final grok = decoded as GrokSearchOptions;
      expect(grok.resolvedModel, GrokSearchOptions.defaultModel);
      expect(grok.resolvedUrl, GrokSearchOptions.defaultUrl);
    });
  });
}
