import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/openai_image_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const String _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

ProviderConfig _config(String baseUrl) {
  return ProviderConfig(
    id: 'OpenAI',
    enabled: true,
    name: 'OpenAI',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
  );
}

ProviderConfig _grokConfig(String baseUrl) {
  return ProviderConfig(
    id: 'Grok',
    enabled: true,
    name: 'Grok',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.openai,
  );
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.bodyBytes,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> bodyBytes;

  String get utf8Body => utf8.decode(bodyBytes);
  String get latin1Body => latin1.decode(bodyBytes);
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient({required this.statusCode, required this.responseBody});

  final int statusCode;
  final String responseBody;
  final requests = <_CapturedRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    requests.add(
      _CapturedRequest(
        method: request.method,
        url: request.url,
        headers: Map<String, String>.from(request.headers),
        bodyBytes: bytes,
      ),
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(responseBody)),
      statusCode,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kelivo_image_test_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
            case 'getApplicationCacheDirectory':
              return tempDir.path;
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('generate posts image generation JSON and saves base64 image', () async {
    final client = _RecordingClient(
      statusCode: 200,
      responseBody: jsonEncode({
        'data': [
          {'b64_json': _onePixelPng},
        ],
      }),
    );

    final result = await OpenAIImageService.generate(
      config: _config('https://api.openai.test/v1'),
      prompt: 'draw a moon',
      model: 'gpt-image-2',
      size: '1024x1024',
      quality: 'auto',
      outputFormat: 'png',
      n: 2,
      client: client,
    );

    final request = client.requests.single;
    final body = jsonDecode(request.utf8Body) as Map<String, dynamic>;
    expect(request.method, 'POST');
    expect(request.url.path, '/v1/images/generations');
    expect(request.headers['Authorization'], 'Bearer test-key');
    expect(body['model'], 'gpt-image-2');
    expect(body['prompt'], 'draw a moon');
    expect(body['n'], 2);
    expect(result.imagePaths, hasLength(1));
    expect(File(result.imagePaths.single).existsSync(), isTrue);
  });

  test('generate resolves apiModelId from provider model override', () async {
    final client = _RecordingClient(
      statusCode: 200,
      responseBody: jsonEncode({
        'data': [
          {'b64_json': _onePixelPng},
        ],
      }),
    );
    final config = _config('https://api.openai.test/v1').copyWith(
      modelOverrides: const <String, dynamic>{
        'image-default': {'apiModelId': 'gpt-image-2'},
      },
    );

    await OpenAIImageService.generate(
      config: config,
      prompt: 'draw a moon',
      model: 'image-default',
      client: client,
    );

    final body =
        jsonDecode(client.requests.single.utf8Body) as Map<String, dynamic>;
    expect(body['model'], 'gpt-image-2');
  });

  test('Grok generate uses xAI-compatible JSON fields', () async {
    final client = _RecordingClient(
      statusCode: 200,
      responseBody: jsonEncode({
        'data': [
          {'b64_json': _onePixelPng, 'mime_type': 'image/png'},
        ],
      }),
    );

    final result = await OpenAIImageService.generate(
      config: _grokConfig('https://api.x.ai/v1'),
      prompt: 'draw a moon',
      model: 'grok-imagine-image-quality',
      client: client,
    );

    final body =
        jsonDecode(client.requests.single.utf8Body) as Map<String, dynamic>;
    expect(body['model'], 'grok-imagine-image-quality');
    expect(body['prompt'], 'draw a moon');
    expect(body['n'], 1);
    expect(body['response_format'], 'b64_json');
    expect(body.containsKey('size'), isFalse);
    expect(body.containsKey('quality'), isFalse);
    expect(body.containsKey('output_format'), isFalse);
    expect(File(result.imagePaths.single).existsSync(), isTrue);
  });

  test('edit posts multipart images edit request', () async {
    final inputFile = File('${tempDir.path}/input.png');
    await inputFile.writeAsBytes(base64Decode(_onePixelPng));
    final maskFile = File('${tempDir.path}/mask.png');
    await maskFile.writeAsBytes(base64Decode(_onePixelPng));
    final client = _RecordingClient(
      statusCode: 200,
      responseBody: jsonEncode({
        'data': [
          {'b64_json': _onePixelPng},
        ],
      }),
    );

    final result = await OpenAIImageService.edit(
      config: _config('https://api.openai.test/v1'),
      prompt: 'turn it blue',
      imagePaths: [inputFile.path],
      maskPath: maskFile.path,
      model: 'gpt-image-2',
      client: client,
    );

    final request = client.requests.single;
    expect(request.method, 'POST');
    expect(request.url.path, '/v1/images/edits');
    expect(request.headers['Authorization'], 'Bearer test-key');
    expect(request.headers['content-type'], startsWith('multipart/form-data'));
    expect(request.latin1Body, contains('name="prompt"'));
    expect(request.latin1Body, contains('turn it blue'));
    expect(request.latin1Body, contains('name="image"'));
    expect(request.latin1Body, contains('name="mask"'));
    expect(result.imagePaths, hasLength(1));
    expect(File(result.imagePaths.single).existsSync(), isTrue);
  });

  test('Grok edit posts JSON image data', () async {
    final inputFile = File('${tempDir.path}/input.png');
    await inputFile.writeAsBytes(base64Decode(_onePixelPng));
    final client = _RecordingClient(
      statusCode: 200,
      responseBody: jsonEncode({
        'data': [
          {'b64_json': _onePixelPng, 'mime_type': 'image/png'},
        ],
      }),
    );

    final result = await OpenAIImageService.edit(
      config: _grokConfig('https://api.x.ai/v1'),
      prompt: 'turn it blue',
      imagePaths: [inputFile.path],
      model: 'grok-imagine-image-quality',
      client: client,
    );

    final request = client.requests.single;
    final body = jsonDecode(request.utf8Body) as Map<String, dynamic>;
    expect(request.method, 'POST');
    expect(request.url.path, '/v1/images/edits');
    expect(
      request.headers.entries
          .singleWhere((entry) => entry.key.toLowerCase() == 'content-type')
          .value,
      'application/json',
    );
    expect(body['model'], 'grok-imagine-image-quality');
    expect(body['prompt'], 'turn it blue');
    expect(body['image']['type'], 'image_url');
    expect(body['image']['url'], startsWith('data:image/png;base64,'));
    expect(result.imagePaths, hasLength(1));
    expect(File(result.imagePaths.single).existsSync(), isTrue);
  });

  test('throws readable API error message', () {
    final client = _RecordingClient(
      statusCode: 400,
      responseBody: jsonEncode({
        'error': {'message': 'bad image request'},
      }),
    );

    expect(
      () => OpenAIImageService.generate(
        config: _config('https://api.openai.test/v1'),
        prompt: 'draw',
        client: client,
      ),
      throwsA(
        isA<OpenAIImageServiceException>().having(
          (e) => e.message,
          'message',
          'bad image request',
        ),
      ),
    );
  });
}
