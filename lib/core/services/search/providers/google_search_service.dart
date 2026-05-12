import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class GoogleSearchService extends SearchService<GoogleSearchOptions> {
  @override
  String get name => 'Google';

  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(
      l10n.searchProviderGoogleDescription,
      style: const TextStyle(fontSize: 12),
    );
  }

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required GoogleSearchOptions serviceOptions,
  }) async {
    final searchEngineId = serviceOptions.searchEngineId.trim();
    if (searchEngineId.isEmpty) {
      throw Exception('Google search engine ID is required');
    }

    try {
      final uri = Uri.https('www.googleapis.com', '/customsearch/v1', {
        'key': serviceOptions.apiKey,
        'cx': searchEngineId,
        'q': query,
        'num': commonOptions.resultSize.clamp(1, 10).toString(),
      });

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(Duration(milliseconds: commonOptions.timeout));

      if (response.statusCode != 200) {
        throw Exception('API request failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawItems = data['items'] as List? ?? const <dynamic>[];
      final items = rawItems
          .whereType<Map>()
          .map(
            (item) => SearchResultItem(
              title: (item['title'] ?? '').toString(),
              url: (item['link'] ?? '').toString(),
              text: (item['snippet'] ?? '').toString(),
            ),
          )
          .where((item) => item.title.isNotEmpty || item.url.isNotEmpty)
          .take(commonOptions.resultSize)
          .toList();

      return SearchResult(items: items);
    } catch (e) {
      throw Exception('Google search failed: $e');
    }
  }
}
