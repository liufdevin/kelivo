import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../l10n/app_localizations.dart';
import '../models/music_models.dart';

enum MusicApiErrorKind {
  http,
  coverHttp,
  emptyResponse,
  invalidJson,
  invalidResponse,
  searchUnavailable,
  searchNetwork,
  unexpected,
}

class MusicApiException implements Exception {
  const MusicApiException(
    this.kind, {
    this.detail = '',
    this.statusCode,
    this.source = '',
  });

  final MusicApiErrorKind kind;
  final String detail;
  final int? statusCode;
  final String source;
}

class MusicApiClient {
  MusicApiClient({http.Client? client}) : _client = client ?? http.Client();

  static const apiEndpoint = 'https://music-api.gdstudio.xyz/api.php';
  static const _jsonHeaders = <String, String>{
    'Accept': 'application/json,text/plain,*/*',
    'User-Agent': 'Mozilla/5.0 Flutter GD Music',
  };
  static const _imageHeaders = <String, String>{
    'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*',
    'User-Agent': 'Mozilla/5.0 Flutter GD Music',
  };
  static final _lrcTime = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?]');

  final http.Client _client;

  Future<List<Track>> search({
    required String source,
    required String keyword,
    required int count,
    required int page,
  }) async {
    final uri = _buildUri({
      'types': 'search',
      'source': source,
      'name': keyword,
      'count': count.toString(),
      'pages': page.toString(),
    });
    try {
      final value = await _getJson(uri);
      return _parseSearchResult(value, source);
    } catch (error) {
      final detail = error is MusicApiException
          ? _technicalDescription(error)
          : error.toString();
      throw MusicApiException(
        stableSearchSources.contains(source)
            ? MusicApiErrorKind.searchNetwork
            : MusicApiErrorKind.searchUnavailable,
        detail: detail,
        source: source,
      );
    }
  }

  Future<SongUrl> fetchSongUrl(Track track, int bitrate) async {
    final uri = _buildUri({
      'types': 'url',
      'source': track.source,
      'id': track.id,
      'br': normalizeBitrate(bitrate).toString(),
    });
    return SongUrl.fromJson(_objectFromResponse(await _getJson(uri)));
  }

  Future<String?> fetchAlbumUrl(Track track) async {
    if (track.picId.isEmpty) {
      return null;
    }
    final uri = _buildUri({
      'types': 'pic',
      'source': track.source,
      'id': track.picId,
      'size': '500',
    });
    final object = _objectFromResponse(await _getJson(uri));
    final url = object['url']?.toString().trim() ?? '';
    return url.isEmpty ? null : url;
  }

  Future<Uint8List?> fetchAlbumBytes(String url) async {
    if (url.trim().isEmpty) {
      return null;
    }
    final response = await _client
        .get(Uri.parse(url), headers: _imageHeaders)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MusicApiException(
        MusicApiErrorKind.coverHttp,
        statusCode: response.statusCode,
        detail: _trimForStatus(
          utf8.decode(response.bodyBytes, allowMalformed: true),
        ),
      );
    }
    return response.bodyBytes.isEmpty ? null : response.bodyBytes;
  }

  Future<List<LyricLine>> fetchLyrics(Track track) async {
    if (track.lyricId.isEmpty) {
      return const <LyricLine>[];
    }
    final uri = _buildUri({
      'types': 'lyric',
      'source': track.source,
      'id': track.lyricId,
    });
    final object = _objectFromResponse(await _getJson(uri));
    return _parseLyrics(
      object['lyric']?.toString() ?? '',
      object['tlyric']?.toString() ?? '',
    );
  }

  void close() => _client.close();

  Uri _buildUri(Map<String, String> queryParameters) =>
      Uri.parse(apiEndpoint).replace(queryParameters: queryParameters);

  Future<dynamic> _getJson(Uri uri) async {
    final response = await _client
        .get(uri, headers: _jsonHeaders)
        .timeout(const Duration(seconds: 20));
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MusicApiException(
        MusicApiErrorKind.http,
        statusCode: response.statusCode,
        detail: _trimForStatus(body),
      );
    }
    if (body.isEmpty) {
      throw const MusicApiException(MusicApiErrorKind.emptyResponse);
    }
    try {
      return jsonDecode(body);
    } on FormatException catch (error) {
      throw MusicApiException(
        MusicApiErrorKind.invalidJson,
        detail: error.message,
      );
    }
  }

  List<Track> _parseSearchResult(dynamic value, String fallbackSource) {
    final List<dynamic> rows;
    if (value is List) {
      rows = value;
    } else if (value is Map<String, dynamic>) {
      rows = value['data'] is List
          ? value['data'] as List<dynamic>
          : value['result'] is List
          ? value['result'] as List<dynamic>
          : <dynamic>[value];
    } else {
      rows = const <dynamic>[];
    }
    return <Track>[
      for (final row in rows)
        if (row is Map)
          Track.fromJson(Map<String, dynamic>.from(row), fallbackSource),
    ].where((track) => track.id.isNotEmpty).toList(growable: false);
  }

  Map<String, dynamic> _objectFromResponse(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    throw const MusicApiException(MusicApiErrorKind.invalidResponse);
  }

  List<LyricLine> _parseLyrics(String lyric, String translated) {
    final originals = _parseLrcMap(lyric);
    final translations = _parseLrcMap(translated);
    final lines = <LyricLine>[];
    for (final entry in originals.entries) {
      var text = entry.value;
      final translation = translations[entry.key]?.trim();
      if (translation != null &&
          translation.isNotEmpty &&
          translation != text.trim()) {
        text = '$text\n$translation';
      }
      if (text.trim().isNotEmpty) {
        lines.add(LyricLine(time: entry.key, text: text.trim()));
      }
    }
    lines.sort((left, right) => left.time.compareTo(right.time));
    return lines;
  }

  Map<Duration, String> _parseLrcMap(String lrc) {
    final result = <Duration, String>{};
    for (final row in lrc.split(RegExp(r'\r?\n'))) {
      final matches = _lrcTime.allMatches(row).toList();
      if (matches.isEmpty) {
        continue;
      }
      final text = row.substring(matches.last.end).trim();
      for (final match in matches) {
        result[_parseTime(match)] = text;
      }
    }
    return result;
  }

  Duration _parseTime(RegExpMatch match) {
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final fraction = match.group(3) ?? '';
    var milliseconds = (minutes * 60 + seconds) * 1000;
    if (fraction.length == 1) {
      milliseconds += int.parse(fraction) * 100;
    } else if (fraction.length == 2) {
      milliseconds += int.parse(fraction) * 10;
    } else if (fraction.length >= 3) {
      milliseconds += int.parse(fraction.substring(0, 3));
    }
    return Duration(milliseconds: milliseconds);
  }

  String _technicalDescription(MusicApiException error) {
    final status = error.statusCode;
    final parts = <String>[
      if (status != null) 'HTTP $status',
      if (error.detail.isNotEmpty) error.detail,
    ];
    return parts.join(': ');
  }

  String _trimForStatus(String text) {
    final singleLine = text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return singleLine.length <= 120
        ? singleLine
        : '${singleLine.substring(0, 120)}...';
  }
}

String describeMusicError(Object error, AppLocalizations l10n) {
  if (error is! MusicApiException) {
    return '${l10n.musicErrorUnexpected}: $error';
  }
  final source = labelForSource(error.source, l10n);
  final status = error.statusCode == null ? '' : ' HTTP ${error.statusCode}';
  final detail = error.detail.isEmpty ? '' : ': ${error.detail}';
  return switch (error.kind) {
    MusicApiErrorKind.http => '${l10n.musicErrorRequestFailed}$status$detail',
    MusicApiErrorKind.coverHttp =>
      '${l10n.musicErrorCoverDownloadFailed}$status$detail',
    MusicApiErrorKind.emptyResponse => l10n.musicErrorEmptyResponse,
    MusicApiErrorKind.invalidJson => '${l10n.musicErrorInvalidJson}$detail',
    MusicApiErrorKind.invalidResponse => l10n.musicErrorInvalidResponse,
    MusicApiErrorKind.searchUnavailable =>
      '${l10n.musicErrorSourceUnavailable}: $source$detail',
    MusicApiErrorKind.searchNetwork =>
      '${l10n.musicErrorSearchNetwork}: $source$detail',
    MusicApiErrorKind.unexpected => '${l10n.musicErrorUnexpected}$detail',
  };
}
