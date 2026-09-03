import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:Kelivo/features/music/controllers/music_player_controller.dart';
import 'package:Kelivo/features/music/models/music_models.dart';
import 'package:Kelivo/features/music/pages/music_page.dart';
import 'package:Kelivo/features/music/services/music_api_client.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

void main() {
  late AppLocalizations l10n;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('loads the music page and completes a bounded search', (
    tester,
  ) async {
    final api = _FakeMusicApiClient(searchResult: const <Track>[_track]);
    final player = MusicPlayerController(_FakeAudioHandler(), api);
    addTearDown(player.dispose);

    await tester.pumpWidget(_testApp(api: api, player: player));
    await tester.pumpAndSettle();

    expect(find.text('LF Music'), findsOneWidget);
    expect(find.text('Music source'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(2), '999');
    await tester.enterText(find.byType(TextField).first, 'demo');
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.text('Demo song'), findsOneWidget);
    expect(api.lastCount, 50);
  });

  testWidgets('rejects an empty keyword and exposes search failures', (
    tester,
  ) async {
    final api = _FakeMusicApiClient(
      searchError: const MusicApiException(
        MusicApiErrorKind.searchNetwork,
        source: 'netease',
      ),
    );
    final player = MusicPlayerController(_FakeAudioHandler(), api);
    addTearDown(player.dispose);

    await tester.pumpWidget(_testApp(api: api, player: player));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pump();
    expect(find.text('Enter a search keyword'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'demo');
    await tester.tap(find.widgetWithText(FilledButton, 'Search'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Search failed'), findsOneWidget);
    expect(find.textContaining('check your network'), findsOneWidget);
  });

  test('moves from track selection to playable and completed states', () async {
    final api = _FakeMusicApiClient();
    final handler = _FakeAudioHandler();
    final player = MusicPlayerController(handler, api);
    addTearDown(player.dispose);

    await player.playTrack(_track, 999, l10n);

    expect(player.currentTrack, _track);
    expect(player.playable, isTrue);
    expect(player.playing, isTrue);
    expect(player.currentSongUrl, 'https://example.com/demo.mp3');

    handler.playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.completed,
        playing: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(player.playing, isFalse);
    expect(player.status, contains('Playback complete'));
  });

  test('empty batch download is rejected before opening a picker', () async {
    final player = MusicPlayerController(
      _FakeAudioHandler(),
      _FakeMusicApiClient(),
    );
    addTearDown(player.dispose);

    await player.downloadTracks(const <Track>[], 999, l10n);

    expect(player.downloading, isFalse);
    expect(player.status, 'Select songs to download');
  });
}

Widget _testApp({
  required MusicApiClient api,
  required MusicPlayerController player,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: MusicHomeContent(api: api, player: player),
    ),
  );
}

const _track = Track(
  id: 'track-1',
  name: 'Demo song',
  artists: <String>['Demo artist'],
  album: 'Demo album',
  picId: '',
  lyricId: '',
  source: 'netease',
);

class _FakeMusicApiClient extends MusicApiClient {
  _FakeMusicApiClient({this.searchResult = const <Track>[], this.searchError});

  final List<Track> searchResult;
  final Object? searchError;
  int? lastCount;

  @override
  Future<List<Track>> search({
    required String source,
    required String keyword,
    required int count,
    required int page,
  }) async {
    lastCount = count;
    final error = searchError;
    if (error != null) {
      throw error;
    }
    return searchResult;
  }

  @override
  Future<SongUrl> fetchSongUrl(Track track, int bitrate) async {
    return const SongUrl(
      url: 'https://example.com/demo.mp3',
      bitrate: 999,
      size: 1024,
    );
  }

  @override
  Future<String?> fetchAlbumUrl(Track track) async => null;

  @override
  Future<List<LyricLine>> fetchLyrics(Track track) async => const <LyricLine>[];
}

class _FakeAudioHandler extends BaseAudioHandler {
  @override
  Future<void> playMediaItem(MediaItem item) async {
    mediaItem.add(item);
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.ready, playing: true),
    );
  }

  @override
  Future<void> play() async {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.ready,
        playing: true,
      ),
    );
  }

  @override
  Future<void> pause() async {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.ready,
        playing: false,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    playbackState.add(playbackState.value.copyWith(updatePosition: position));
  }
}
