import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/local_litert_prompt_builder.dart';

void main() {
  group('buildLocalLiteRtPrompt', () {
    test('keeps short chat history intact', () {
      final prompt = buildLocalLiteRtPrompt([
        {'role': 'system', 'content': 'Be concise.'},
        {'role': 'user', 'content': 'Hello'},
        {'role': 'assistant', 'content': 'Hi'},
        {'role': 'tool', 'content': 'weather ok'},
      ]);

      expect(prompt.systemPrompt, 'Be concise.');
      expect(prompt.prompt, 'User: Hello\n\nAssistant: Hi\n\nTool: weather ok');
      expect(prompt.omittedTurnCount, 0);
    });

    test('limits long chat history to recent turns', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': 'Be helpful.'},
        for (var i = 0; i < 12; i++)
          {'role': i.isEven ? 'user' : 'assistant', 'content': 'turn-$i'},
      ];

      final prompt = buildLocalLiteRtPrompt(
        messages,
        maxPromptChars: 80,
        keepRecentTurns: 4,
      );

      expect(prompt.prompt.length, lessThanOrEqualTo(80));
      expect(prompt.prompt, contains('turn-11'));
      expect(prompt.prompt, isNot(contains('turn-0')));
      expect(prompt.omittedTurnCount, greaterThan(0));
      expect(prompt.systemPrompt, contains('Earlier conversation turns'));
    });

    test('extracts text from multimodal content parts', () {
      final prompt = buildLocalLiteRtPrompt([
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'first'},
            {'type': 'image_url', 'image_url': 'ignored'},
            {'type': 'text', 'text': 'second'},
          ],
        },
      ]);

      expect(prompt.prompt, 'User: first\nsecond');
    });

    test('keeps oversized latest turn within the prompt limit', () {
      final prompt = buildLocalLiteRtPrompt([
        {'role': 'user', 'content': 'x' * 200},
      ], maxPromptChars: 40);

      expect(prompt.prompt.length, 40);
      expect(prompt.omittedTurnCount, 0);
    });
  });
}
