import 'package:Kelivo/core/models/assistant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Assistant image model config', () {
    test('keeps image model fields in json round trip', () {
      const assistant = Assistant(
        id: 'assistant-1',
        name: 'Painter',
        chatModelProvider: 'OpenAI',
        chatModelId: 'gpt-5.1',
        imageModelProvider: 'Images',
        imageModelId: 'gpt-image-2',
      );

      final decoded = Assistant.fromJson(assistant.toJson());

      expect(decoded.chatModelProvider, 'OpenAI');
      expect(decoded.chatModelId, 'gpt-5.1');
      expect(decoded.imageModelProvider, 'Images');
      expect(decoded.imageModelId, 'gpt-image-2');
    });

    test(
      'defaults missing image model fields to null for old assistant json',
      () {
        final assistant = Assistant.fromJson(const {
          'id': 'assistant-1',
          'name': 'Old assistant',
        });

        expect(assistant.imageModelProvider, isNull);
        expect(assistant.imageModelId, isNull);
      },
    );

    test('clearImageModel only clears the image model binding', () {
      const assistant = Assistant(
        id: 'assistant-1',
        name: 'Painter',
        chatModelProvider: 'OpenAI',
        chatModelId: 'gpt-5.1',
        imageModelProvider: 'Images',
        imageModelId: 'gpt-image-2',
      );

      final next = assistant.copyWith(clearImageModel: true);

      expect(next.chatModelProvider, 'OpenAI');
      expect(next.chatModelId, 'gpt-5.1');
      expect(next.imageModelProvider, isNull);
      expect(next.imageModelId, isNull);
    });
  });
}
