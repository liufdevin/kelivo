import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../models/token_usage.dart';
import '../../../providers/settings_provider.dart';
import '../chat_api_helpers.dart';
import '../stream/stream_chunk.dart';

final Map<String, String> _difyConversationIds = <String, String>{};

Uri _difyChatMessagesUrl(ProviderConfig config) {
  final rawBase = config.baseUrl.endsWith('/')
      ? config.baseUrl.substring(0, config.baseUrl.length - 1)
      : config.baseUrl;
  if (rawBase.endsWith('/chat-messages')) {
    return Uri.parse(rawBase);
  }
  return Uri.parse('$rawBase/chat-messages');
}

String? _difyHeaderValue(Map<String, String>? headers, String name) {
  if (headers == null || headers.isEmpty) return null;
  final lower = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lower) {
      final value = entry.value.trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

String _difyConversationCacheKey({
  required ProviderConfig config,
  required String modelId,
  required String localConversationId,
}) {
  return '${config.id}\n$modelId\n$localConversationId';
}

String _difyMessageContentToText(dynamic content) {
  if (content == null) return '';
  if (content is String) return content;
  if (content is List) {
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is Map) {
        final text = item['text'] ?? item['content'];
        if (text != null) buffer.write(text);
      } else if (item != null) {
        buffer.write(item);
      }
    }
    return buffer.toString();
  }
  return content.toString();
}

String _difyQueryFromMessages(List<Map<String, dynamic>> messages) {
  final normalized = messages
      .map((message) {
        final role = (message['role'] ?? 'user').toString();
        final content = _difyMessageContentToText(message['content']).trim();
        if (content.isEmpty) return null;
        return MapEntry(role, content);
      })
      .whereType<MapEntry<String, String>>()
      .toList(growable: false);

  if (normalized.isEmpty) return '';
  if (normalized.length == 1 && normalized.single.key == 'user') {
    return normalized.single.value;
  }

  final buffer = StringBuffer();
  for (final item in normalized) {
    if (buffer.isNotEmpty) buffer.write('\n\n');
    buffer.write('${item.key}: ${item.value}');
  }
  return buffer.toString();
}

