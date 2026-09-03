import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../controllers/music_player_controller.dart';
import '../models/music_models.dart';
import '../theme/music_theme.dart';
import '../widgets/music_album_art.dart';

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key, required this.player});

  final MusicPlayerController player;

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  final _lyricsController = ScrollController();
  bool _userSeeking = false;
  double _seekValue = 0;
  int _activeLyricIndex = -1;
  String _lyricsSignature = '';

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_syncLyrics);
    _syncLyrics();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.player.bindLocalizations(AppLocalizations.of(context)!);
  }

  @override
  void dispose() {
    widget.player.removeListener(_syncLyrics);
    _lyricsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildMusicTheme(Theme.of(context)),
      child: Scaffold(
        body: AnimatedBuilder(
          animation: widget.player,
          builder: (context, _) {
            return _buildShell(widget.player, widget.player.currentTrack);
          },
        ),
      ),
    );
  }

  Widget _buildShell(MusicPlayerController player, Track? track) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE5F3ED), MusicColors.paper, MusicColors.paper],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(player),
                  const SizedBox(height: 14),
                  Expanded(child: _buildBody(player, track)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(MusicPlayerController player, Track? track) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 820) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 372,
                child: SingleChildScrollView(
                  child: _buildPlayerPanel(player, track),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: _buildLyricsPanel(player, fillHeight: true)),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildPlayerPanel(player, track),
              const SizedBox(height: 14),
              _buildLyricsPanel(player),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(MusicPlayerController player) {
    final l10n = AppLocalizations.of(context)!;
    final stateLabel = player.downloading
        ? l10n.musicDownloading
        : player.preparing
        ? l10n.musicLoading
        : player.playing
        ? l10n.musicPlaying
        : l10n.musicPaused;
    return _Panel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          IconButton.outlined(
            tooltip: l10n.musicBack,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.musicNowPlaying,
                  style: const TextStyle(
                    color: MusicColors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.musicPlayerSubtitle,
                  style: const TextStyle(
                    color: MusicColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _MetaChip(
            icon: player.downloading
                ? Icons.download
                : player.preparing
                ? Icons.hourglass_top
                : player.playing
                ? Icons.equalizer
                : Icons.pause_circle_outline,
            label: stateLabel,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerPanel(MusicPlayerController player, Track? track) {
    final l10n = AppLocalizations.of(context)!;
    final durationMs = player.duration.inMilliseconds <= 0
        ? 1000
        : player.duration.inMilliseconds;
    final positionMs = _userSeeking
        ? _seekValue.round()
        : player.position.inMilliseconds.clamp(0, durationMs);
    return _Panel(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [MusicColors.surface, MusicColors.accentWash],
      ),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final artSize = constraints.maxWidth < 420 ? 220.0 : 260.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: MusicAlbumArt(
                  url: player.albumUrl,
                  bytes: player.albumBytes,
                  size: artSize,
                  iconSize: artSize * 0.38,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                track == null
                    ? l10n.musicNoTrackPlaying
                    : track.name.isEmpty
                    ? l10n.musicUnknownTrack
                    : track.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MusicColors.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                track?.artistText(l10n) ?? l10n.musicChooseTrackFromHome,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MusicColors.muted, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (track != null) _MetaChip(label: track.sourceLabel(l10n)),
                  if ((track?.album ?? '').isNotEmpty)
                    _MetaChip(icon: Icons.album_outlined, label: track!.album),
                ],
              ),
              const SizedBox(height: 18),
              _buildProgressPanel(player, positionMs, durationMs),
              const SizedBox(height: 16),
              _buildControls(player, track),
              if (player.status.isNotEmpty) ...[
                const SizedBox(height: 14),
                _StatusMessage(text: player.status),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildProgressPanel(
    MusicPlayerController player,
    int positionMs,
    int durationMs,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: MusicColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MusicColors.line),
      ),
      child: Column(
        children: [
          Slider(
            value: positionMs.toDouble(),
            max: durationMs.toDouble(),
            onChanged: player.playable
                ? (value) {
                    setState(() {
                      _userSeeking = true;
                      _seekValue = value;
                    });
                  }
                : null,
            onChangeEnd: player.playable
                ? (value) {
                    setState(() => _userSeeking = false);
                    widget.player.seekTo(
                      Duration(milliseconds: value.round()),
                      l10n,
                    );
                  }
                : null,
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatTime(Duration(milliseconds: positionMs)),
                  style: const _TimeTextStyle(),
                ),
              ),
              Text(_formatTime(player.duration), style: const _TimeTextStyle()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControls(MusicPlayerController player, Track? track) {
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: IconButton.filled(
            tooltip: player.playing ? l10n.musicPause : l10n.musicPlay,
            onPressed: player.playable
                ? () => player.togglePlayback(l10n)
                : null,
            iconSize: 34,
            icon: Icon(
              player.preparing
                  ? Icons.hourglass_top
                  : player.playing
                  ? Icons.pause
                  : Icons.play_arrow,
            ),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: track == null || player.downloading ? null : _download,
          icon: Icon(player.downloading ? Icons.hourglass_top : Icons.download),
          label: Text(
            player.downloading
                ? l10n.musicDownloading
                : l10n.musicDownloadCurrent,
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsPanel(
    MusicPlayerController player, {
    bool fillHeight = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final lyrics = player.lyrics;
    return _Panel(
      height: fillHeight ? null : 480,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _LyricsIcon(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.musicLyrics,
                      style: const TextStyle(
                        color: MusicColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      l10n.musicLyricsFollowProgress,
                      style: const TextStyle(
                        color: MusicColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _MetaChip(label: '${lyrics.length} ${l10n.musicLineUnit}'),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: lyrics.isEmpty
                ? _EmptyLyrics(message: l10n.musicNoLyrics)
                : Container(
                    decoration: BoxDecoration(
                      color: MusicColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: MusicColors.line),
                    ),
                    child: ListView.builder(
                      controller: _lyricsController,
                      padding: const EdgeInsets.symmetric(vertical: 120),
                      itemCount: lyrics.length,
                      itemBuilder: (context, index) {
                        final active = index == _activeLyricIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: active ? 12 : 9,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? MusicColors.accentSoft
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              color: active
                                  ? MusicColors.accentDark
                                  : MusicColors.muted,
                              fontSize: active ? 19 : 15,
                              fontWeight: active
                                  ? FontWeight.w900
                                  : FontWeight.w500,
                              height: 1.38,
                            ),
                            child: Text(
                              lyrics[index].text,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _syncLyrics() {
    final track = widget.player.currentTrack;
    final lyrics = widget.player.lyrics;
    final signature = '${track?.id ?? ''}:${lyrics.length}';
    if (signature != _lyricsSignature) {
      _lyricsSignature = signature;
      _activeLyricIndex = -1;
    }
    final nextIndex = _findActiveLyric(lyrics, widget.player.position);
    if (nextIndex == _activeLyricIndex) {
      return;
    }
    _activeLyricIndex = nextIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_lyricsController.hasClients || nextIndex < 0) {
        return;
      }
      const estimatedLineHeight = 54.0;
      final viewport = _lyricsController.position.viewportDimension;
      final target = (nextIndex * estimatedLineHeight) - viewport / 2;
      _lyricsController.animateTo(
        target.clamp(0.0, _lyricsController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  int _findActiveLyric(List<LyricLine> lyrics, Duration position) {
    if (lyrics.isEmpty) {
      return -1;
    }
    var index = 0;
    for (var i = 0; i < lyrics.length; i++) {
      if (lyrics[i].time <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  Future<void> _download() async {
    await widget.player.downloadCurrent(AppLocalizations.of(context)!);
    if (!mounted || widget.player.status.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.player.status)));
  }

  String _formatTime(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 24 * 60 * 60);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remainder.toString().padLeft(2, '0')}';
  }
}

class _TimeTextStyle extends TextStyle {
  const _TimeTextStyle()
    : super(
        color: MusicColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    required this.padding,
    this.gradient,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? MusicColors.surfaceRaised : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MusicColors.line),
        boxShadow: const [
          BoxShadow(
            color: MusicColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _LyricsIcon extends StatelessWidget {
  const _LyricsIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: MusicColors.accentSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.lyrics_outlined, color: MusicColors.accentDark),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: MusicColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MusicColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: MusicColors.accent, size: 15),
            const SizedBox(width: 5),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MusicColors.accentDark,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MusicColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MusicColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: MusicColors.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: MusicColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLyrics extends StatelessWidget {
  const _EmptyLyrics({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MusicColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MusicColors.line),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note, color: MusicColors.accent, size: 34),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(color: MusicColors.muted, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
