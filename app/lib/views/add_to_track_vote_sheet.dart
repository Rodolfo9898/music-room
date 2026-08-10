import 'package:flutter/material.dart';

import '../objects/vote_event.dart';
import 'track_vote.dart';

Future<void> showAddToTrackVoteSheet(BuildContext context, int musicId) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF11141D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (ctx) => _AddToTrackVoteSheet(musicId: musicId),
  );
}

class _AddToTrackVoteSheet extends StatefulWidget {
  final int musicId;

  const _AddToTrackVoteSheet({required this.musicId});

  @override
  State<_AddToTrackVoteSheet> createState() => _AddToTrackVoteSheetState();
}

class _AddToTrackVoteSheetState extends State<_AddToTrackVoteSheet> {
  bool _isLoading = true;
  List<VoteEvent> _events = [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    var events = await VoteEventService.fetchVoteEvents();
    if (!mounted) return;

    final needsLocation = events.any(
      (event) => event.votePolicy == 'LOCATION_TIME',
    );
    if (needsLocation) {
      final location = await requestCurrentLocation();
      if (!mounted) return;
      if (location.isGranted) {
        events = await VoteEventService.fetchVoteEvents(
          latitude: location.position?.latitude,
          longitude: location.position?.longitude,
        );
        if (!mounted) return;
      }
    }

    setState(() {
      _events = events;
      _isLoading = false;
    });
  }

  Future<void> _addToEvent(VoteEvent event) async {
    final result = await VoteEventService.suggestTrack(event, widget.musicId);

    if (!mounted) return;
    Navigator.of(context).pop();

    final message = result.isSuccess
        ? 'Added to "${event.name}"'
        : (result.message ?? 'Failed to add to "${event.name}"');

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Add to track vote',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No voting events yet',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _events.length,
                itemBuilder: (context, index) {
                  final event = _events[index];
                  final alreadySuggested = event.tracks.any(
                    (track) => track.musicId == widget.musicId,
                  );
                  final disabled = !event.canVote || alreadySuggested;
                  return ListTile(
                    key: ValueKey('add_to_track_vote_tile_${event.id}'),
                    leading: Icon(
                      event.isPublic ? Icons.how_to_vote : Icons.lock_outline,
                      color: Colors.white54,
                    ),
                    title: Text(
                      event.name,
                      style: TextStyle(
                        color: disabled
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      alreadySuggested
                          ? 'Already suggested'
                          : !event.canVote
                          ? 'Voting not available'
                          : '${event.tracks.length} suggestion${event.tracks.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: alreadySuggested
                            ? const Color(0xFF2DD4BF).withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    trailing: alreadySuggested
                        ? const Icon(
                            Icons.check_circle,
                            color: Color(0xFF2DD4BF),
                            size: 20,
                          )
                        : null,
                    onTap: disabled ? null : () => _addToEvent(event),
                    contentPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
