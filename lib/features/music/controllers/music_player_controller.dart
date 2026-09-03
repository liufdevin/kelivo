import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../l10n/app_localizations.dart';
import '../models/music_models.dart';
import '../services/download_saver.dart';
import '../services/music_api_client.dart';

class MusicPlayerController extends ChangeNotifier {
  MusicPlayerController(this._audioHandler, this._api) {
    _subscriptions = <StreamSubscription<dynamic>>[
      _audioHandler.playbackState.listen(_handlePlaybackState),
      _audioHandler.mediaItem.listen(_handleMediaItem),
    ];
  }

  static const _trackIdKey = 'trackId';
  static const _artistsKey = 'artists';
  static const _albumKey = 'album';
  static const _picIdKey = 'picId';
  static const _lyricIdKey = 'lyricId';
  static const _sourceKey = 'source';
  static const _requestedBitrateKey = 'requestedBitrate';
  static const _actualBitrateKey = 'actualBitrate';

  final AudioHandler _audioHandler;
  final MusicApiClient _api;
  final http.Client _downloadClient = http.Client();
  late final List<StreamSubscription<dynamic>> _subscriptions;

  Track? currentTrack;
  String? albumUrl;
  Uint8List? albumBytes;
  List<LyricLine> lyrics = const <LyricLine>[];
  String? currentSongUrl;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  bool preparing = false;
  bool playable = false;
  bool downloading = false;
  int downloadTotal = 0;
  int downloadCompleted = 0;
  String status = '';
  int requestedBitrate = bitrateOptions.first.value;
  int actualBitrate = 0;

  AppLocalizations? _l10n;
  int _playRequest = 0;
  bool _receivedInitialMediaItem = false;
  PlaybackState _lastPlaybackState = PlaybackState();
  Timer? _positionTimer;

  void bindLocalizations(AppLocalizations l10n) {
    _l10n = l10n;
  }

  Future<void> playTrack(
    Track track,
    int bitrate,
    AppLocalizations l10n,
  ) async {
    bindLocalizations(l10n);
    final request = ++_playRequest;
    requestedBitrate = normalizeBitrate(bitrate);
    actualBitrate = 0;
    currentTrack = track;
    albumUrl = null;
    albumBytes = null;
    lyrics = const <LyricLine>[];
    currentSongUrl = null;
    position = Duration.zero;
    duration = Duration.zero;
    playing = false;
    preparing = true;
    playable = false;
    status =
        '${l10n.musicStatusGettingPlaybackUrl}: '
        '${labelForBitrate(requestedBitrate, l10n)}';
    notifyListeners();

    unawaited(_loadLyrics(track, request, l10n));
    final albumUrlFuture = _loadAlbumUrl(track, request);
    try {
      final songUrl = await _api.fetchSongUrl(track, requestedBitrate);
      if (!_isCurrentRequest(track, request)) {
        return;
      }
      if (songUrl.url.trim().isEmpty) {
        throw const MusicApiException(MusicApiErrorKind.invalidResponse);
      }
      final artUrl = await albumUrlFuture;
      currentSongUrl = songUrl.url;
      actualBitrate = songUrl.bitrate;
      status = '${l10n.musicStatusBuffering}: ${track.name}';
      notifyListeners();

      await _audioHandler.playMediaItem(
        _mediaItemForTrack(track, songUrl, artUrl, l10n),
      );
      if (!_isCurrentRequest(track, request)) {
        return;
      }
      preparing = false;
      playable = true;
      playing = true;
      final actual = actualBitrate > 0 ? actualBitrate : requestedBitrate;
      status =
          '${l10n.musicStatusPlaying}: ${track.name} '
          '(${labelForBitrate(actual, l10n)})';
      notifyListeners();
    } catch (error) {
      if (!_isCurrentRequest(track, request)) {
        return;
      }
      preparing = false;
      playable = false;
      playing = false;
      status =
          '${l10n.musicStatusPlayFailed}: '
          '${describeMusicError(error, l10n)}';
      notifyListeners();
    }
  }

