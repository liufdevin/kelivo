import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../controllers/music_player_controller.dart';
import '../pages/music_player_page.dart';
import '../theme/music_theme.dart';
import 'music_album_art.dart';

class MusicMiniPlayer extends StatelessWidget {
  const MusicMiniPlayer({super.key, required this.player});

  final MusicPlayerController player;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final track = player.currentTrack;
    if (track == null) {
      return const SizedBox.shrink();
    }
    final durationMs = player.duration.inMilliseconds;
    final progress = durationMs <= 0
        ? null
        : (player.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MusicPlayerPage(player: player),
            ),
          );
        },
        child: Container(
          height: 84,
          decoration: BoxDecoration(
            color: MusicColors.surface,
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
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                color: MusicColors.accent,
                backgroundColor: MusicColors.surfaceSoft,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
                  child: Row(
                    children: [
                      MusicAlbumArt(
                        url: player.albumUrl,
                        bytes: player.albumBytes,
                        size: 52,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.name.isEmpty
                                  ? l10n.musicUnknownTrack
                                  : track.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MusicColors.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${track.artistText(l10n)} · '
                              '${track.sourceLabel(l10n)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MusicColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: player.playing
                            ? l10n.musicPause
                            : l10n.musicPlay,
                        onPressed: player.playable
                            ? () => player.togglePlayback(l10n)
                            : null,
                        icon: Icon(
                          player.preparing
                              ? Icons.hourglass_top
                              : player.playing
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
