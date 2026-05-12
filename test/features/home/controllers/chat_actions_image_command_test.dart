import 'package:Kelivo/features/home/controllers/chat_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatActions image command parsing', () {
    test('parses slash image commands', () {
      expect(
        ChatActions.imageGenerationPromptFromText('/image a neon city'),
        'a neon city',
      );
      expect(
        ChatActions.imageGenerationPromptFromText('/img: watercolor cat'),
        'watercolor cat',
      );
      expect(
        ChatActions.imageGenerationPromptFromText('/draw：isometric room'),
        'isometric room',
      );
    });

    test('parses Chinese image commands', () {
      expect(ChatActions.imageGenerationPromptFromText('生图 一只白色猫咪'), '一只白色猫咪');
      expect(ChatActions.imageGenerationPromptFromText('画图：赛博朋克街道'), '赛博朋克街道');
    });

    test('returns empty prompt for command without content', () {
      expect(ChatActions.imageGenerationPromptFromText('/image'), '');
      expect(ChatActions.imageGenerationPromptFromText('生图'), '');
    });

    test('does not treat ordinary chat text as image request', () {
      expect(ChatActions.imageGenerationPromptFromText('帮我写一段介绍'), isNull);
      expect(
        ChatActions.imageGenerationPromptFromText('image quality'),
        isNull,
      );
    });
  });
}
