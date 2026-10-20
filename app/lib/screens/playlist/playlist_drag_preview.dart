import 'package:flutter/material.dart';
import '../../domain/radio_library.dart';
import '../../theme/app_theme.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import 'track_card.dart';

class PlaylistDragPreview extends StatelessWidget {
  const PlaylistDragPreview({super.key, required this.tracks});
  final List<PoolTrack> tracks;
  @override
  Widget build(BuildContext context) {
    final rm = context.rm;
    final available = MediaQuery.sizeOf(context).height * .65;
    final visible = tracks
        .take(((available - 42) / 54).floor().clamp(1, 8))
        .toList();
    return Material(
      color: rm.panel,
      elevation: 8,
      borderRadius: BorderRadius.circular(RmTokens.rSm),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tracks.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  '移动 ${tracks.length} 首歌曲',
                  style: RmText.sans(
                    12,
                    weight: FontWeight.w600,
                    color: rm.accent.base,
                  ),
                ),
              ),
            for (final track in visible)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: TrackCard.fromPoolTrack(track, dragging: true),
              ),
            if (visible.length < tracks.length)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                child: Text(
                  '另 ${tracks.length - visible.length} 首一起移动',
                  style: RmText.sans(11, color: rm.fg3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
