part of 'track_vote.dart';

class TrackVoteScreen extends StatefulWidget {
  static const routeName = '/track-vote';
  const TrackVoteScreen({super.key});

  @override
  State<TrackVoteScreen> createState() => _TrackVoteScreenState();
}

class _TrackVoteScreenState extends State<TrackVoteScreen> {
  int _refreshKey = 0;

  Future<void> _create() async {
    final event = await context.push<VoteEvent>(
      CreateVoteEventScreen.routeName,
    );
    if (!mounted || event == null) return;
    await _openEvent(event);
  }

  Future<void> _openEvent(VoteEvent event) async {
    await context.push<bool>(VoteEventScreen.routeName, extra: event);
    if (mounted) setState(() => _refreshKey++);
  }

  @override
  Widget build(BuildContext context) {
    final client = GraphQLConnection().client;
    return MusicRoomScaffold(
      appBar: AppBar(title: const Text('Track Vote')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('track_vote_new_event_button'),
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: client == null
          ? const Center(child: Text('Realtime connection unavailable'))
          : GraphQLProvider(
              client: client,
              child: Query(
                key: ValueKey(_refreshKey),
                options: QueryOptions(
                  document: gql(_eventsQuery),
                  fetchPolicy: FetchPolicy.noCache,
                ),
                builder: (result, {fetchMore, refetch}) {
                  if (result.isLoading && result.data == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (result.hasException) {
                    return Center(child: Text(result.exception.toString()));
                  }
                  final raw = result.data?['voteEvents'];
                  final events = raw is List
                      ? raw
                            .whereType<Map<String, dynamic>>()
                            .map(VoteEvent.fromJson)
                            .toList()
                      : <VoteEvent>[];
                  if (events.isEmpty) {
                    return const Center(
                      child: Text('No accessible voting events yet.'),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => refetch?.call(),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: events.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final event = events[index];
                        return ListTile(
                          tileColor: const Color(0xFF11141D),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          leading: CircleAvatar(
                            child: Icon(
                              event.isPublic ? Icons.public : Icons.lock,
                            ),
                          ),
                          title: Text(event.name),
                          subtitle: Text(
                            '${event.tracks.length} suggestions · ${event.policyLabel}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openEvent(event),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
    );
  }
}
