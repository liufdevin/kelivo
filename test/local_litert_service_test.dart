import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/services/local_litert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LiteRT model size exception exposes a stable error code', () {
    const error = LocalLiteRtException(
      'local_litert_model_too_large',
      'too large',
    );

    expect(error.toString(), 'local_litert_model_too_large');
  });

  test(
    'LiteRT service reports unsupported platforms before native calls',
    () async {
      if (Platform.isAndroid) return;

      expect(
        LocalLiteRtService.sendMessage(
          modelPath: '/tmp/model.litertlm',
          systemPrompt: 'system',
          prompt: 'hello',
        ),
        throwsUnsupportedError,
      );
    },
  );
}