int _difyUsageInt(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

TokenUsage? _difyUsage(dynamic metadata) {
  if (metadata is! Map) return null;
  final rawUsage = metadata['usage'];
  if (rawUsage is! Map) return null;
  final prompt = _difyUsageInt(rawUsage['prompt_tokens']);
  final completion = _difyUsageInt(rawUsage['completion_tokens']);
  final total = _difyUsageInt(rawUsage['total_tokens']);
  return TokenUsage(
    promptTokens: prompt,
    completionTokens: completion,
    totalTokens: total > 0 ? total : prompt + completion,
  );
}

void _rememberDifyConversationId({
  required String? localConversationId,
  required String cacheKey,
  required dynamic value,
}) {
  final localId = localConversationId?.trim();
  if (localId == null || localId.isEmpty) return;
  final conversationId = value?.toString().trim();
  if (conversationId == null || conversationId.isEmpty) return;
  _difyConversationIds[cacheKey] = conversationId;
}

Map<String, dynamic> _difyBuildBody({
  required ProviderConfig config,
  required String modelId,
  required List<Map<String, dynamic>> messages,
  required bool stream,
  Map<String, String>? extraHeaders,
  Map<String, dynamic>? extraBody,
}) {
  final localConversationId = _difyHeaderValue(
    extraHeaders,
    'X-Conversation-Id',
  );
  final cacheKey = localConversationId == null
      ? null
      : _difyConversationCacheKey(
          config: config,
          modelId: modelId,
          localConversationId: localConversationId,
        );
  final cachedDifyConversationId = cacheKey == null
      ? null
      : _difyConversationIds[cacheKey];

  final body = <String, dynamic>{
    'inputs': <String, dynamic>{},
    'query': _difyQueryFromMessages(messages),
    'response_mode': stream ? 'streaming' : 'blocking',
    'user': localConversationId ?? 'kelivo',
    if (cachedDifyConversationId != null)
      'conversation_id': cachedDifyConversationId,
  };

  final configuredBody = customBody(config, modelId);
  if (configuredBody.isNotEmpty) body.addAll(configuredBody);
  if (extraBody != null && extraBody.isNotEmpty) {
    extraBody.forEach((key, value) {
      body[key] = value;
    });
  }
  body['response_mode'] = stream ? 'streaming' : 'blocking';
  body.putIfAbsent('inputs', () => <String, dynamic>{});
  body.putIfAbsent('query', () => _difyQueryFromMessages(messages));
  body.putIfAbsent('user', () => localConversationId ?? 'kelivo');
  return body;
}

Stream<StreamChunk> sendDifyChatStream(
  http.Client client,
  ProviderConfig config,
  String modelId,
  List<Map<String, dynamic>> messages, {
  Map<String, String>? extraHeaders,
  Map<String, dynamic>? extraBody,
  bool stream = true,
}) async* {
  final localConversationId = _difyHeaderValue(
    extraHeaders,
    'X-Conversation-Id',
  );
  final cacheKey = _difyConversationCacheKey(
    config: config,
    modelId: modelId,
    localConversationId: localConversationId ?? '',
  );
  final request = http.Request('POST', _difyChatMessagesUrl(config));
  final headers = <String, String>{
    'Authorization': 'Bearer ${apiKeyForRequest(config, modelId)}',
    'Content-Type': 'application/json',
    'Accept': stream ? 'text/event-stream' : 'application/json',
  };
  headers.addAll(customHeaders(config, modelId));
  if (extraHeaders != null && extraHeaders.isNotEmpty) {
    headers.addAll(extraHeaders);
  }
  request.headers.addAll(headers);
  request.body = jsonEncode(
    _difyBuildBody(
      config: config,
      modelId: modelId,
      messages: messages,
      stream: stream,
      extraHeaders: extraHeaders,
      extraBody: extraBody,
    ),
  );

  final response = await client.send(request);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    final errorBody = await response.stream.bytesToString();
    throw HttpException('HTTP ${response.statusCode}: $errorBody');
  }

  if (!stream) {
    final text = await response.stream.bytesToString();
    final obj = jsonDecode(text);
    if (obj is! Map) {
      yield const Finish();
      return;
    }
    _rememberDifyConversationId(
      localConversationId: localConversationId,
      cacheKey: cacheKey,
      value: obj['conversation_id'],
    );
    final usage = _difyUsage(obj['metadata']);
    final answer = (obj['answer'] ?? '').toString();
    if (answer.isNotEmpty) yield TextDelta(id: 'dify', text: answer);
    if (usage != null) yield Usage(usage);
    yield const Finish();
    return;
  }

  TokenUsage? usage;
  var done = false;
  await for (final line
      in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('data:')) continue;
    final payload = trimmed.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') continue;
    final obj = jsonDecode(payload);
    if (obj is! Map) continue;

    _rememberDifyConversationId(
      localConversationId: localConversationId,
      cacheKey: cacheKey,
      value: obj['conversation_id'],
    );
    final event = (obj['event'] ?? '').toString();
    if (event == 'message' || event == 'agent_message') {
      final answer = (obj['answer'] ?? '').toString();
      if (answer.isNotEmpty) {
        yield TextDelta(id: 'dify', text: answer);
      }
    } else if (event == 'message_end') {
      usage = _difyUsage(obj['metadata']);
      done = true;
      if (usage != null) yield Usage(usage);
      yield const Finish();
    } else if (event == 'error') {
      final message = (obj['message'] ?? obj['code'] ?? 'Dify error')
          .toString();
      throw HttpException(message);
    }
  }

  if (!done) {
    if (usage != null) yield Usage(usage);
    yield const Finish();
  }
}
