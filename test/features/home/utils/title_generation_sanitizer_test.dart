import 'dart:convert';

import 'package:Kelivo/features/home/utils/title_generation_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('title generation sanitizer', () {
    test('removes generated image markdown and attachment markers', () {
      final content = sanitizeTitleGenerationMessageContent(
        'User: 生图 白猫\n'
        'Assistant: ![](D:\\app\\images\\openai_img.png)\n'
        '[image:D:\\upload\\a.png]\n'
        '[file:D:\\docs\\a.pdf]',
      );

      expect(content, 'User: 生图 白猫 Assistant:');
      expect(content, isNot(contains('openai_img.png')));
      expect(content, isNot(contains('[image:')));
      expect(content, isNot(contains('[file:')));
    });

    test('removes inline base64 images and control characters', () {
      final content = sanitizeTitleGenerationMessageContent(
        'hello\u0000 data:image/png;base64,QUJDRA== world',
      );

      expect(content, 'hello world');
    });

    test('cleans generated title output', () {
      final title = sanitizeGeneratedConversationTitle(
        '  "**白猫海报**"\n第二行\u0000',
      );

      expect(title, '白猫海报 第二行');
    });

    test('repairs UTF-8 Chinese title decoded as latin1', () {
      final mojibake = latin1.decode(utf8.encode('默认助手'));
      final title = sanitizeGeneratedConversationTitle(mojibake);

      expect(title, '默认助手');
    });

    test('keeps normal generated title unchanged', () {
      final title = sanitizeGeneratedConversationTitle('A quiet room layout');

      expect(title, 'A quiet room layout');
    });
  });
}
