import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProviderConfig.defaultsFor', () {
    test('SiliconFlow does not prefill free models', () {
      final cfg = ProviderConfig.defaultsFor('SiliconFlow');

      expect(cfg.enabled, isTrue);
      expect(cfg.apiKey, isEmpty);
      expect(cfg.baseUrl, 'https://api.siliconflow.cn/v1');
      expect(cfg.models, isEmpty);
      expect(cfg.cachedModels, isEmpty);
      expect(cfg.modelOverrides, isEmpty);
    });
  });
}
