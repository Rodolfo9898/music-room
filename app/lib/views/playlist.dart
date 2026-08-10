import 'package:flutter/material.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:pmr_music_room/views/utils/scaffold.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/music.dart';
import '../network/playlist.dart';
import '../network/web_socket.dart';
import '../objects/music_track.dart';
import '../objects/user_playlist.dart';
import '../state/music_player_controller.dart';
import '../config/constants.dart';

class PlaylistScreenArgs {
  final String title;
  final String subtitle;
  final int playlistId;

  const PlaylistScreenArgs({
    required this.title,
    required this.subtitle,
    required this.playlistId,
  });
}

class PlaylistScreen extends StatefulWidget {
  static const routeName = '/playlist';

  final String title;
  final String subtitle;
  final int playlistId;

  const PlaylistScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.playlistId,
  });

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  UserPlaylist? _playlist;
  bool _isLoading = true;
  bool _isMutating = false;
  String? _statusMessage;
  int? _accountId;

  @override
  void initState() {
    super.initState();
    _loadPlaylist();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(
          () => _accountId = prefs.getInt(SharedPreferencesKeys.accountId),
        );
      }
    });
  }

  Future<void> _loadPlaylist() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });
    final playlist = await PlaylistService.fetchPlaylist(widget.playlistId);
    if (!mounted) return;
    setState(() {
      _playlist = playlist;
      _isLoading = false;
      _statusMessage = playlist == null ? 'Unable to load playlist.' : null;
    });
  }

  void _applyLivePlaylist(UserPlaylist playlist) {
    if (_playlist?.musicIds.join(',') == playlist.musicIds.join(',') &&
        _playlist?.isPublic == playlist.isPublic &&
        _playlist?.editPolicy == playlist.editPolicy &&
        _playlist?.version == playlist.version &&
        _playlist?.canEdit == playlist.canEdit &&
        _playlist?.collaboratorIds.length == playlist.collaboratorIds.length) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _playlist = playlist;
        _statusMessage = 'Playlist synced in real time.';
      });
    });
  }

  Future<void> _toggleVisibility(UserPlaylist playlist) async {
    await _runMutation(
      () => PlaylistService.updateVisibility(
        playlist.id,
        !playlist.isPublic,
        expectedVersion: playlist.version,
      ),
      successMessage: playlist.isPublic
          ? 'Playlist is now private.'
          : 'Playlist is now public.',
    );
  }

  Future<void> _toggleEditPolicy(UserPlaylist playlist) async {
    final nextPolicy = playlist.editPolicy == 'EVERYONE'
        ? 'COLLABORATORS'
        : 'EVERYONE';
    await _runMutation(
      () => PlaylistService.updateEditPolicy(
        playlist.id,
        nextPolicy,
        expectedVersion: playlist.version,
      ),
      successMessage: nextPolicy == 'EVERYONE'
          ? 'Everyone can edit this playlist.'
          : 'Only collaborators can edit this playlist.',
    );
  }

  Future<void> _inviteCollaborator(UserPlaylist playlist) async {
    final dialogFormKey = GlobalKey<FormState>();
    final controller = TextEditingController();
    bool isSubmitting = false;

    await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final isValid = dialogFormKey.currentState?.validate() ?? false;
              if (!isValid || isSubmitting) {
                return;
              }

              final email = controller.text.trim();
              if (email.isEmpty) return;

              setDialogState(() {
                isSubmitting = true;
              });

              await _runMutation(
                () => PlaylistService.inviteCollaborator(
                  playlist.id,
                  email,
                  expectedVersion: playlist.version,
                ),
                successMessage: 'Collaborator invited.',
              );

              if (!dialogContext.mounted) {
                return;
              }

              Navigator.of(dialogContext).pop();

              if (!mounted) {
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Successfully added $email")),
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF11141D),
              title: const Text('Invite collaborator'),
              content: Form(
                key: dialogFormKey,
                child: TextField(
                  key: const Key('playlist_invite_email_field'),
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  onSubmitted: (value) =>
                      Navigator.of(context).pop(value.trim()),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const Key('playlist_invite_submit_button'),
                  onPressed: isSubmitting ? null : submit,
                  child: isSubmitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Invite'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addTrack(UserPlaylist playlist) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => _TrackSearchSheet(
        playlistId: playlist.id,
        playlistVersion: playlist.version,
        playlistTrackIds: playlist.musicIds,
      ),
    );
    if (added == true) {
      await _loadPlaylist();
    }
  }

  Future<void> _removeTrack(UserPlaylist playlist, MusicTrack track) async {
    if (!playlist.canEdit) return;
    setState(() => _isMutating = true);
    final success = await PlaylistService.removeTrack(
      playlist.id,
      track.id,
      expectedVersion: playlist.version,
    );
    if (!mounted) return;
    setState(() {
      _isMutating = false;
      _statusMessage = success
          ? 'Removed "${track.title}".'
          : 'Could not remove "${track.title}".';
    });
    if (success) await _loadPlaylist();
  }

  Future<void> _play(UserPlaylist playlist) async {
    final player = Provider.of<MusicPlayerController>(context, listen: false);
    final queued = await player.setQueue(playlist.tracks);
    if (!queued) {
      if (mounted) {
        setState(() => _statusMessage = 'Could not start playback.');
      }
      return;
    }
    await player.playQueueTrack(0);
  }

  Future<void> _onReorder(
    UserPlaylist playlist,
    int oldIndex,
    int newIndex,
  ) async {
    if (!playlist.canEdit) return;
    final tracks = [...playlist.tracks];
    final moved = tracks.removeAt(oldIndex);
    tracks.insert(newIndex, moved);
    setState(() {
      _playlist = UserPlaylist(
        id: playlist.id,
        name: playlist.name,
        ownerId: playlist.ownerId,
        isPublic: playlist.isPublic,
        editPolicy: playlist.editPolicy,
        version: playlist.version,
        canEdit: playlist.canEdit,
        trackCount: tracks.length,
        musicIds: tracks.map((track) => track.id).toList(),
        collaboratorIds: playlist.collaboratorIds,
        tracks: tracks,
      );
      _isMutating = true;
    });
    final success = await PlaylistService.moveTrack(
      playlist.id,
      moved.id,
      newIndex,
      expectedVersion: playlist.version,
    );
    if (!mounted) return;
    setState(() {
      _isMutating = false;
      _statusMessage = success ? 'Order updated.' : 'Could not reorder track.';
    });
    if (!success) await _loadPlaylist();
  }

  Future<void> _runMutation(
    Future<UserPlaylist?> Function() action, {
    required String successMessage,
  }) async {
    setState(() => _isMutating = true);
    final playlist = await action();
    if (!mounted) return;
    setState(() {
      _isMutating = false;
      if (playlist != null) {
        _playlist = playlist;
        _statusMessage = successMessage;
      } else {
        _statusMessage = 'Operation failed.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const pageBackground = Color(0xFF090B11);
    final client = GraphQLConnection().client;

    return MusicRoomScaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(title: Text(_playlist?.name ?? widget.title)),
      body: SafeArea(
        child: client == null
            ? const Center(child: Text('Realtime connection is unavailable.'))
            : GraphQLProvider(
                client: client,
                child: Subscription(
                  options: PlaylistService.playlistUpdatedOptions(
                    widget.playlistId,
                  ),
                  builder: (result) {
                    final data = result.data?['playlistUpdated'];
                    if (data is Map<String, dynamic>) {
                      _applyLivePlaylist(UserPlaylist.fromJson(data));
                    }
                    if (_isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final playlist = _playlist;
                    if (playlist == null) {
                      return _StatusPanel(
                        icon: Icons.error_outline,
                        title: 'Playlist unavailable',
                        message: _statusMessage ?? 'Unable to open playlist.',
                        onRetry: _loadPlaylist,
                      );
                    }
                    return _PlaylistEditor(
                      playlist: playlist,
                      isOwner: playlist.ownerId == _accountId,
                      isMutating: _isMutating,
                      statusMessage: result.hasException
                          ? 'Live sync disconnected.'
                          : _statusMessage,
                      onToggleVisibility: () => _toggleVisibility(playlist),
                      onToggleEditPolicy: () => _toggleEditPolicy(playlist),
                      onInvite: () => _inviteCollaborator(playlist),
                      onAddTrack: () => _addTrack(playlist),
                      onRemoveTrack: (track) => _removeTrack(playlist, track),
                      onPlay: () => _play(playlist),
                      onReorder: (oldIndex, newIndex) =>
                          _onReorder(playlist, oldIndex, newIndex),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _PlaylistEditor extends StatelessWidget {
  final UserPlaylist playlist;
  final bool isOwner;
  final bool isMutating;
  final String? statusMessage;
  final VoidCallback onToggleVisibility;
  final VoidCallback onToggleEditPolicy;
  final VoidCallback onInvite;
  final VoidCallback onAddTrack;
  final ValueChanged<MusicTrack> onRemoveTrack;
  final ReorderCallback onReorder;
  final VoidCallback onPlay;

  const _PlaylistEditor({
    required this.playlist,
    required this.isOwner,
    required this.isMutating,
    required this.statusMessage,
    required this.onToggleVisibility,
    required this.onToggleEditPolicy,
    required this.onInvite,
    required this.onAddTrack,
    required this.onRemoveTrack,
    required this.onReorder,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final canInteractWithTracks = playlist.canEdit && !isMutating;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _PlaylistHeader(
                      playlist: playlist,
                      isOwner: isOwner,
                      onToggleVisibility: onToggleVisibility,
                      onToggleEditPolicy: onToggleEditPolicy,
                      onInvite: onInvite,
                      onPlay: onPlay,
                    ),
                    if (statusMessage != null) ...[
                      const SizedBox(height: 14),
                      _StatusBanner(message: statusMessage!),
                    ],
                    if (isMutating) ...[
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Tracks',
                            style: TextStyle(
                              color: Color(0xFFF4F7FB),
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (playlist.canEdit)
                          FilledButton.icon(
                            key: const Key('playlist_add_track_button'),
                            onPressed: canInteractWithTracks
                                ? onAddTrack
                                : null,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!playlist.canEdit)
                      const _StatusBanner(
                        message:
                            'Read-only view. Public playlists are editable by everyone; private playlists require an invite.',
                      ),
                  ]),
                ),
              ),
              if (playlist.tracks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyPlaylist(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  sliver: SliverReorderableList(
                    itemCount: playlist.tracks.length,
                    onReorderItem: canInteractWithTracks
                        ? onReorder
                        : (oldIndex, newIndex) {},
                    itemBuilder: (context, index) {
                      final track = playlist.tracks[index];
                      return _TrackTile(
                        key: ValueKey(track.id),
                        track: track,
                        index: index,
                        canEdit: playlist.canEdit,
                        isMutating: isMutating,
                        onRemove: () => onRemoveTrack(track),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  final UserPlaylist playlist;
  final bool isOwner;
  final VoidCallback onToggleVisibility;
  final VoidCallback onToggleEditPolicy;
  final VoidCallback onInvite;
  final VoidCallback onPlay;

  const _PlaylistHeader({
    required this.playlist,
    required this.isOwner,
    required this.onToggleVisibility,
    required this.onToggleEditPolicy,
    required this.onInvite,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).secondaryHeaderColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                key: const Key('playlist_toggle_visibility_button'),
                onPressed: isOwner ? onToggleVisibility : null,
                tooltip: playlist.isPublic ? 'Make private' : 'Make public',
                icon: Icon(
                  playlist.isPublic
                      ? Icons.public_rounded
                      : Icons.lock_outline_rounded,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('playlist_toggle_edit_policy_button'),
                onPressed: isOwner ? onToggleEditPolicy : null,
                tooltip: playlist.editPolicy == 'EVERYONE'
                    ? 'Restrict editing to collaborators'
                    : 'Allow everyone to edit',
                icon: Icon(
                  playlist.editPolicy == 'EVERYONE'
                      ? Icons.groups_rounded
                      : Icons.verified_user_rounded,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('playlist_invite_button'),
                onPressed: isOwner ? onInvite : null,
                tooltip: 'Invite collaborator',
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
              const Spacer(),
              IconButton.filled(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            playlist.name,
            style: const TextStyle(
              fontSize: 32,
              height: 1.0,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${playlist.isPublic ? 'Public' : 'Private'} playlist - ${playlist.editPolicy == 'EVERYONE' ? 'everyone can edit' : 'invited collaborators can edit'}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '${playlist.tracks.length} tracks - ${_formatDuration(Duration(seconds: playlist.totalDuration))} - ${playlist.collaboratorIds.length} collaborators',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackSearchSheet extends StatefulWidget {
  final int playlistId;
  final int playlistVersion;
  final List<int> playlistTrackIds;

  const _TrackSearchSheet({
    required this.playlistId,
    required this.playlistVersion,
    required this.playlistTrackIds,
  });

  @override
  State<_TrackSearchSheet> createState() => _TrackSearchSheetState();
}

class _TrackSearchSheetState extends State<_TrackSearchSheet> {
  final _controller = TextEditingController();
  List<MusicTrack> _tracks = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      setState(() => _tracks = []);
      return;
    }
    setState(() => _isLoading = true);
    final result = await MusicService.searchTracks(query);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _tracks = result.tracks;
    });
  }

  Future<void> _add(MusicTrack track) async {
    final success = await PlaylistService.addTrack(
      widget.playlistId,
      track.id,
      expectedVersion: widget.playlistVersion,
    );
    if (!mounted) return;
    Navigator.of(context).pop(success);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Added "${track.title}".'
              : 'Could not add "${track.title}".',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        18,
        16,
        MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add track',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('playlist_track_search_field'),
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Search title or artist',
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: _tracks.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Search for a track to add.')),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _tracks.length,
                      itemBuilder: (context, index) {
                        final track = _tracks[index];
                        return ListTile(
                          key: ValueKey('playlist_track_result_${track.id}'),
                          leading: const Icon(Icons.music_note_rounded),
                          title: Text(track.title),
                          subtitle: Text(
                            track.artistName ??
                                _formatDuration(
                                  Duration(seconds: track.duration),
                                ),
                          ),
                          onTap: widget.playlistTrackIds.contains(track.id)
                              ? null
                              : () => _add(track),
                          trailing: widget.playlistTrackIds.contains(track.id)
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String message;

  const _StatusBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD166).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFD166).withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFFFD166),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final MusicTrack track;
  final int index;
  final bool canEdit;
  final bool isMutating;
  final VoidCallback onRemove;

  const _TrackTile({
    super.key,
    required this.track,
    required this.index,
    required this.canEdit,
    required this.isMutating,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF11141D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              key: ValueKey('playlist_track_drag_handle_${track.id}'),
              index: index,
              enabled: canEdit && !isMutating,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: Icon(
                  canEdit
                      ? Icons.drag_handle_rounded
                      : Icons.music_note_rounded,
                  color: Colors.white,
                ),
              ),
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
                    style: const TextStyle(
                      color: Color(0xFFF4F7FB),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (track.artistName != null)
                    Text(
                      '${track.artistName}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              _formatDuration(Duration(seconds: track.duration)),
              style: const TextStyle(
                color: Color(0xFF98A2B3),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (canEdit) ...[
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey('playlist_remove_track_button_${track.id}'),
                onPressed: isMutating ? null : onRemove,
                icon: const Icon(Icons.remove_circle_outline_rounded),
                color: const Color(0xFFFF7A45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyPlaylist extends StatelessWidget {
  const _EmptyPlaylist();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No tracks yet. Add a track to start collaborating.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _StatusPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF98A2B3)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
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
