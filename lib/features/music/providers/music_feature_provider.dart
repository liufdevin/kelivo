import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../../../l10n/app_localizations.dart';
import '../controllers/music_player_controller.dart';
import '../services/gd_audio_handler.dart';
import '../services/gd_desktop_audio_handler.dart';
import '../services/music_api_client.dart';

class MusicFeatureProvider extends ChangeNotifier {
  MusicFeatureProvider({MusicApiClient? api, AudioHandler? audioHandler})
    : _api = api ?? MusicApiClient() {
    if (audioHandler != null) {
      _audioHandler = audioHandler;
      _player = MusicPlayerController(audioHandler, _api);
    }
  }

  final MusicApiClient _api;
  AudioHandler? _audioHandler;
  MusicPlayerController? _player;
  Future<MusicPlayerController>? _initializing;

  MusicApiClient get api => _api;
  MusicPlayerController? get player => _player;

  Future<MusicPlayerController> initialize(AppLocalizations l10n) {
    final current = _player;
    if (current != null) {
      current.bindLocalizations(l10n);
      return Future<MusicPlayerController>.value(current);
    }
    return _initializing ??= _initialize(l10n);
  }

  Future<MusicPlayerController> _initialize(AppLocalizations l10n) async {
    try {
      final isWindowsOrLinux =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux);
      final AudioHandler handler;
      if (isWindowsOrLinux) {
        handler = GdDesktopAudioHandler();
      } else {
        handler = await AudioService.init(
          builder: GdAudioHandler.new,
          config: AudioServiceConfig(
            androidNotificationChannelId: 'com.psyche.kelivo.music',
            androidNotificationChannelName: l10n.musicNotificationChannelName,
            androidStopForegroundOnPause: false,
          ),
        );
      }
      _audioHandler = handler;
      final result = MusicPlayerController(handler, _api)
        ..bindLocalizations(l10n);
      _player = result;
      notifyListeners();
      return result;
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _api.close();
    unawaited(_disposeAudioHandler());
    super.dispose();
  }

  Future<void> _disposeAudioHandler() async {
    final handler = _audioHandler;
    if (handler == null) {
      return;
    }
    try {
      await handler.stop();
    } catch (error, stackTrace) {
      debugPrint('Music audio handler stop failed: $error\n$stackTrace');
    }
    if (handler is GdAudioHandler) {
      await handler.disposeHandler();
    } else if (handler is GdDesktopAudioHandler) {
      await handler.disposeHandler();
    }
  }
}
