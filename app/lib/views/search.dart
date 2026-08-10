import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pmr_music_room/views/utils/scaffold.dart';
import 'package:provider/provider.dart';

import '../network/music.dart';
import '../network/playlist.dart';
import '../objects/music_service_result.dart';
import '../objects/music_track.dart';
import '../objects/user_playlist.dart';
import '../objects/vote_event.dart';
import '../state/music_player_controller.dart';
import 'add_to_playlist_sheet.dart';
import 'add_to_track_vote_sheet.dart';
import 'playlist.dart';
import 'track_vote.dart';

enum _SearchTab { music, playlists, voteEvents }

class SearchScreen extends StatefulWidget {
  static const routeName = '/search';

  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  _SearchTab _selectedTab = _SearchTab.music;

  List<MusicTrack> _musicResults = [];
  bool _isMusicLoading = false;
  String? _musicErrorMessage;

  List<UserPlaylist> _playlistResults = [];
  bool _isPlaylistLoading = false;
  String? _playlistErrorMessage;

  List<VoteEvent> _voteEventResults = [];
  bool _isVoteEventLoading = false;
  String? _voteEventErrorMessage;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _musicResults = [];
        _musicErrorMessage = null;
        _playlistResults = [];
        _playlistErrorMessage = null;
        _voteEventResults = [];
        _voteEventErrorMessage = null;
      });
      return;
    }

    setState(() {
      _isMusicLoading = true;
      _musicErrorMessage = null;
      _isPlaylistLoading = true;
      _playlistErrorMessage = null;
      _isVoteEventLoading = true;
      _voteEventErrorMessage = null;
    });

    final results = await Future.wait([
      MusicService.searchTracks(trimmed),
      PlaylistService.searchPlaylists(trimmed),
      VoteEventService.search(trimmed),
    ]);

    if (!mounted) return;

    final musicResult = results[0] as MusicServiceResult;
    final playlistResult = results[1] as List<UserPlaylist>;
    final voteEventResult = results[2] as List<VoteEvent>;

    setState(() {
      _isMusicLoading = false;
      _musicResults = musicResult.tracks;
      _musicErrorMessage = musicResult.success ? null : musicResult.message;

      _isPlaylistLoading = false;
      _playlistResults = playlistResult;

      _isVoteEventLoading = false;
      _voteEventResults = voteEventResult;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MusicRoomScaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              key: const Key('search_field'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by title or artist...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('Music (${_musicResults.length})'),
                    selected: _selectedTab == _SearchTab.music,
                    onSelected: (_) =>
                        setState(() => _selectedTab = _SearchTab.music),
                    showCheckmark: false
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Playlists (${_playlistResults.length})'),
                    selected: _selectedTab == _SearchTab.playlists,
                    onSelected: (_) =>
                        setState(() => _selectedTab = _SearchTab.playlists),
                    showCheckmark: false
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Vote Events (${_voteEventResults.length})'),
                    selected: _selectedTab == _SearchTab.voteEvents,
                    onSelected: (_) =>
                        setState(() => _selectedTab = _SearchTab.voteEvents),
                    showCheckmark: false
                  ),
                ],
              ),
            ),
          ),
          if (_activeErrorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _activeErrorMessage!,
                style: TextStyle(color: Colors.orange.shade300, fontSize: 13),
              ),
            ),
          Expanded(child: _buildActiveTabBody()),
        ],
      ),
    );
  }

  String? get _activeErrorMessage => switch (_selectedTab) {
    _SearchTab.music => _musicErrorMessage,
    _SearchTab.playlists => _playlistErrorMessage,
    _SearchTab.voteEvents => _voteEventErrorMessage,
  };

  Widget _buildActiveTabBody() {
    if (_selectedTab == _SearchTab.music) {
      if (_isMusicLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_musicResults.isEmpty) {
        return Center(
          child: Text(
            _controller.text.isEmpty
                ? 'Type to search for music'
                : 'No tracks found',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 15,
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _musicResults.length,
        itemBuilder: (context, index) {
          final track = _musicResults[index];
          return _SearchResultTile(track: track);
        },
      );
    }

    if (_selectedTab == _SearchTab.voteEvents) {
      if (_isVoteEventLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_voteEventResults.isEmpty) {
        return Center(
          child: Text(
            _controller.text.isEmpty
                ? 'Type to search for vote events'
                : 'No vote events found',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 15,
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _voteEventResults.length,
        itemBuilder: (context, index) {
          final event = _voteEventResults[index];
          return _VoteEventResultTile(event: event);
        },
      );
    }

    if (_isPlaylistLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_playlistResults.isEmpty) {
      return Center(
        child: Text(
          _controller.text.isEmpty
              ? 'Type to search for playlists'
              : 'No playlists found',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 15,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _playlistResults.length,
      itemBuilder: (context, index) {
        final playlist = _playlistResults[index];
        return _PlaylistResultTile(playlist: playlist);
      },
    );
  }
}

class _PlaylistResultTile extends StatelessWidget {
  final UserPlaylist playlist;

  const _PlaylistResultTile({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF1E2030),
        child: Icon(
          playlist.isPublic ? Icons.queue_music : Icons.lock_outline,
          color: Colors.white70,
        ),
      ),
      title: Text(playlist.name, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        '${playlist.trackCount} track${playlist.trackCount == 1 ? '' : 's'} · ${playlist.isPublic ? 'Public' : 'Private'}',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white70),
      onTap: () {
        context.push(
          PlaylistScreen.routeName,
          extra: PlaylistScreenArgs(
            title: playlist.name,
            subtitle:
                '${playlist.trackCount} track${playlist.trackCount == 1 ? '' : 's'}',
            playlistId: playlist.id,
          ),
        );
      },
    );
  }
}

class _VoteEventResultTile extends StatelessWidget {
  final VoteEvent event;

  const _VoteEventResultTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF1E2030),
        child: Icon(
          event.isPublic ? Icons.how_to_vote : Icons.lock_outline,
          color: Colors.white70,
        ),
      ),
      title: Text(event.name, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        '${event.tracks.length} track${event.tracks.length == 1 ? '' : 's'} · ${event.isPublic ? 'Public' : 'Private'} · ${event.policyLabel}',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white70),
      onTap: () {
        context.push(VoteEventScreen.routeName, extra: event);
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final MusicTrack track;

  const _SearchResultTile({required this.track});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('search_result_tile_${track.id}'),
      leading: const CircleAvatar(
        backgroundColor: Color(0xFF1E2030),
        child: Icon(Icons.music_note, color: Colors.white70),
      ),
      title: Text(track.title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(
        [
          if (track.artistName != null) track.artistName!,
          _formatDuration(track.duration),
        ].join(' · '),
        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey('search_result_menu_${track.id}'),
        icon: const Icon(Icons.more_vert, color: Colors.white70),
        color: const Color(0xFF1E2030),
        onSelected: (value) async {
          switch (value) {
            case 'queue':
              final player = context.read<MusicPlayerController>();
              final added = await player.addToQueue(track);
              if (!context.mounted) return;
              if (added) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added "${track.title}" to queue')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to add "${track.title}" to queue'),
                  ),
                );
              }
            case 'playlist':
              showAddToPlaylistSheet(context, track.id);
            case 'track_vote':
              showAddToTrackVoteSheet(context, track.id);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'queue',
            child: ListTile(
              leading: Icon(Icons.queue_play_next, color: Colors.white70),
              title: Text(
                'Add to queue',
                style: TextStyle(color: Colors.white),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'playlist',
            child: ListTile(
              leading: Icon(Icons.playlist_add, color: Colors.white70),
              title: Text(
                'Add to playlist',
                style: TextStyle(color: Colors.white),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const PopupMenuItem(
            value: 'track_vote',
            child: ListTile(
              leading: Icon(Icons.how_to_vote, color: Colors.white70),
              title: Text(
                'Add to track vote',
                style: TextStyle(color: Colors.white),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
