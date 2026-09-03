import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audioplayers/audioplayers.dart' as ap;

/// Windows/Linux playback backend.
///
/// `audio_service` has no native Windows implementation and `just_audio`
/// requires an additional desktop implementation. Kelivo already ships
/// `audioplayers`, which supports both targets, so desktop playback uses it
/// while retaining the same AudioHandler contract as mobile and macOS.
class GdDesktopAudioHandler extends BaseAudioHandler with SeekHandler {
  GdDesktopAudioHandler() {
    _subscriptions
      ..add(_player.onPlayerStateChanged.listen(_handlePlayerState))
      ..add(_player.onDurationChanged.listen(_handleDuration))
      ..add(_player.onPositionChanged.listen(_handlePosition))
      ..add(_player.onPlayerComplete.listen((_) => _handleComplete()));
  }

  final ap.AudioPlayer _player = ap.AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _currentUrl;

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
    _currentUrl = mediaItem.id;
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: true,
        controls: _controls(playing: true),
        systemActions: const {MediaAction.seek},
      ),
    );
    try {
      await _player.play(ap.UrlSource(mediaItem.id));
      _broadcast(processingState: AudioProcessingState.ready, playing: true);
    } catch (error) {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          playing: false,
          errorMessage: error.toString(),
          controls: _controls(playing: false),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    final url = _currentUrl;
    if (_player.state == ap.PlayerState.completed ||
        _player.state == ap.PlayerState.stopped) {
      if (url == null) {
        return;
      }
      await _player.play(ap.UrlSource(url));
    } else {
      await _player.resume();
    }
    _broadcast(processingState: AudioProcessingState.ready, playing: true);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _broadcast(processingState: AudioProcessingState.ready, playing: false);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcast(
      processingState: AudioProcessingState.ready,
      playing: _player.state == ap.PlayerState.playing,
      position: position,
    );
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _currentUrl = null;
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
        controls: const <MediaControl>[],
        systemActions: const <MediaAction>{},
        updatePosition: Duration.zero,
      ),
    );
  }

  Future<void> disposeHandler() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
  }

  void _handlePlayerState(ap.PlayerState state) {
    final processingState = switch (state) {
      ap.PlayerState.completed => AudioProcessingState.completed,
      ap.PlayerState.disposed ||
      ap.PlayerState.stopped => AudioProcessingState.idle,
      ap.PlayerState.playing ||
      ap.PlayerState.paused => AudioProcessingState.ready,
    };
    _broadcast(
      processingState: processingState,
      playing: state == ap.PlayerState.playing,
    );
  }

  void _handleDuration(Duration duration) {
    final item = mediaItem.valueOrNull;
    if (item != null && item.duration != duration) {
      mediaItem.add(item.copyWith(duration: duration));
    }
  }

  void _handlePosition(Duration position) {
    _broadcast(
      processingState: AudioProcessingState.ready,
      playing: _player.state == ap.PlayerState.playing,
      position: position,
    );
  }

  void _handleComplete() {
    _broadcast(processingState: AudioProcessingState.completed, playing: false);
  }

  void _broadcast({
    required AudioProcessingState processingState,
    required bool playing,
    Duration? position,
  }) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: _controls(playing: playing),
        systemActions: const {MediaAction.seek},
        processingState: processingState,
        playing: playing,
        updatePosition: position ?? playbackState.value.position,
        speed: 1,
      ),
    );
  }

  List<MediaControl> _controls({required bool playing}) => <MediaControl>[
    if (playing) MediaControl.pause else MediaControl.play,
    MediaControl.stop,
  ];
}
