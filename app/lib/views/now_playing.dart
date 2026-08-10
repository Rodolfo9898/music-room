import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/music_player_controller.dart';
import 'queue_view.dart';
import 'utils/animated_equalizer.dart';

class NowPlayingScreen extends StatelessWidget {
  static const routeName = '/now-playing';

  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<MusicPlayerController>();
    final track = player.currentTrack;

    if (track == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Now playing'),
          actions: _roomActions(context, player),
        ),
        body: const Center(
          child: Text(
            'Nothing playing',
            style: TextStyle(color: Color(0xFF98A2B3), fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now playing'),
        actions: _roomActions(context, player),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFF5F6D),
                                Color(0xFFFFD166),
                                Color(0xFF6C63FF),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFFF7A45,
                                ).withValues(alpha: 0.18),
                                blurRadius: 34,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(100),
                          child: AnimatedEqualizer(
                            isPlaying: player.isPlaying,
                            color: Colors.white,
                            size: 85,
                            barCount: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      track.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF4F7FB),
                        fontSize: 30,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      player.activeRoomName != null
                          ? 'Socket room: ${player.activeRoomName}'
                          : 'Artist #${track.artistId} • Genre #${track.genreId}',
                      style: const TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _ExpandedPlayerControls(player: player),
            ],
          ),
        ),
      ),
    );
  }
}

List<Widget>? _roomActions(BuildContext context, MusicPlayerController player) {
  if (!player.hasActiveRoom) return null;
  return [
    if (player.isRoomHost)
      IconButton(
        tooltip: 'Transfer host',
        icon: const Icon(Icons.swap_horiz_rounded),
        onPressed: () => _showTransferHostSheet(context, player),
      ),
    if (player.isRoomHost)
      IconButton(
        tooltip: 'Delete room',
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: () => _confirmDeleteRoom(context, player),
      ),
    IconButton(
      tooltip: 'Leave room',
      icon: const Icon(Icons.logout_rounded),
      onPressed: () async {
        final messenger = ScaffoldMessenger.of(context);
        final success = await player.leaveRoom();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'You left the room.'
                  : 'Left the room, but the server could not be notified.',
            ),
          ),
        );
        if (success && context.mounted) {
          context.pop();
        }
      },
    ),
  ];
}

Future<void> _confirmDeleteRoom(
  BuildContext context,
  MusicPlayerController player,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete room?'),
      content: const Text(
        'This closes the room for every listener. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final success = await player.deleteRoom();
  messenger.showSnackBar(
    SnackBar(
      content: Text(success ? 'Room deleted.' : 'Could not delete the room.'),
    ),
  );
}

Future<void> _showTransferHostSheet(
  BuildContext context,
  MusicPlayerController player,
) async {
  final candidates = player.otherRoomMemberIds;
  final targetId = await showModalBottomSheet<int>(
    context: context,
    builder: (sheetContext) {
      if (candidates.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(24),
          child: Text('No other members in this room.'),
        );
      }
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: candidates
              .map(
                (id) => ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text('Member #$id'),
                  onTap: () => Navigator.of(sheetContext).pop(id),
                ),
              )
              .toList(),
        ),
      );
    },
  );

  if (targetId == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final success = await player.transferHost(targetId);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        success ? 'Host transferred.' : 'Could not transfer host.',
      ),
    ),
  );
}

class _ExpandedPlayerControls extends StatelessWidget {
  final MusicPlayerController player;

  const _ExpandedPlayerControls({required this.player});

  @override
  Widget build(BuildContext context) {
    final maxSeconds = player.displayDuration.inSeconds <= 0
        ? 1.0
        : player.displayDuration.inSeconds.toDouble();
    final currentSeconds = player.position.inSeconds
        .clamp(0, maxSeconds.toInt())
        .toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: currentSeconds,
            min: 0,
            max: maxSeconds,
            activeColor: const Color(0xFFFF7A45),
            inactiveColor: Colors.white.withValues(alpha: 0.14),
            onChanged: player.seek,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(player.position),
              style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
            ),
            Text(
              _formatDuration(player.displayDuration),
              style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: player.canSkipPrevious ? player.skipPrevious : null,
              iconSize: 38,
              color: Colors.white,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            const SizedBox(width: 18),
            IconButton.filled(
              onPressed: player.togglePlay,
              iconSize: 42,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFFF7A45),
                foregroundColor: Colors.white,
                fixedSize: const Size(72, 72),
              ),
              icon: Icon(
                player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
            const SizedBox(width: 18),
            IconButton(
              onPressed: player.canSkipNext ? player.skipNext : null,
              iconSize: 38,
              color: Colors.white,
              icon: const Icon(Icons.skip_next_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        IconButton(
          tooltip: player.isMuted ? 'Unmute' : 'Mute',
          onPressed: player.toggleMute,
          iconSize: 26,
          color: player.isMuted
              ? const Color(0xFFFF7A45)
              : const Color(0xFF98A2B3),
          icon: Icon(
            player.isMuted
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
          ),
        ),
        const SizedBox(height: 14),
        if (player.queue.isNotEmpty)
          TextButton.icon(
            onPressed: () => context.push(QueueView.routeName),
            icon: const Icon(Icons.queue_music_rounded, size: 20),
            label: const Text('View Queue'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF98A2B3),
            ),
          ),
        if (player.statusMessage != null) ...[
          const SizedBox(height: 14),
          Text(
            player.statusMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF98A2B3),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString();
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours > 0) {
    return '$hours:${minutes.padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}
