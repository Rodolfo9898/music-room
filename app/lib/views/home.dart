import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:pmr_music_room/views/search.dart';
import 'package:provider/provider.dart';

import '../network/web_socket.dart';
import '../state/music_player_controller.dart';
import 'my_playlists.dart';
import 'profile.dart';
import 'utils/scaffold.dart';
import 'track_vote.dart';

const String _roomsSubscription = r'''
  subscription HomeRoomsLive {
    rooms {
      id
      name
      hostId
      memberIds
      playlist { musicId }
      status
    }
  }
''';

const String _createRoomMutation = r'''
  mutation CreateHomeRoom($name: String!) {
    createRoom(name: $name) {
      id
      name
    }
  }
''';

const String _joinRoomMutation = r'''
  mutation JoinHomeRoom($roomId: Int!) {
    joinRoom(roomId: $roomId) {
      id
      name
    }
  }
''';

const String _leaveRoomMutation = r'''
  mutation LeaveHomeRoom($roomId: Int!) {
    leaveRoom(roomId: $roomId)
  }
''';

const String _meQuery = r'''
  query HomeMe { me }
''';

class HomeScreen extends StatefulWidget {
  static const routeName = '/home';

  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isCreatingRoom = false;
  int? _currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MusicPlayerController>().loadTracks();
    });
    _loadCurrentUserId();
  }

  Future<void> _loadCurrentUserId() async {
    final client = GraphQLConnection().client?.value;
    if (client == null) return;
    try {
      final result = await client.query(
        QueryOptions(document: gql(_meQuery), fetchPolicy: FetchPolicy.noCache),
      );
      final userId = result.data?['me'];
      if (mounted && userId is int) {
        setState(() => _currentUserId = userId);
      }
    } catch (_) {}
  }

  Future<void> _createRoom() async {
    final client = GraphQLConnection().client?.value;
    if (client == null) {
      _showMessage('Realtime connection is not ready yet.');
      return;
    }

    setState(() => _isCreatingRoom = true);
    try {
      final now = DateTime.now();
      final result = await client.mutate(
        MutationOptions(
          document: gql(_createRoomMutation),
          variables: {
            'name':
                'Room ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
          },
          fetchPolicy: FetchPolicy.noCache,
        ),
      );

      if (!mounted) return;
      if (result.hasException) {
        _showMessage('Could not create the room.');
        return;
      }

      final rawRoom = result.data?['createRoom'];
      if (rawRoom is Map<String, dynamic>) {
        final roomId = _toInt(rawRoom['id']);
        final roomName = rawRoom['name'] as String? ?? 'Live room';
        context.read<MusicPlayerController>().setActiveRoom(
          roomId: roomId,
          roomName: roomName,
        );
        _showMessage('$roomName created.');
      }
    } finally {
      if (mounted) setState(() => _isCreatingRoom = false);
    }
  }

  Future<void> _joinRoom(_LiveRoom room) async {
    final client = GraphQLConnection().client?.value;
    if (client == null) {
      _showMessage('Realtime connection is not ready yet.');
      return;
    }

    final result = await client.mutate(
      MutationOptions(
        document: gql(_joinRoomMutation),
        variables: {'roomId': room.id},
        fetchPolicy: FetchPolicy.noCache,
      ),
    );

    if (!mounted) return;
    if (result.hasException) {
      _showMessage('Could not join ${room.name}.');
      return;
    }

    context.read<MusicPlayerController>().setActiveRoom(
      roomId: room.id,
      roomName: room.name,
    );
    _showMessage('Joined ${room.name}.');
  }

  Future<void> _leaveRoom(_LiveRoom room) async {
    final player = context.read<MusicPlayerController>();
    bool success;
    if (player.activeRoomId == room.id) {
      success = await player.leaveRoom();
    } else {
      final client = GraphQLConnection().client?.value;
      if (client == null) {
        _showMessage('Realtime connection is not ready yet.');
        return;
      }
      final result = await client.mutate(
        MutationOptions(
          document: gql(_leaveRoomMutation),
          variables: {'roomId': room.id},
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
      success = !result.hasException && result.data?['leaveRoom'] == true;
    }

    if (!mounted) return;
    _showMessage(
      success ? 'Left ${room.name}.' : 'Could not leave ${room.name}.',
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return MusicRoomScaffold(
      backgroundColor: const Color(0xFF090B11),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            _Header(
              onProfileTap: () => context.push(ProfileScreen.routeName),
              onSearchTap: () => context.push(SearchScreen.routeName),
            ),
            const SizedBox(height: 32),
            _PrimaryAction(
              isLoading: _isCreatingRoom,
              onPressed: _isCreatingRoom ? null : _createRoom,
            ),
            const SizedBox(height: 14),
            _PlaylistAction(
              onPressed: () => context.push(MyPlaylistsScreen.routeName),
            ),
            const SizedBox(height: 14),
            _ActionCard(
              key: const Key('home_track_vote_button'),
              icon: Icons.how_to_vote_rounded,
              color: const Color(0xFF6C63FF),
              title: 'Track Vote',
              subtitle: 'Suggest and rank the next track live.',
              onTap: () => context.push(TrackVoteScreen.routeName),
            ),
            const SizedBox(height: 32),
            const Text(
              'Live rooms',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Join a room that is active right now.',
              style: TextStyle(color: Color(0xFF98A2B3)),
            ),
            const SizedBox(height: 16),
            _LiveRoomsSection(
              onJoinRoom: _joinRoom,
              onLeaveRoom: _leaveRoom,
              currentUserId: _currentUserId,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onProfileTap;
  final VoidCallback onSearchTap;

  const _Header({required this.onProfileTap, required this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Music Room',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 3),
              Text(
                'Listen and collaborate',
                style: TextStyle(color: Color(0xFF98A2B3)),
              ),
            ],
          ),
        ),
        IconButton.outlined(
          tooltip: 'Search',
          onPressed: onSearchTap,
          icon: const Icon(Icons.search_rounded),
        ),
        IconButton.filledTonal(
          key: const Key('home_profile_button'),
          tooltip: 'Profile',
          onPressed: onProfileTap,
          icon: const Icon(Icons.person_outline_rounded),
        ),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _PrimaryAction({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return _ActionCard(
      icon: Icons.graphic_eq_rounded,
      color: const Color(0xFFFF7A45),
      title: 'Start a room',
      subtitle: 'Create a live listening session.',
      onTap: onPressed,
      isLoading: isLoading,
    );
  }
}

class _PlaylistAction extends StatelessWidget {
  final VoidCallback onPressed;

  const _PlaylistAction({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return _ActionCard(
      key: const Key('home_playlists_button'),
      icon: Icons.queue_music_rounded,
      color: const Color(0xFF2DD4BF),
      title: 'Playlists',
      subtitle: 'Open and edit collaborative playlists.',
      onTap: onPressed,
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isLoading;

  const _ActionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF11141D),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.chevron_right_rounded,
                      color: onTap == null ? const Color(0xFF6B7280) : null,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveRoomsSection extends StatefulWidget {
  final ValueChanged<_LiveRoom> onJoinRoom;
  final ValueChanged<_LiveRoom> onLeaveRoom;
  final int? currentUserId;

  const _LiveRoomsSection({
    super.key,
    required this.onJoinRoom,
    required this.onLeaveRoom,
    required this.currentUserId,
  });

  @override
  State<_LiveRoomsSection> createState() => _LiveRoomsSectionState();
}

class _LiveRoomsSectionState extends State<_LiveRoomsSection> {
  List<_LiveRoom>? _rooms;

  @override
  Widget build(BuildContext context) {
    final client = GraphQLConnection().client;
    if (client == null) {
      return const _StatusCard(
        icon: Icons.wifi_off_rounded,
        message: 'Realtime connection unavailable.',
      );
    }

    return GraphQLProvider(
      client: client,
      child: Subscription(
        options: SubscriptionOptions(document: gql(_roomsSubscription)),
        builder: (result) {
          // The server pushes a fresh room list on every create/join/leave/
          // close, so this stays in sync even when a room is left from a
          // different screen (e.g. the Now Playing / Queue view) — no
          // manual refresh needed.
          final raw = result.data?['rooms'];
          if (raw is List) _rooms = _parseRooms(raw);

          if (_rooms == null) {
            if (result.hasException) {
              return const _StatusCard(
                icon: Icons.error_outline_rounded,
                message: 'Rooms are unavailable right now.',
              );
            }
            return const Center(child: CircularProgressIndicator());
          }

          final rooms = _rooms!;
          if (rooms.isEmpty) {
            return const _StatusCard(
              icon: Icons.meeting_room_outlined,
              message: 'No live rooms yet.',
            );
          }

          return Column(
            children: rooms
                .map(
                  (room) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RoomTile(
                      room: room,
                      isMember:
                          widget.currentUserId != null &&
                          room.memberIds.contains(widget.currentUserId),
                      onTap: () => widget.onJoinRoom(room),
                      onLeave: () => widget.onLeaveRoom(room),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  static List<_LiveRoom> _parseRooms(dynamic rawRooms) {
    if (rawRooms is! List) return const [];
    return rawRooms
        .whereType<Map<String, dynamic>>()
        .map(_LiveRoom.fromJson)
        .toList();
  }
}

class _RoomTile extends StatelessWidget {
  final _LiveRoom room;
  final bool isMember;
  final VoidCallback onTap;
  final VoidCallback onLeave;

  const _RoomTile({
    required this.room,
    required this.isMember,
    required this.onTap,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: isMember ? null : onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      tileColor: const Color(0xFF11141D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
      title: Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${room.memberCount} listeners · ${room.trackCount} tracks · ${room.status.toLowerCase()}',
      ),
      trailing: isMember
          ? IconButton(
              tooltip: 'Leave room',
              icon: const Icon(Icons.logout_rounded),
              onPressed: onLeave,
            )
          : const Icon(Icons.login_rounded),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String message;

  const _StatusCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF11141D),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF98A2B3)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF98A2B3)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveRoom {
  final int id;
  final String name;
  final int memberCount;
  final int trackCount;
  final String status;
  final List<int> memberIds;

  const _LiveRoom({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.trackCount,
    required this.status,
    required this.memberIds,
  });

  factory _LiveRoom.fromJson(Map<String, dynamic> json) {
    final rawMemberIds = json['memberIds'];
    final memberIds = rawMemberIds is List
        ? rawMemberIds.map(_toInt).toList()
        : <int>[];
    return _LiveRoom(
      id: _toInt(json['id']),
      name: json['name'] as String? ?? 'Untitled room',
      memberCount: memberIds.length,
      trackCount: json['playlist'] is List
          ? (json['playlist'] as List).length
          : 0,
      status: json['status'] as String? ?? 'IDLE',
      memberIds: memberIds,
    );
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
