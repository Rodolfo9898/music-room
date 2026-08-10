import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/music_player_controller.dart';
import '../now_playing.dart';
import '../queue_view.dart';
import 'animated_equalizer.dart';

class BottomPlayer extends StatelessWidget {
  const BottomPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<MusicPlayerController>();
    final track = player.currentTrack;

    if (track == null) {
      if (!player.hasActiveRoom) return const SizedBox.shrink();

      return GestureDetector(
        onTap: () => context.push(NowPlayingScreen.routeName),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF11141D),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nothing in the queue',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFF4F7FB),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (player.activeRoomName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Room: ${player.activeRoomName}',
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => context.push(NowPlayingScreen.routeName),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF11141D),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            _MiniArtwork(isPlaying: player.isPlaying),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF4F7FB),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    player.activeRoomName != null
                        ? 'Room: ${player.activeRoomName}'
                        : player.isPlaying
                        ? 'Playing from the current playlist'
                        : 'Paused from the current playlist',
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (player.queue.isNotEmpty)
              IconButton(
                onPressed: () => context.push(QueueView.routeName),
                icon: const Icon(Icons.queue_music_rounded),
                color: const Color(0xFF98A2B3),
              ),
            IconButton(
              onPressed: player.togglePlay,
              icon: Icon(
                player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniArtwork extends StatelessWidget {
  final bool isPlaying;

  const _MiniArtwork({required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5F6D), Color(0xFF6C63FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: AnimatedEqualizer(
          isPlaying: isPlaying,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
