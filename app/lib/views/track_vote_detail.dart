part of 'track_vote.dart';

class VoteEventScreen extends StatefulWidget {
  static const routeName = '/track-vote/event';
  final VoteEvent initialEvent;
  const VoteEventScreen({super.key, required this.initialEvent});

  @override
  State<VoteEventScreen> createState() => _VoteEventScreenState();
}

class _VoteEventScreenState extends State<VoteEventScreen> {
  VoteEvent? _event;
  int? _accountId;
  double? _subscriptionLatitude;
  double? _subscriptionLongitude;

  @override
  void initState() {
    super.initState();
    _event = widget.initialEvent;
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(
          () => _accountId = prefs.getInt(SharedPreferencesKeys.accountId),
        );
      }
    });
    if (_event?.votePolicy == 'LOCATION_TIME') {
      requestCurrentLocation().then((location) {
        if (!mounted || !location.isGranted) return;
        setState(() {
          _subscriptionLatitude = location.position?.latitude;
          _subscriptionLongitude = location.position?.longitude;
        });
      });
    }
  }

  Future<Map<String, double?>?> _locationVariables() async {
    if (_event?.votePolicy != 'LOCATION_TIME') {
      return {'latitude': null, 'longitude': null};
    }
    final location = await requestCurrentLocation();
    if (!location.isGranted) {
      if (mounted) _message(locationAccessMessage(location.status));
      return null;
    }
    return {
      'latitude': location.position?.latitude,
      'longitude': location.position?.longitude,
    };
  }

  Future<void> _vote(int musicId) async {
    final location = await _locationVariables();
    if (location == null) return;
    final result = await GraphQLConnection().client!.value.mutate(
      MutationOptions(
        document: gql(_fields(_voteMutation)),
        variables: {'eventId': _event!.id, 'musicId': musicId, ...location},
      ),
    );
    if (mounted && result.hasException) _message(result.exception.toString());
  }

  Future<void> _suggest() async {
    final queryController = TextEditingController();
    List<MusicTrack> results = [];
    final selected = await showDialog<MusicTrack>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Suggest a track'),
          content: SizedBox(
            width: 420,
            height: 360,
            child: Column(
              children: [
                TextField(
                  key: const Key('track_vote_suggest_search_field'),
                  controller: queryController,
                  decoration: const InputDecoration(
                    labelText: 'Search catalog',
                  ),
                  onChanged: (value) async {
                    final response = await MusicService.searchTracks(value);
                    setDialogState(() => results = response.tracks);
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (_, index) {
                      final track = results[index];
                      return ListTile(
                        key: ValueKey('track_vote_suggest_result_${track.id}'),
                        title: Text(track.title),
                        subtitle: Text(track.artistName ?? 'Unknown artist'),
                        onTap: () => Navigator.pop(dialogContext, track),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final location = await _locationVariables();
    if (location == null) return;
    final result = await GraphQLConnection().client!.value.mutate(
      MutationOptions(
        document: gql(_fields(_suggestMutation)),
        variables: {'eventId': _event!.id, 'musicId': selected.id, ...location},
      ),
    );
    if (mounted && result.hasException) _message(result.exception.toString());
  }

  Future<void> _playRanking(VoteEvent event) async {
    final played = await context.read<MusicPlayerController>().playVoteRanking(
      event.id,
      event.tracks.map((track) => track.musicId).toList(),
    );
    if (!mounted) return;
    _message(
      played
          ? 'The live room queue now follows the vote ranking.'
          : 'Could not start the vote ranking.',
    );
  }

  Future<void> _unlinkFromLiveRoom() async {
    final unlinked = await context
        .read<MusicPlayerController>()
        .unlinkVoteEvent();
    if (!mounted) return;
    _message(
      unlinked
          ? 'Unlinked this event from the live room queue.'
          : 'Could not unlink from the live room.',
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this event?'),
        content: const Text(
          'This removes it and all its suggestions/votes for everyone. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('track_vote_delete_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    final result = await GraphQLConnection().client!.value.mutate(
      MutationOptions(
        document: gql(_deleteEventMutation),
        variables: {'eventId': _event!.id},
      ),
    );
    if (!mounted) return;
    final success =
        !result.hasException && result.data?['deleteVoteEvent'] == true;
    if (!success) {
      _message('Could not delete this event.');
      return;
    }
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final client = GraphQLConnection().client!;
    final player = context.watch<MusicPlayerController>();
    return GraphQLProvider(
      client: client,
      child: Subscription(
        options: SubscriptionOptions(
          document: gql(_fields(_eventSubscription)),
          variables: {
            'eventId': _event!.id,
            'latitude': _subscriptionLatitude,
            'longitude': _subscriptionLongitude,
          },
        ),
        builder: (result) {
          final raw = result.data?['voteEventUpdated'];
          if (raw is Map<String, dynamic>) _event = VoteEvent.fromJson(raw);
          return MusicRoomScaffold(
            appBar: AppBar(
              title: Text(_event!.name),
              actions: [
                IconButton(
                  key: const Key('track_vote_members_button'),
                  tooltip: _event!.membersManageable ? 'Members' : 'Voters',
                  onPressed: () => context.push(
                    VoteEventMembersScreen.routeName,
                    extra: _event!,
                  ),
                  icon: const Icon(Icons.people_outline),
                ),
                if (_event!.ownerId == _accountId)
                  IconButton(
                    key: const Key('track_vote_delete_button'),
                    tooltip: 'Delete event',
                    onPressed: _confirmDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            floatingActionButton: _event!.canVote
                ? FloatingActionButton.extended(
                    key: const Key('track_vote_suggest_button'),
                    onPressed: _suggest,
                    icon: const Icon(Icons.add),
                    label: const Text('Suggest'),
                  )
                : null,
            body: _event == null
                ? Text('An error occured')
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _event!.isPublic
                                    ? 'Public event'
                                    : 'Private event',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(_event!.policyLabel),
                              if (!_event!.canVote)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _event!.canVoteReasonMessage,
                                    style: const TextStyle(
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Live ranking',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (_event!.ownerId == _accountId &&
                          _event!.tracks.isNotEmpty &&
                          !(player.linkedVoteEventId == _event!.id)) ...[
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          key: const Key('track_vote_play_ranking_button'),
                          onPressed: () => _playRanking(_event!),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play ranking in live room'),
                        ),
                      ],
                      if (_event!.ownerId == _accountId &&
                          player.linkedVoteEventId == _event!.id) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const Key('track_vote_unlink_button'),
                          onPressed: _unlinkFromLiveRoom,
                          icon: const Icon(Icons.link_off),
                          label: const Text('Unlink from live room'),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (_event!.tracks.isEmpty)
                        const Text('No suggestions yet.'),
                      ..._event!.tracks.asMap().entries.map((entry) {
                        final selected = _event!.userVoteMusicIds.contains(
                          entry.value.musicId,
                        );
                        return Card(
                          key: ValueKey(
                            'track_vote_track_${entry.value.musicId}',
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text('${entry.key + 1}'),
                            ),
                            title: Text(entry.value.title),
                            subtitle: Text(
                              '${entry.value.artist} · ${entry.value.votes} votes',
                            ),
                            trailing: IconButton.filledTonal(
                              key: ValueKey(
                                'track_vote_vote_button_${entry.value.musicId}',
                              ),
                              onPressed: _event!.canVote
                                  ? () => _vote(entry.value.musicId)
                                  : null,
                              icon: Icon(
                                selected ? Icons.check : Icons.how_to_vote,
                                color: selected ? Colors.green : null,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
          );
        },
      ),
    );
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));
}

class VoteEventMembersScreen extends StatefulWidget {
  static const routeName = '/track-vote/event/members';
  final VoteEvent initialEvent;
  const VoteEventMembersScreen({super.key, required this.initialEvent});

  @override
  State<VoteEventMembersScreen> createState() => _VoteEventMembersScreenState();
}

class _VoteEventMembersScreenState extends State<VoteEventMembersScreen> {
  VoteEvent? _event;
  int? _accountId;
  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _event = widget.initialEvent;
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(
          () => _accountId = prefs.getInt(SharedPreferencesKeys.accountId),
        );
      }
    });
  }

  bool get _canManage =>
      _accountId != null &&
      _event!.ownerId == _accountId &&
      _event!.membersManageable;

  Future<void> _invite() async {
    final controller = TextEditingController();
    final dialogFormKey = GlobalKey<FormState>();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite voter'),
        content: Form(
          key: dialogFormKey,
          child: TextFormField(
            key: const Key('track_vote_invite_email_field'),
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Account email'),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: _validateEmail,
            onFieldSubmitted: (_) {
              final isValid = dialogFormKey.currentState?.validate() ?? false;
              if (!isValid) return;
              Navigator.pop(ctx, controller.text.trim());
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('track_vote_invite_submit_button'),
            onPressed: () {
              final isValid = dialogFormKey.currentState?.validate() ?? false;
              if (!isValid) return;
              Navigator.pop(ctx, controller.text.trim());
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    final result = await GraphQLConnection().client!.value.mutate(
      MutationOptions(
        document: gql(_fields(_inviteMutation)),
        variables: {'eventId': _event!.id, 'email': email},
      ),
    );
    if (mounted) {
      _message(
        result.hasException
            ? _inviteErrorMessage(result.exception)
            : 'Invitation added.',
      );
    }
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  String _inviteErrorMessage(OperationException? exception) {
    final message = exception?.graphqlErrors.firstOrNull?.message.trim();
    if (message == null || message.isEmpty) return 'Could not add invitation.';
    if (message.toLowerCase() == 'user not found') {
      return 'No account found for this email.';
    }
    return message;
  }

  Future<void> _removeMember(VoteMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member'),
        content: Text(
          'Remove ${member.displayName} from this event? Their vote will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('track_vote_members_remove_confirm_button'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await GraphQLConnection().client!.value.mutate(
      MutationOptions(
        document: gql(_fields(_removeMemberMutation)),
        variables: {'eventId': _event!.id, 'userId': member.id},
      ),
    );
    if (mounted) {
      _message(
        result.hasException
            ? 'Could not remove member.'
            : '${member.displayName} removed.',
      );
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    final client = GraphQLConnection().client!;
    return Scaffold(
      appBar: AppBar(
        title: Text(_event!.membersManageable ? 'Members' : 'Voters'),
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              key: const Key('track_vote_members_add_button'),
              onPressed: _invite,
              icon: const Icon(Icons.person_add),
              label: const Text('Add member'),
            )
          : null,
      body: GraphQLProvider(
        client: client,
        child: Subscription(
          options: SubscriptionOptions(
            document: gql(_fields(_eventSubscription)),
            variables: {'eventId': _event!.id},
          ),
          builder: (result) {
            final raw = result.data?['voteEventUpdated'];
            if (raw is Map<String, dynamic>) _event = VoteEvent.fromJson(raw);
            final event = _event!;
            if (event.members.isEmpty) {
              return Center(
                child: Text(
                  event.membersManageable
                      ? 'No invited members yet.'
                      : 'No one has voted yet.',
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: event.members.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final member = event.members[index];
                return ListTile(
                  key: ValueKey('track_vote_member_${member.id}'),
                  tileColor: const Color(0xFF11141D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(member.displayName),
                  subtitle: Text(member.email),
                  trailing: _canManage
                      ? IconButton(
                          key: ValueKey(
                            'track_vote_member_remove_${member.id}',
                          ),
                          tooltip: 'Remove member',
                          icon: const Icon(Icons.person_remove),
                          onPressed: () => _removeMember(member),
                        )
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
