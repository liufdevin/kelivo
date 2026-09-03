import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as ja;

class GdAudioHandler extends BaseAudioHandler with SeekHandler {
  GdAudioHandler() {
    unawaited(_init());
  }

  final ja.AudioPlayer _player = ja.AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _subscriptions
      ..add(_player.playbackEventStream.listen(_broadcastState))
      ..add(_player.durationStream.listen(_updateDuration))
      ..add(
        _player.processingStateStream.listen((state) {
          if (state == ja.ProcessingState.completed) {
            _broadcastState(_player.playbackEvent);
          }
        }),
      );
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: true,
        controls: _controls(playing: true),
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1],
      ),
    );
    try {
      final duration = await _player.setUrl(mediaItem.id);
      if (duration != null) {
        this.mediaItem.add(mediaItem.copyWith(duration: duration));
      }
      _playFromCurrentSource();
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
    if (_player.processingState == ja.ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    if (_player.audioSource == null) {
      final item = mediaItem.valueOrNull;
      if (item == null) {
        return;
      }
      final duration = await _player.setUrl(item.id);
      if (duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    }
    _playFromCurrentSource();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _broadcastState(_player.playbackEvent);
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player.stop();
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
        controls: const <MediaControl>[],
        systemActions: const <MediaAction>{},
      ),
    );
  }

  Future<void> disposeHandler() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
  }

  void _updateDuration(Duration? duration) {
    final item = mediaItem.valueOrNull;
    if (item != null && duration != null && item.duration != duration) {
      mediaItem.add(item.copyWith(duration: duration));
    }
  }

  void _broadcastState(ja.PlaybackEvent event) {
    final processingState = _mapProcessingState(_player.processingState);
    final isPlaying =
        _player.playing && processingState != AudioProcessingState.completed;
    playbackState.add(
      playbackState.value.copyWith(
        controls: _controls(playing: isPlaying),
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1],
        processingState: processingState,
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
  }

  void _playFromCurrentSource() {
    playbackState.add(
      playbackState.value.copyWith(
        controls: _controls(playing: true),
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1],
        processingState:
            _mapProcessingState(_player.processingState) ==
                AudioProcessingState.idle
            ? AudioProcessingState.loading
            : _mapProcessingState(_player.processingState),
        playing: true,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
      ),
    );
    unawaited(
      _player.play().catchError((Object error, StackTrace stackTrace) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            playing: false,
            errorMessage: error.toString(),
            controls: _controls(playing: false),
          ),
        );
      }),
    );
  }

  List<MediaControl> _controls({required bool playing}) => <MediaControl>[
    if (playing) MediaControl.pause else MediaControl.play,
    MediaControl.stop,
  ];

  AudioProcessingState _mapProcessingState(ja.ProcessingState state) {
    return switch (state) {
      ja.ProcessingState.idle => AudioProcessingState.idle,
      ja.ProcessingState.loading => AudioProcessingState.loading,
      ja.ProcessingState.buffering => AudioProcessingState.buffering,
      ja.ProcessingState.ready => AudioProcessingState.ready,
      ja.ProcessingState.completed => AudioProcessingState.completed,
    };
  }
}
