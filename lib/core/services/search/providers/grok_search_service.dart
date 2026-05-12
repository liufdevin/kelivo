import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class GrokSearchService extends SearchService<GrokSearchOptions> {
  @override
  String get name => 'Grok';

  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(
      l10n.searchProviderGrokDescription,
      style: const TextStyle(fontSize: 12),
    );
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required GrokSearchOptions serviceOptions,
  }) async {
    try {
      final body = <String, dynamic>{
        'model': serviceOptions.resolvedModel,
        'messages': [
          {
            'role': 'system',
            'content':
                'Search the web and summarize the most relevant sourced results.',
          },
          {'role': 'user', 'content': query},
        ],
        'search_parameters': {'mode': 'on', 'return_citations': true},
      };

      final response = await http
          .post(
            Uri.parse(serviceOptions.resolvedUrl),
            headers: {
              'Authorization': 'Bearer ${serviceOptions.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(Duration(milliseconds: commonOptions.timeout));

      if (response.statusCode != 200) {
        throw Exception('API request failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final message = _firstMessage(data);
      final answer = _contentToText(message?['content']).trim();
      final citations = _citationList(data, message);
      final items = <SearchResultItem>[];

      for (var i = 0; i < citations.length; i++) {
        final url = citations[i].trim();
        if (url.isEmpty) continue;
        items.add(SearchResultItem(title: url, url: url, text: answer));
      }

      if (items.isEmpty && answer.isNotEmpty) {
        items.add(
          SearchResultItem(
            title: name,
            url: serviceOptions.resolvedUrl,
            text: answer,
          ),
        );
      }

      return SearchResult(
        answer: answer.isEmpty ? null : answer,
        items: items.take(commonOptions.resultSize).toList(),
      );
    } catch (e) {
      throw Exception('Grok search failed: $e');
    }
  }

  Map<String, dynamic>? _firstMessage(Map<String, dynamic> data) {
    final choices = data['choices'] as List? ?? const <dynamic>[];
    if (choices.isEmpty || choices.first is! Map) return null;
    final message = (choices.first as Map)['message'];
    if (message is Map<String, dynamic>) return message;
    if (message is Map) return message.cast<String, dynamic>();
    return null;
  }

  String _contentToText(dynamic content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List) {
      return content
          .map((part) {
            if (part is String) return part;
            if (part is Map && part['text'] != null) return part['text'];
            return '';
          })
          .where((part) => part.toString().isNotEmpty)
          .join('\n');
    }
    return content.toString();
  }

  List<String> _citationList(
    Map<String, dynamic> data,
    Map<String, dynamic>? message,
  ) {
    final raw = data['citations'] ?? message?['citations'];
    if (raw is! List) return const <String>[];
    return raw.map((item) => item.toString()).toList();
  }
}