  Future<void> togglePlayback(AppLocalizations l10n) async {
    bindLocalizations(l10n);
    if (!playable) {
      return;
    }
    try {
      if (playing) {
        await _audioHandler.pause();
        playing = false;
        preparing = false;
        playable = currentSongUrl != null;
        status = l10n.musicStatusPaused;
      } else {
        playing = true;
        preparing = false;
        playable = true;
        if (_lastPlaybackState.processingState ==
            AudioProcessingState.completed) {
          position = Duration.zero;
        }
        status = currentTrack == null
            ? l10n.musicStatusPlaying
            : '${l10n.musicStatusPlaying}: ${currentTrack!.name}';
        _updatePositionTimer();
        notifyListeners();
        await _audioHandler.play();
      }
      _updatePositionTimer();
      notifyListeners();
    } catch (error) {
      playing = false;
      preparing = false;
      status =
          '${l10n.musicStatusPlayerError}: '
          '${describeMusicError(error, l10n)}';
      notifyListeners();
    }
  }

  Future<void> seekTo(Duration value, AppLocalizations l10n) async {
    bindLocalizations(l10n);
    if (!playable) {
      return;
    }
    try {
      await _audioHandler.seek(value);
      position = value;
      notifyListeners();
    } catch (error) {
      status =
          '${l10n.musicStatusSeekFailed}: '
          '${describeMusicError(error, l10n)}';
      notifyListeners();
    }
  }

  Future<void> downloadCurrent(AppLocalizations l10n) async {
    final track = currentTrack;
    if (track == null) {
      status = l10n.musicStatusSelectTrackFirst;
      notifyListeners();
      return;
    }
    await downloadTrack(track, requestedBitrate, l10n);
  }

