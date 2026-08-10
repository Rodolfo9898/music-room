import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:provider/provider.dart';

import '../network/web_socket.dart';
import '../objects/music_track.dart';
import '../objects/vote_event.dart';
import '../state/music_player_controller.dart';
import 'track_vote.dart';
import 'utils/animated_equalizer.dart';

const String _linkedVoteEventQuery = r'''
  query QueueLinkedVoteEvent($id: Int!) {
    voteEvent(id: $id) {
      id name owner_id is_public vote_policy version can_vote user_vote_music_ids
      tracks { music_id title artist_name duration vote_count suggested_by }
      members { id email display_name }
    }
  }
''';

class QueueView extends StatelessWidget {
  static const routeName = '/queue';

  const QueueView({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<MusicPlayerController>();
    final queue = player.queue;
    final currentIndex = player.queueIndex;
    final linkedVoteEventId = player.linkedVoteEventId;

    return Scaffold(
      backgroundColor: const Color(0xFF090B11),
      appBar: AppBar(title: const Text('Queue')),
      body: Column(
        children: [
          if (linkedVoteEventId != null)
            _LinkedVoteEventBanner(eventId: linkedVoteEventId),
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child: Text(
                      'Queue is empty',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 16,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      final isActive = index == currentIndex;
                      return _QueueTrackTile(
                        track: track,
                        isActive: isActive,
                        isPlaying: isActive && player.isPlaying,
                        onTap: () => player.playQueueTrack(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Shows the Track Vote event the active room's queue is currently following
/// (if any) and links to its detail page.
class _LinkedVoteEventBanner extends StatelessWidget {
  final int eventId;

  const _LinkedVoteEventBanner({required this.eventId});

  @override
  Widget build(BuildContext context) {
    final client = GraphQLConnection().client;
    if (client == null) return const SizedBox.shrink();
    return GraphQLProvider(
      client: client,
      child: Query(
        key: ValueKey('queue_linked_vote_event_$eventId'),
        options: QueryOptions(
          document: gql(_linkedVoteEventQuery),
          variables: {'id': eventId},
          fetchPolicy: FetchPolicy.networkOnly,
        ),
        builder: (result, {fetchMore, refetch}) {
          final raw = result.data?['voteEvent'];
          if (raw is! Map<String, dynamic>) return const SizedBox.shrink();
          final event = VoteEvent.fromJson(raw);
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Material(
              color: const Color(0xFF11141D),
              borderRadius: BorderRadius.circular(14),
              child: ListTile(
                key: const Key('queue_linked_vote_event_tile'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(
                  Icons.how_to_vote,
                  color: Color(0xFFFF7A45),
                ),
                title: Text(
                  'Following live votes',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                subtitle: Text(
                  event.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.white70,
                ),
                onTap: () =>
                    context.push(VoteEventScreen.routeName, extra: event),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QueueTrackTile extends StatelessWidget {
  final MusicTrack track;
  final bool isActive;
  final bool isPlaying;
  final VoidCallback onTap;

  const _QueueTrackTile({
    required this.track,
    required this.isActive,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFFF7A45).withValues(alpha: 0.12)
                : const Color(0xFF11141D),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFFF7A45).withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              if (isActive)
                AnimatedEqualizer(
                  isPlaying: isPlaying,
                  color: const Color(0xFFFF7A45),
                  size: 24,
                )
              else
                Icon(
                  Icons.music_note_rounded,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 24,
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive
                            ? const Color(0xFFFF7A45)
                            : const Color(0xFFF4F7FB),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (track.artistName != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        track.artistName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _formatDuration(Duration(seconds: track.duration)),
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
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
