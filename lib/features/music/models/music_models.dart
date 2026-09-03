import '../../../l10n/app_localizations.dart';

class MusicSource {
  const MusicSource(this.value);

  final String value;

  String label(AppLocalizations l10n) => labelForSource(value, l10n);
}

class BitrateOption {
  const BitrateOption(this.value);

  final int value;
}

const musicSources = <MusicSource>[
  MusicSource('kuwo'),
  MusicSource('netease'),
  MusicSource('tencent'),
  MusicSource('tidal'),
  MusicSource('qobuz'),
  MusicSource('joox'),
  MusicSource('bilibili'),
  MusicSource('apple'),
  MusicSource('ytmusic'),
  MusicSource('spotify'),
];

const stableSearchSources = <String>{'netease', 'kuwo'};

const bitrateOptions = <BitrateOption>[
  BitrateOption(999),
  BitrateOption(740),
  BitrateOption(320),
  BitrateOption(192),
  BitrateOption(128),
];

class Track {
  const Track({
    required this.id,
    required this.name,
    required this.artists,
    required this.album,
    required this.picId,
    required this.lyricId,
    required this.source,
  });

  factory Track.fromJson(Map<String, dynamic> json, String fallbackSource) {
    final id = _readText(json['id']);
    return Track(
      id: id,
      name: _readText(json['name']),
      artists: _parseArtists(json['artist']),
      album: _readText(json['album']),
      picId: _readText(json['pic_id']),
      lyricId: _readText(json['lyric_id'], fallback: id),
      source: _readText(json['source'], fallback: fallbackSource),
    );
  }

  final String id;
  final String name;
  final List<String> artists;
  final String album;
  final String picId;
  final String lyricId;
  final String source;

  String artistText(AppLocalizations l10n) =>
      artists.isEmpty ? l10n.musicUnknownArtist : artists.join(' / ');

  String sourceLabel(AppLocalizations l10n) => labelForSource(source, l10n);
}

class SongUrl {
  const SongUrl({required this.url, required this.bitrate, required this.size});

  factory SongUrl.fromJson(Map<String, dynamic> json) {
    return SongUrl(
      url: _readText(json['url']),
      bitrate: _readInt(json['br']),
      size: _readInt(json['size']),
    );
  }

  final String url;
  final int bitrate;
  final int size;
}

class LyricLine {
  const LyricLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

String labelForSource(String source, AppLocalizations l10n) {
  return switch (source) {
    'kuwo' => l10n.musicSourceKuwo,
    'netease' => l10n.musicSourceNetease,
    'tencent' => l10n.musicSourceTencent,
    'tidal' => l10n.musicSourceTidal,
    'qobuz' => l10n.musicSourceQobuz,
    'joox' => l10n.musicSourceJoox,
    'bilibili' => l10n.musicSourceBilibili,
    'apple' => l10n.musicSourceApple,
    'ytmusic' => l10n.musicSourceYouTube,
    'spotify' => l10n.musicSourceSpotify,
    _ => source.isEmpty ? l10n.musicUnknownSource : source,
  };
}

String labelForBitrate(int bitrate, AppLocalizations l10n) {
  return switch (bitrate) {
    999 => l10n.musicBitrate24BitLossless,
    740 => l10n.musicBitrate16BitLossless,
    _ => '$bitrate ${l10n.musicBitrateKbps}',
  };
}

int normalizeBitrate(int bitrate) {
  return bitrateOptions.any((item) => item.value == bitrate)
      ? bitrate
      : bitrateOptions.first.value;
}

String _readText(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _parseArtists(Object? value) {
  final artists = <String>[];
  if (value is Iterable) {
    for (final item in value) {
      final name = item is Map ? _readText(item['name']) : _readText(item);
      if (name.isNotEmpty) {
        artists.add(name);
      }
    }
  } else if (value is Map) {
    final name = _readText(value['name']);
    if (name.isNotEmpty) {
      artists.add(name);
    }
  } else {
    final name = _readText(value);
    if (name.isNotEmpty) {
      artists.add(name);
    }
  }
  return artists;
}