  Future<void> downloadTrack(
    Track track,
    int bitrate,
    AppLocalizations l10n,
  ) async {
    bindLocalizations(l10n);
    if (downloading) {
      return;
    }
    final selectedBitrate = normalizeBitrate(bitrate);
    downloading = true;
    downloadTotal = 1;
    downloadCompleted = 0;
    status =
        '${l10n.musicStatusPreparingDownload}: ${track.name} '
        '(${labelForBitrate(selectedBitrate, l10n)})';
    notifyListeners();
    try {
      final url = await _resolveDownloadUrl(track, selectedBitrate);
      final fileName = _downloadFileName(track, url, l10n);
      status = '${l10n.musicStatusDownloading}: $fileName';
      notifyListeners();
      final saved = await _saveDownload(
        url: url,
        fileName: fileName,
        l10n: l10n,
      );
      if (saved == null) {
        status = l10n.musicStatusDownloadCancelled;
        return;
      }
      downloadCompleted = 1;
      status = '${l10n.musicStatusSaved}: ${saved.displayPath}';
    } catch (error) {
      status =
          '${l10n.musicStatusDownloadFailed}: '
          '${describeMusicError(error, l10n)}';
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  Future<void> downloadTracks(
    List<Track> tracks,
    int bitrate,
    AppLocalizations l10n,
  ) async {
    bindLocalizations(l10n);
    if (tracks.isEmpty) {
      status = l10n.musicStatusSelectTracks;
      notifyListeners();
      return;
    }
    if (downloading) {
      return;
    }
    final directory = await pickBatchDownloadDirectory(
      confirmButtonText: l10n.musicChooseSaveDirectory,
    );
    if (directory == null) {
      status = l10n.musicStatusBatchCancelled;
      notifyListeners();
      return;
    }

    final selectedBitrate = normalizeBitrate(bitrate);
    final usedNames = <String>{};
    final failures = <String>[];
    downloading = true;
    downloadTotal = tracks.length;
    downloadCompleted = 0;
    status =
        '${l10n.musicStatusBatchPreparing}: '
        '${tracks.length} ${l10n.musicTrackUnit}';
    notifyListeners();
    try {
      for (final track in tracks) {
        final index = downloadCompleted + 1;
        status =
            '${l10n.musicStatusDownloading} $index/${tracks.length}: '
            '${track.name}';
        notifyListeners();
        try {
          final url = await _resolveDownloadUrl(track, selectedBitrate);
          final fileName = _uniqueFileName(
            _downloadFileName(track, url, l10n),
            usedNames,
          );
          final saved = await _saveDownload(
            url: url,
            fileName: fileName,
            targetPath: path.join(directory, fileName),
            l10n: l10n,
          );
          if (saved == null) {
            failures.add('${track.name}: ${l10n.musicStatusDownloadCancelled}');
          }
        } catch (error) {
          failures.add('${track.name}: ${describeMusicError(error, l10n)}');
        } finally {
          downloadCompleted += 1;
          notifyListeners();
        }
      }
      final success = tracks.length - failures.length;
      status =
          '${l10n.musicStatusBatchComplete}: '
          '$success ${l10n.musicTrackUnit}';
      if (failures.isNotEmpty) {
        status =
            '$status, ${l10n.musicFailed}: ${failures.length} '
            '(${failures.first})';
      }
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  Future<String?> _loadAlbumUrl(Track track, int request) async {
    try {
      final url = await _api.fetchAlbumUrl(track);
      if (_isCurrentRequest(track, request)) {
        albumUrl = url;
        albumBytes = null;
        notifyListeners();
      }
      if (url != null && url.isNotEmpty) {
        unawaited(_loadAlbumBytes(track, request, url));
      }
      return url;
    } catch (error, stackTrace) {
      debugPrint('Music album URL load failed: $error\n$stackTrace');
      if (_isCurrentRequest(track, request)) {
        albumBytes = null;
        notifyListeners();
      }
      return null;
    }
  }

  Future<void> _loadAlbumBytes(Track track, int request, String url) async {
    try {
      final bytes = await _api.fetchAlbumBytes(url);
      if (_isCurrentRequest(track, request)) {
        albumBytes = bytes;
        notifyListeners();
      }
    } catch (error, stackTrace) {
      debugPrint('Music album image load failed: $error\n$stackTrace');
      if (_isCurrentRequest(track, request)) {
        albumBytes = null;
        notifyListeners();
      }
    }
  }

  Future<void> _loadLyrics(
    Track track,
    int request,
    AppLocalizations l10n,
  ) async {
    try {
      final lines = await _api.fetchLyrics(track);
      if (_isCurrentRequest(track, request)) {
        lyrics = lines;
        notifyListeners();
      }
    } catch (error) {
      if (_isCurrentRequest(track, request)) {
        lyrics = const <LyricLine>[];
        status =
            '${l10n.musicStatusLyricsFailed}: '
            '${describeMusicError(error, l10n)}';
        notifyListeners();
      }
    }
  }

  MediaItem _mediaItemForTrack(
    Track track,
    SongUrl songUrl,
    String? artUrl,
    AppLocalizations l10n,
  ) {
    return MediaItem(
      id: songUrl.url,
      title: track.name.isEmpty ? l10n.musicUnknownTrack : track.name,
      artist: track.artistText(l10n),
      album: track.album.isEmpty ? l10n.musicUnknownAlbum : track.album,
      artUri: artUrl == null || artUrl.isEmpty ? null : Uri.parse(artUrl),
      extras: <String, dynamic>{
        _trackIdKey: track.id,
        _artistsKey: track.artists,
        _albumKey: track.album,
        _picIdKey: track.picId,
        _lyricIdKey: track.lyricId,
        _sourceKey: track.source,
        _requestedBitrateKey: requestedBitrate,
        _actualBitrateKey: songUrl.bitrate,
      },
    );
  }

  Future<String> _resolveDownloadUrl(Track track, int bitrate) async {
    if (identical(track, currentTrack) &&
        currentSongUrl != null &&
        requestedBitrate == bitrate) {
      return currentSongUrl!;
    }
    final songUrl = await _api.fetchSongUrl(track, bitrate);
    if (songUrl.url.trim().isEmpty) {
      throw const MusicApiException(MusicApiErrorKind.invalidResponse);
    }
    return songUrl.url;
  }

  Future<SavedDownload?> _saveDownload({
    required String url,
    required String fileName,
    required AppLocalizations l10n,
    String? targetPath,
  }) async {
    final response = await _downloadClient
        .get(
          Uri.parse(url),
          headers: const {'User-Agent': 'Mozilla/5.0 Flutter GD Music'},
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MusicApiException(
        MusicApiErrorKind.http,
        statusCode: response.statusCode,
      );
    }
    return saveDownloadBytes(
      bytes: response.bodyBytes,
      fileName: fileName,
      mimeType: response.headers['content-type'] ?? 'audio/mpeg',
      audioTypeLabel: l10n.musicAudioFileType,
      confirmButtonText: l10n.musicSave,
      androidSaveError: l10n.musicErrorAndroidSave,
      targetPath: targetPath,
    );
  }

  void _handleMediaItem(MediaItem? item) {
    if (!_receivedInitialMediaItem) {
      _receivedInitialMediaItem = true;
      if (item == null) {
        return;
      }
    }
    if (item == null) {
      currentTrack = null;
      albumUrl = null;
      albumBytes = null;
      lyrics = const <LyricLine>[];
      currentSongUrl = null;
      duration = Duration.zero;
      position = Duration.zero;
      playable = false;
      preparing = false;
      playing = false;
      _updatePositionTimer();
      notifyListeners();
      return;
    }

    duration = item.duration ?? duration;
    currentSongUrl = item.id;
    albumUrl = item.artUri?.toString();
    actualBitrate = _readIntExtra(item, _actualBitrateKey, actualBitrate);
    requestedBitrate = _readIntExtra(
      item,
      _requestedBitrateKey,
      requestedBitrate,
    );
    final restoredTrack = _trackFromMediaItem(item);
    if (currentTrack == null ||
        (restoredTrack != null && restoredTrack.id != currentTrack!.id)) {
      currentTrack = restoredTrack;
      albumBytes = null;
      lyrics = const <LyricLine>[];
      final request = ++_playRequest;
      final l10n = _l10n;
      if (restoredTrack != null && l10n != null) {
        unawaited(_loadLyrics(restoredTrack, request, l10n));
        if (albumUrl != null) {
          unawaited(_loadAlbumBytes(restoredTrack, request, albumUrl!));
        }
      }
    }
    notifyListeners();
  }

  void _handlePlaybackState(PlaybackState state) {
    _lastPlaybackState = state;
    position = state.position;
    playing = state.playing;
    preparing =
        state.processingState == AudioProcessingState.loading ||
        state.processingState == AudioProcessingState.buffering;
    playable =
        currentSongUrl != null &&
        state.processingState != AudioProcessingState.error;
    final l10n = _l10n;
    if (state.processingState == AudioProcessingState.completed) {
      playing = false;
      preparing = false;
      position = duration;
      if (l10n != null) {
        status = currentTrack == null
            ? l10n.musicStatusPlaybackComplete
            : '${l10n.musicStatusPlaybackComplete}: ${currentTrack!.name}';
      }
    } else if (state.processingState == AudioProcessingState.error) {
      playing = false;
      preparing = false;
      playable = false;
      if (l10n != null) {
        status =
            '${l10n.musicStatusPlayerError}: '
            '${state.errorMessage ?? l10n.musicUnknownError}';
      }
    }
    _updatePositionTimer();
    notifyListeners();
  }

  void _updatePositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
    if (!playing) {
      return;
    }
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final nextPosition = _lastPlaybackState.position;
      if (nextPosition != position) {
        position = nextPosition;
        notifyListeners();
      }
    });
  }

  Track? _trackFromMediaItem(MediaItem item) {
    final extras = item.extras;
    final id = extras?[_trackIdKey]?.toString() ?? '';
    if (extras == null || id.isEmpty) {
      return null;
    }
    return Track(
      id: id,
      name: item.title,
      artists: _readArtists(extras[_artistsKey], item.artist),
      album: extras[_albumKey]?.toString() ?? item.album ?? '',
      picId: extras[_picIdKey]?.toString() ?? '',
      lyricId: extras[_lyricIdKey]?.toString() ?? id,
      source: extras[_sourceKey]?.toString() ?? '',
    );
  }

  List<String> _readArtists(Object? value, String? fallback) {
    if (value is Iterable) {
      final artists = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (artists.isNotEmpty) {
        return artists;
      }
    }
    final text = fallback?.trim() ?? '';
    return text.isEmpty ? const <String>[] : text.split(' / ');
  }

  int _readIntExtra(MediaItem item, String key, int fallback) {
    final value = item.extras?[key];
    return value is int
        ? value
        : int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool _isCurrentRequest(Track track, int request) =>
      _playRequest == request && currentTrack?.id == track.id;

  String _downloadFileName(Track track, String url, AppLocalizations l10n) {
    final title = track.name.isEmpty ? l10n.musicUnknownTrack : track.name;
    return '${_safeFileName('${track.artistText(l10n)} - $title')}${_extensionFromUrl(url)}';
  }

  String _safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'kelivo_music' : cleaned;
  }

  String _extensionFromUrl(String url) {
    final pathText = Uri.tryParse(url)?.path ?? '';
    final dot = pathText.lastIndexOf('.');
    if (dot >= 0 && dot < pathText.length - 1) {
      final extension = pathText.substring(dot);
      if (extension.length <= 6) {
        return extension;
      }
    }
    return '.mp3';
  }

  String _uniqueFileName(String fileName, Set<String> usedNames) {
    if (usedNames.add(fileName)) {
      return fileName;
    }
    final extension = path.extension(fileName);
    final baseName = path.basenameWithoutExtension(fileName);
    var index = 2;
    while (true) {
      final next = '$baseName ($index)$extension';
      if (usedNames.add(next)) {
        return next;
      }
      index += 1;
    }
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _downloadClient.close();
    super.dispose();
  }
}
