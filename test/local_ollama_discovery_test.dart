import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/model_provider.dart';
import 'package:Kelivo/core/services/local_provider_config.dart';

void main() {
  test(
    'falls back to Ollama native tags endpoint for local providers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      server.listen((request) async {
        requests.add(request.uri.path);
        if (request.uri.path == '/api/tags') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'models': [
                {'name': 'gemma3:4b'},
                {'model': 'qwen2.5:7b'},
              ],
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      try {
        final cfg = buildLocalOpenAICompatibleProviderConfig(
          id: 'Local - Ollama',
          name: 'Local Ollama',
          enabled: true,
          apiKey: 'ollama',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          modelId: 'placeholder',
        );

        final models = await ProviderManager.listModels(cfg);

        expect(models.map((m) => m.id), ['gemma3:4b', 'qwen2.5:7b']);
        expect(requests, containsAllInOrder(['/v1/models', '/api/tags']));
      } finally {
        await server.close(force: true);
      }
    },
  );
}
