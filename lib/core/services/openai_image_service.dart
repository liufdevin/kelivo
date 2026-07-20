import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../utils/app_directories.dart';
import '../providers/settings_provider.dart';
import 'api_key_manager.dart';
import 'model_override_payload_parser.dart';
import 'network/dio_http_client.dart';

class OpenAIImageResult {
  const OpenAIImageResult({required this.imagePaths, this.revisedPrompt});

  final List<String> imagePaths;
  final String? revisedPrompt;
}

class OpenAIImageServiceException implements Exception {
  const OpenAIImageServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpenAIImageService {
  OpenAIImageService._();

  static const Duration _timeout = Duration(minutes: 3);

  static Future<OpenAIImageResult> generate({
    required ProviderConfig config,
    required String prompt,
    String model = 'gpt-image-2',
    String size = '1024x1024',
    String quality = 'auto',
    String outputFormat = 'png',
    int n = 1,
    http.Client? client,
  }) async {
    final apiKey = _effectiveApiKey(config);
    if (apiKey.isEmpty) {
      throw const OpenAIImageServiceException('missing_api_key');
    }
    final promptText = prompt.trim();
    if (promptText.isEmpty) {
      throw const OpenAIImageServiceException('missing_prompt');
    }

    final ownsClient = client == null;
    final resolvedClient = client ?? clientFor(config);
    try {
      final xAi = _isXAiProvider(config);
      final response = await resolvedClient
          .post(
            _endpoint(config, 'images/generations'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _effectiveModelId(config, model),
              'prompt': promptText,
              'n': n.clamp(1, 4),
              if (xAi)
                'response_format': 'b64_json'
              else ...{
                'size': size,
                'quality': quality,
                'output_format': outputFormat,
              },
            }),
          )
          .timeout(_timeout);
      return await _parseResponse(
        response,
        prefix: 'openai_img',
        fallbackMime: _outputMime(outputFormat),
      );
    } finally {
      if (ownsClient) resolvedClient.close();
    }
  }

  static Future<OpenAIImageResult> edit({
    required ProviderConfig config,
    required String prompt,
    required List<String> imagePaths,
    String? maskPath,
    String model = 'gpt-image-2',
    String size = '1024x1024',
    String quality = 'auto',
    String outputFormat = 'png',
    int n = 1,
    http.Client? client,
  }) async {
    final apiKey = _effectiveApiKey(config);
    if (apiKey.isEmpty) {
      throw const OpenAIImageServiceException('missing_api_key');
    }
    final promptText = prompt.trim();
    if (promptText.isEmpty) {
      throw const OpenAIImageServiceException('missing_prompt');
    }
    final images = imagePaths
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (images.isEmpty) {
      throw const OpenAIImageServiceException('missing_edit_image');
    }

    final ownsClient = client == null;
    final resolvedClient = client ?? clientFor(config);
    try {
      if (_isXAiProvider(config)) {
        final imageRefs = <Map<String, String>>[
          for (final path in images) await _xAiImageReference(path),
        ];
        final response = await resolvedClient
            .post(
              _endpoint(config, 'images/edits'),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': _effectiveModelId(config, model),
                'prompt': promptText,
                if (imageRefs.length == 1)
                  'image': imageRefs.single
                else
                  'images': imageRefs,
                'response_format': 'b64_json',
              }),
            )
            .timeout(_timeout);
        return await _parseResponse(
          response,
          prefix: 'openai_edit',
          fallbackMime: _outputMime(outputFormat),
        );
      }

      final request = http.MultipartRequest(
        'POST',
        _endpoint(config, 'images/edits'),
      );
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.fields.addAll({
        'model': _effectiveModelId(config, model),
        'prompt': promptText,
        'n': n.clamp(1, 4).toString(),
        'size': size,
        'quality': quality,
        'output_format': outputFormat,
      });
      for (final path in images) {
        request.files.add(await http.MultipartFile.fromPath('image', path));
      }
      final mask = maskPath?.trim();
      if (mask != null && mask.isNotEmpty) {
        request.files.add(await http.MultipartFile.fromPath('mask', mask));
      }

