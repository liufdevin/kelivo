import 'dart:convert';
import 'dart:io';

import 'package:Kelivo/core/services/network/dio_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('forwards multipart requests with explicit content type', () async {
    late Map<String, String> capturedHeaders;
    late String capturedBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handling = server.first.then((request) async {
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });
      capturedHeaders = headers;
      final bodyBytes = await request.fold<List<int>>(<int>[], (all, chunk) {
        all.addAll(chunk);
        return all;
      });
      capturedBody = latin1.decode(bodyBytes);
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"ok":true}');
      await request.response.close();
    });

    final client = DioHttpClient();
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://127.0.0.1:${server.port}/upload'),
      );
      request.fields['prompt'] = 'turn it blue';
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
          ),
          filename: 'input.png',
        ),
      );

      final response = await http.Response.fromStream(
        await client.send(request),
      );

      expect(response.statusCode, 200);
      expect(
        capturedHeaders['content-type'],
        startsWith('multipart/form-data'),
      );
      expect(capturedBody, contains('name="prompt"'));
      expect(capturedBody, contains('name="image"'));
      await handling;
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
}
