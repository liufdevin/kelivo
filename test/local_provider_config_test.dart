import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/local_provider_config.dart';

void main() {
  group('buildLocalOpenAICompatibleProviderConfig', () {
    test('creates an enabled OpenAI-compatible local provider', () {
      final cfg = buildLocalOpenAICompatibleProviderConfig(
        id: 'Local - Test',
        name: 'Local Test',
        enabled: true,
        apiKey: 'local-key',
        baseUrl: 'http://127.0.0.1:1234/v1',
        modelId: 'qwen2.5',
      );

      expect(cfg.id, 'Local - Test');
      expect(cfg.name, 'Local Test');
      expect(cfg.enabled, isTrue);
      expect(cfg.providerType, ProviderKind.openai);
      expect(cfg.baseUrl, 'http://127.0.0.1:1234/v1');
      expect(cfg.apiKey, 'local-key');
      expect(cfg.chatPath, '/chat/completions');
      expect(cfg.useResponseApi, isFalse);
      expect(cfg.models, ['qwen2.5']);
    });

    test('uses local runtime defaults for blank base url and model id', () {
      final cfg = buildLocalOpenAICompatibleProviderConfig(
        id: 'Local',
        name: 'Local',
        enabled: true,
        apiKey: '',
        baseUrl: '  ',
        modelId: '',
      );

      expect(cfg.baseUrl, defaultLocalProviderBaseUrl);
      expect(cfg.models, [defaultLocalProviderModelId]);
      expect(cfg.modelOverrides, contains(defaultLocalProviderModelId));
    });

    test('detects localhost OpenAI-compatible providers as local', () {
      final cfg = buildLocalOpenAICompatibleProviderConfig(
        id: 'Ollama',
        name: 'Ollama',
        enabled: true,
        apiKey: '',
        baseUrl: 'http://localhost:11434/v1',
        modelId: 'gemma3:4b',
      );

      expect(isLocalOpenAICompatibleProvider(cfg), isTrue);
      expect(isLocalProviderConfig(cfg), isTrue);
    });

    test('marks the configured local model as text chat', () {
      final cfg = buildLocalOpenAICompatibleProviderConfig(
        id: 'Local',
        name: 'Local',
        enabled: true,
        apiKey: '',
        baseUrl: defaultLocalProviderBaseUrl,
        modelId: 'gemma3:4b',
      );

      expect(cfg.modelOverrides['gemma3:4b'], {
        'name': 'gemma3:4b',
        'type': 'chat',
        'input': ['text'],
        'output': ['text'],
      });
    });
  });

  group('buildLocalLiteRtProviderConfig', () {
    test('creates a LiteRT-LM provider backed by a model file', () {
      final cfg = buildLocalLiteRtProviderConfig(
        id: 'Local - Gemma',
        name: 'Gemma Local',
        enabled: true,
        modelPath: '/data/user/0/com.psyche.kelivo/files/gemma.litertlm',
        modelId: 'gemma-4-E4B-it',
      );

      expect(cfg.id, 'Local - Gemma');
      expect(cfg.providerType, ProviderKind.openai);
      expect(cfg.apiKey, isEmpty);
      expect(cfg.baseUrl, endsWith('gemma.litertlm'));
      expect(cfg.chatPath, isNull);
      expect(cfg.models, ['gemma-4-E4B-it']);
      expect(isLocalLiteRtProvider(cfg), isTrue);
      expect(
        localLiteRtModelPath(cfg, 'gemma-4-E4B-it'),
        '/data/user/0/com.psyche.kelivo/files/gemma.litertlm',
      );
    });

    test('uses Gemma E4B as the default imported model id', () {
      final cfg = buildLocalLiteRtProviderConfig(
        id: 'Local',
        name: 'Local',
        enabled: true,
        modelPath: '/tmp/imported.litertlm',
        modelId: '',
      );

      expect(cfg.models, [defaultLocalLiteRtModelId]);
      expect(isLocalLiteRtProvider(cfg), isTrue);
    });
  });

  group('buildLocalGgufProviderConfig', () {
    test('creates a GGUF provider backed by a model file', () {
      final cfg = buildLocalGgufProviderConfig(
        id: 'Local - Qwen',
        name: 'Qwen GGUF',
        enabled: true,
        modelPath: '/data/user/0/com.psyche.kelivo/files/qwen.gguf',
        modelId: 'qwen2.5-3b-instruct',
      );

      expect(cfg.id, 'Local - Qwen');
      expect(cfg.providerType, ProviderKind.openai);
      expect(cfg.apiKey, isEmpty);
      expect(cfg.baseUrl, endsWith('qwen.gguf'));
      expect(cfg.chatPath, isNull);
      expect(cfg.models, ['qwen2.5-3b-instruct']);
      expect(isLocalGgufProvider(cfg), isTrue);
      expect(isLocalNativeModelProvider(cfg), isTrue);
      expect(isLocalOpenAICompatibleProvider(cfg), isFalse);
      expect(
        localGgufModelPath(cfg, 'qwen2.5-3b-instruct'),
        '/data/user/0/com.psyche.kelivo/files/qwen.gguf',
      );
    });

    test('uses a stable default imported GGUF model id', () {
      final cfg = buildLocalGgufProviderConfig(
        id: 'Local',
        name: 'Local',
        enabled: true,
        modelPath: '/tmp/imported.gguf',
        modelId: '',
      );

      expect(cfg.models, [defaultLocalGgufModelId]);
      expect(isLocalGgufProvider(cfg), isTrue);
    });
  });
}