      final streamed = await resolvedClient.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      return await _parseResponse(
        response,
        prefix: 'openai_edit',
        fallbackMime: _outputMime(outputFormat),
      );
    } finally {
      if (ownsClient) resolvedClient.close();
    }
  }

  static http.Client clientFor(ProviderConfig config) {
    if (config.proxyEnabled == true &&
        (config.proxyHost ?? '').trim().isNotEmpty &&
        (config.proxyPort ?? '').trim().isNotEmpty) {
      return DioHttpClient(
        proxy: NetworkProxyConfig(
          enabled: true,
          type: ProviderConfig.resolveProxyType(config.proxyType),
          host: config.proxyHost!.trim(),
          port: int.tryParse(config.proxyPort!.trim()) ?? 8080,
          username: (config.proxyUsername ?? '').trim().isEmpty
              ? null
              : config.proxyUsername!.trim(),
          password: (config.proxyPassword ?? '').trim().isEmpty
              ? null
              : config.proxyPassword!.trim(),
        ),
      );
    }
    return DioHttpClient();
  }

  static String _effectiveApiKey(ProviderConfig config) {
    final direct = config.apiKey.trim();
    if (direct.isNotEmpty) return direct;
    if (config.multiKeyEnabled == true &&
        (config.apiKeys?.isNotEmpty == true)) {
      final selected = ApiKeyManager().selectForProvider(config);
      return selected.key?.key.trim() ?? '';
    }
    return '';
  }

  static String _effectiveModelId(ProviderConfig config, String model) {
    final fallback = model.trim().isEmpty ? 'gpt-image-2' : model.trim();
    try {
      final ov = ModelOverridePayloadParser.modelOverride(
        config.modelOverrides,
        fallback,
      );
      final upstream = (ov['apiModelId'] ?? ov['api_model_id'])
          ?.toString()
          .trim();
      if (upstream != null && upstream.isNotEmpty) return upstream;
    } catch (_) {}
    return fallback;
  }

  static Uri _endpoint(ProviderConfig config, String path) {
    final rawBase = config.baseUrl.trim().isEmpty
        ? 'https://api.openai.com/v1'
        : config.baseUrl.trim();
    final base = rawBase.endsWith('/')
        ? rawBase.substring(0, rawBase.length - 1)
        : rawBase;
    return Uri.parse('$base/$path');
  }

  static bool _isXAiProvider(ProviderConfig config) {
    final host = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';
    if (host == 'x.ai' || host.endsWith('.x.ai')) return true;
    final identity = '${config.id} ${config.name}'.toLowerCase();
    return RegExp(
      r'(^|[^a-z0-9])(grok|xai|x\.ai)([^a-z0-9]|$)',
    ).hasMatch(identity);
  }

  static Future<Map<String, String>> _xAiImageReference(String path) async {
    final source = path.trim();
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return <String, String>{'type': 'image_url', 'url': source};
    }
    if (source.startsWith('data:')) {
      return <String, String>{'type': 'image_url', 'url': source};
    }
    final mime = _mimeFromPath(source);
    final bytes = await File(source).readAsBytes();
    return <String, String>{
      'type': 'image_url',
      'url': 'data:$mime;base64,${base64Encode(bytes)}',
    };
  }

  static String _mimeFromPath(String path) {
    final normalized = path.toLowerCase().split('?').first.split('#').first;
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (normalized.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  static String _outputMime(String outputFormat) {
    final normalized = outputFormat.trim().toLowerCase();
    if (normalized == 'jpg' || normalized == 'jpeg') return 'image/jpeg';
    if (normalized == 'webp') return 'image/webp';
    return 'image/png';
  }

  static Future<OpenAIImageResult> _parseResponse(
    http.Response response, {
    required String prefix,
    required String fallbackMime,
  }) async {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenAIImageServiceException(_extractError(response.body));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const OpenAIImageServiceException('invalid_response');
    }
    final data = decoded['data'];
    if (data is! List || data.isEmpty) {
      throw const OpenAIImageServiceException('empty_image_response');
    }

    final imagePaths = <String>[];
    String? revisedPrompt;
    for (final item in data) {
      if (item is! Map) continue;
      final prompt = item['revised_prompt']?.toString();
      if (prompt != null && prompt.isNotEmpty) {
        revisedPrompt ??= prompt;
      }
      final b64 = item['b64_json']?.toString();
      if (b64 != null && b64.isNotEmpty) {
        final mime = item['mime_type']?.toString().trim();
        final path = await AppDirectories.saveBase64Image(
          mime == null || mime.isEmpty ? fallbackMime : mime,
          b64,
          prefix: prefix,
        );
        if (path != null && path.isNotEmpty) imagePaths.add(path);
      }
      final url = item['url']?.toString();
      if (url != null && url.isNotEmpty) {
        imagePaths.add(url);
      }
    }
    if (imagePaths.isEmpty) {
      throw const OpenAIImageServiceException('empty_image_response');
    }
    return OpenAIImageResult(
      imagePaths: List.unmodifiable(imagePaths),
      revisedPrompt: revisedPrompt,
    );
  }

  static String _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = error['message']?.toString();
          if (message != null && message.isNotEmpty) return message;
        }
      }
    } catch (_) {}
    return body.trim().isEmpty ? 'request_failed' : body.trim();
  }
}
