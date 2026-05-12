import 'dart:io';

import 'package:flutter/services.dart';

class LocalLiteRtException implements Exception {
  const LocalLiteRtException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => code;
}

class LocalLiteRtService {
  static const MethodChannel _channel = MethodChannel('app.local_litert');

  static Future<String> sendMessage({
    required String modelPath,
    required String systemPrompt,
    required String prompt,
    double? temperature,
    bool preferCpu = true,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'LiteRT-LM local models are only supported on Android.',
      );
    }
    final String? result;
    try {
      result = await _channel.invokeMethod<String>('sendMessage', {
        'modelPath': modelPath,
        'systemPrompt': systemPrompt,
        'prompt': prompt,
        if (temperature != null) 'temperature': temperature,
        'preferCpu': preferCpu,
      });
    } on PlatformException catch (error) {
      if (error.code == 'local_litert_model_too_large') {
        throw LocalLiteRtException(error.code, error.message ?? error.code);
      }
      rethrow;
    }
    return result?.trim() ?? '';
  }

  static Future<void> testConnection({
    required String modelPath,
    double? temperature,
  }) async {
    await sendMessage(
      modelPath: modelPath,
      systemPrompt: 'You are a helpful assistant.',
      prompt: 'hello',
      temperature: temperature,
      preferCpu: true,
    );
  }
}
