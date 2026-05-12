import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart' as llama;

class LocalGgufException implements Exception {
  const LocalGgufException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => code;
}

class LocalGgufService {
  static llama.LlamaController? _controller;
  static String? _currentModelPath;

  static Future<String> sendMessage({
    required String modelPath,
    required String systemPrompt,
    required String prompt,
    double? temperature,
    bool preferCpu = true,
  }) async {
    final buffer = StringBuffer();
    await for (final token in sendMessageStream(
      modelPath: modelPath,
      systemPrompt: systemPrompt,
      prompt: prompt,
      temperature: temperature,
      preferCpu: preferCpu,
    )) {
      buffer.write(token);
    }
    return buffer.toString().trim();
  }

  static Stream<String> sendMessageStream({
    required String modelPath,
    required String systemPrompt,
    required String prompt,
    double? temperature,
    bool preferCpu = true,
  }) async* {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'GGUF local models are only supported on Android.',
      );
    }
    final normalizedPath = modelPath.trim();
    if (normalizedPath.isEmpty) {
      throw const LocalGgufException(
        'local_gguf_missing_model',
        'Missing GGUF model path.',
      );
    }
    final modelFile = File(normalizedPath);
    final exists = await modelFile.exists();
    final stat = exists ? await modelFile.stat() : null;
    if (!exists || stat?.type != FileSystemEntityType.file) {
      throw const LocalGgufException(
        'local_gguf_missing_model',
        'GGUF model file does not exist.',
      );
    }
    if (prompt.trim().isEmpty) {
      throw const LocalGgufException(
        'local_gguf_missing_prompt',
        'Missing prompt.',
      );
    }

    final controller = await _getOrCreateController(
      normalizedPath,
      preferCpu: preferCpu,
    );
    final messages = <llama.ChatMessage>[
      llama.ChatMessage(
        role: 'system',
        content: systemPrompt.trim().isEmpty
            ? 'You are a helpful assistant.'
            : systemPrompt.trim(),
      ),
      llama.ChatMessage(role: 'user', content: prompt),
    ];

    yield* controller.generateChat(
      messages: messages,
      maxTokens: 1024,
      temperature: temperature ?? 0.7,
      topP: 0.95,
      topK: 40,
      repeatPenalty: 1.1,
    );
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

  static Future<llama.LlamaController> _getOrCreateController(
    String modelPath, {
    required bool preferCpu,
  }) async {
    final existing = _controller;
    if (existing != null && _currentModelPath == modelPath) {
      final loaded = await existing.isModelLoaded();
      if (loaded) return existing;
    }

    await _disposeController();
    final controller = llama.LlamaController();
    try {
      final gpuLayers = preferCpu
          ? 0
          : (await controller.detectGpu()).recommendedGpuLayers;
      await controller.loadModel(
        modelPath: modelPath,
        threads: 4,
        contextSize: 4096,
        gpuLayers: gpuLayers,
      );
      _controller = controller;
      _currentModelPath = modelPath;
      return controller;
    } catch (error) {
      await controller.dispose();
      throw LocalGgufException('local_gguf_failed', '$error');
    }
  }

  static Future<void> _disposeController() async {
    final old = _controller;
    _controller = null;
    _currentModelPath = null;
    if (old == null) return;
    try {
      await old.dispose();
    } catch (_) {}
  }
}
