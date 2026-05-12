import 'dart:io';

import 'package:Kelivo/utils/chat_image_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatImageMarkdown.extractEditableImagePaths', () {
    test('extracts local markdown image paths in order', () {
      final paths = ChatImageMarkdown.extractEditableImagePaths(
        'done\n![](/tmp/kelivo/a.png)\n![alt](C:\\Users\\me\\b.webp)',
      );

      expect(paths, <String>['/tmp/kelivo/a.png', 'C:\\Users\\me\\b.webp']);
    });

    test('deduplicates repeated local image paths', () {
      final paths = ChatImageMarkdown.extractEditableImagePaths(
        '![](/tmp/kelivo/a.png)\nagain ![x](/tmp/kelivo/a.png)',
      );

      expect(paths, <String>['/tmp/kelivo/a.png']);
    });

    test('decodes file uri image paths', () {
      final uri = Uri.file(
        Platform.isWindows
            ? r'C:\Users\me\Kelivo Images\a b.png'
            : '/tmp/Kelivo Images/a b.png',
        windows: Platform.isWindows,
      ).toString();

      final paths = ChatImageMarkdown.extractEditableImagePaths('![]($uri)');

      expect(paths, hasLength(1));
      expect(paths.single, contains('a b.png'));
    });

    test('ignores remote, data, relative, and non-image targets', () {
      final paths = ChatImageMarkdown.extractEditableImagePaths(
        [
          '![](https://example.com/a.png)',
          '![](data:image/png;base64,AAAA)',
          '![](relative/a.png)',
          '![](/tmp/kelivo/readme.txt)',
        ].join('\n'),
      );

      expect(paths, isEmpty);
    });
  });
}
