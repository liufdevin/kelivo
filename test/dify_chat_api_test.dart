import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/api/chat_api_service.dart';

const _conversationHeaderName = 'X-Conversation-Id';

ProviderConfig _difyConfig(String baseUrl) {
  return ProviderConfig(
    id: 'DifyTest',
    enabled: true,
    name: 'DifyTest',
    apiKey: 'test-key',
    baseUrl: baseUrl,
    providerType: ProviderKind.dify,
    models: const ['dify-chat'],
  );
}

void main() {
  group('Dify chat API', () {
    test('streams message events and reuses returned conversation id', () async {
      final receivedBodies = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        expect(request.method, 'POST');
        expect(request.uri.path, '/v1/chat-messages');
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-key',
        );
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        receivedBodies.add(body);

        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'data: ${jsonEncode({'event': 'message', 'conversation_id': 'dify-conv-1', 'answer': receivedBodies.length == 1 ? 'hel' : 'aga'})}\n\n',
        );
        request.response.write(
          'data: ${jsonEncode({'event': 'message', 'conversation_id': 'dify-conv-1', 'answer': receivedBodies.length == 1 ? 'lo' : 'in'})}\n\n',
        );
        request.response.write(
          'data: ${jsonEncode({
            'event': 'message_end',
            'conversation_id': 'dify-conv-1',
            'metadata': {
              'usage': {'prompt_tokens': 3, 'completion_tokens': 2, 'total_tokens': 5},
            },
          })}\n\n',
        );
        await request.response.close();
      });

      final baseUrl = 'http://${server.address.address}:${server.port}/v1';
      final first = await ChatApiService.sendMessageStream(
        config: _difyConfig(baseUrl),
        modelId: 'dify-chat',
        messages: const [
          {'role': 'user', 'content': 'hello'},
        ],
        extraHeaders: const {_conversationHeaderName: 'local-conv-1'},
      ).toList();
      final second = await ChatApiService.sendMessageStream(
        config: _difyConfig(baseUrl),
        modelId: 'dify-chat',
        messages: const [
          {'role': 'user', 'content': 'again'},
        ],
        extraHeaders: const {_conversationHeaderName: 'local-conv-1'},
      ).toList();

      expect(first.map((chunk) => chunk.content).join(), 'hello');
      expect(first.last.isDone, isTrue);
      expect(first.last.usage?.totalTokens, 5);
      expect(second.map((chunk) => chunk.content).join(), 'again');
      expect(receivedBodies.first['response_mode'], 'streaming');
      expect(receivedBodies.first.containsKey('conversation_id'), isFalse);
      expect(receivedBodies.last['conversation_id'], 'dify-conv-1');
    });

    test('parses blocking response', () async {
      Map<String, dynamic>? receivedBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        receivedBody =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'event': 'message',
            'conversation_id': 'dify-conv-2',
            'answer': 'blocking ok',
            'metadata': {
              'usage': {
                'prompt_tokens': 4,
                'completion_tokens': 6,
                'total_tokens': 10,
              },
            },
          }),
        );
        await request.response.close();
      });

      final chunks = await ChatApiService.sendMessageStream(
        config: _difyConfig(
          'http://${server.address.address}:${server.port}/v1',
        ),
        modelId: 'dify-chat',
        messages: const [
          {'role': 'system', 'content': 'be concise'},
          {'role': 'user', 'content': 'hello'},
        ],
        stream: false,
      ).toList();

      expect(receivedBody?['response_mode'], 'blocking');
      expect(receivedBody?['query'], contains('system: be concise'));
      expect(chunks.single.content, 'blocking ok');
      expect(chunks.single.usage?.totalTokens, 10);
    });

    test('throws on HTTP error', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write('bad dify request');
        await request.response.close();
      });

      expect(
        ChatApiService.sendMessageStream(
          config: _difyConfig(
            'http://${server.address.address}:${server.port}/v1',
          ),
          modelId: 'dify-chat',
          messages: const [
            {'role': 'user', 'content': 'hello'},
          ],
        ).toList(),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
