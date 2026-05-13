import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/home/controllers/chat_actions.dart';

ProviderConfig _providerConfig({Map<String, dynamic> overrides = const {}}) {
  return ProviderConfig(
    id: 'OpenAITest',
    enabled: true,
    name: 'OpenAITest',
    apiKey: 'test-key',
    baseUrl: 'https://example.test/v1',
    providerType: ProviderKind.openai,
    models: const ['text-only', 'vision-alias'],
    modelOverrides: overrides,
  );
}

void main() {
  group('ChatActions image input capability', () {
    late SettingsProvider settings;

    setUp(() {
      SharedPreferences.setMockInitialValues(const {});
      settings = SettingsProvider();
    });

    test('rejects image input when the chat model is text-only', () async {
      await settings.setProviderConfig(
        'OpenAITest',
        _providerConfig(
          overrides: const {
            'text-only': {
              'apiModelId': 'text-only',
              'type': 'chat',
              'input': ['text'],
              'output': ['text'],
            },
          },
        ),
      );

      final rejected = ChatActions.shouldRejectImageInputForModel(
        input: const ChatInputData(text: '', imagePaths: ['C:/tmp/image.png']),
        settings: settings,
        providerKey: 'OpenAITest',
        modelId: 'text-only',
        useDirectImageApi: false,
      );

      expect(rejected, isTrue);
    });

    test('allows image input when the model declares image modality', () async {
      await settings.setProviderConfig(
        'OpenAITest',
        _providerConfig(
          overrides: const {
            'vision-alias': {
              'apiModelId': 'custom-vision-model',
              'type': 'chat',
              'input': ['text', 'image'],
              'output': ['text'],
            },
          },
        ),
      );

      final rejected = ChatActions.shouldRejectImageInputForModel(
        input: const ChatInputData(text: '', imagePaths: ['C:/tmp/image.png']),
        settings: settings,
        providerKey: 'OpenAITest',
        modelId: 'vision-alias',
        useDirectImageApi: false,
      );

      expect(rejected, isFalse);
    });

    test('allows text-only chat model when OCR is active', () async {
      await settings.setProviderConfig(
        'OpenAITest',
        _providerConfig(
          overrides: const {
            'text-only': {
              'apiModelId': 'text-only',
              'type': 'chat',
              'input': ['text'],
              'output': ['text'],
            },
          },
        ),
      );
      await settings.setOcrModel('OpenAITest', 'vision-alias');
      await settings.setOcrEnabled(true);

      final rejected = ChatActions.shouldRejectImageInputForModel(
        input: const ChatInputData(text: '', imagePaths: ['C:/tmp/image.png']),
        settings: settings,
        providerKey: 'OpenAITest',
        modelId: 'text-only',
        useDirectImageApi: false,
      );

      expect(rejected, isFalse);
    });
  });
}
