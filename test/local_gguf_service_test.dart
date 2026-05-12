import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/local_gguf_service.dart';

void main() {
  group('GGUF service', () {
    test('reports unsupported platforms before native calls', () async {
      if (Platform.isAndroid) return;

      expect(
        () => LocalGgufService.sendMessage(
          modelPath: '/tmp/model.gguf',
          systemPrompt: 'You are helpful.',
          prompt: 'hello',
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
