import 'package:flutter/material.dart';

import '../network/playlist.dart';
import '../objects/user_playlist.dart';

Future<void> showAddToPlaylistSheet(BuildContext context, int musicId) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF11141D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (ctx) => _AddToPlaylistSheet(musicId: musicId),
  );
}

class _AddToPlaylistSheet extends StatefulWidget {
  final int musicId;

  const _AddToPlaylistSheet({required this.musicId});

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  bool _isCreating = false;
  bool _isLoading = true;
  List<UserPlaylist> _playlists = [];
  final _nameController = TextEditingController();
  bool _newPlaylistPublic = true;
  String _newPlaylistEditPolicy = 'EVERYONE';

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final playlists = await PlaylistService.fetchMyPlaylists();
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addToPlaylist(UserPlaylist playlist) async {
    final success = await PlaylistService.addTrack(
      playlist.id,
      widget.musicId,
      expectedVersion: playlist.version,
    );

    if (!mounted) return;
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Added to "${playlist.name}"'
              : 'Failed to add to "${playlist.name}"',
        ),
      ),
    );
  }

  Future<void> _createAndAdd() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final outcome = await PlaylistService.createPlaylist(
      name,
      _newPlaylistPublic,
      editPolicy: _newPlaylistEditPolicy,
    );
    if (outcome.playlist == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(outcome.error ?? 'Failed to create playlist')),
      );
      return;
    }

    await PlaylistService.addTrack(
      outcome.playlist!.id,
      widget.musicId,
      expectedVersion: outcome.playlist!.version,
    );

    if (!mounted) return;
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Created "${outcome.playlist!.name}" and added track'),
      ),
    );
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
            'Add to playlist',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          // Create new playlist section
          if (_isCreating) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('add_to_playlist_name_field'),
                    controller: _nameController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Playlist name',
                      hintStyle: TextStyle(color: Colors.white38),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _createAndAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _newPlaylistPublic = !_newPlaylistPublic;
                    });
                  },
                  icon: Icon(
                    _newPlaylistPublic ? Icons.public : Icons.lock_outline,
                    color: Colors.white70,
                  ),
                  tooltip: _newPlaylistPublic ? 'Public' : 'Private',
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _newPlaylistEditPolicy =
                          _newPlaylistEditPolicy == 'EVERYONE'
                          ? 'COLLABORATORS'
                          : 'EVERYONE';
                    });
                  },
                  icon: Icon(
                    _newPlaylistEditPolicy == 'EVERYONE'
                        ? Icons.groups_rounded
                        : Icons.verified_user_rounded,
                    color: Colors.white70,
                  ),
                  tooltip: _newPlaylistEditPolicy == 'EVERYONE'
                      ? 'Everyone can edit'
                      : 'Collaborators can edit',
                ),
                TextButton(
                  key: const Key('add_to_playlist_create_button'),
                  onPressed: _createAndAdd,
                  child: const Text('Create'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ] else
            ListTile(
              key: const Key('add_to_playlist_create_toggle'),
              leading: const Icon(Icons.add, color: Colors.white70),
              title: const Text(
                'Create new playlist',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => setState(() => _isCreating = true),
              contentPadding: EdgeInsets.zero,
            ),
          const Divider(color: Colors.white12),
          // Existing playlists
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No playlists yet',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _playlists.length,
                itemBuilder: (context, index) {
                  final playlist = _playlists[index];
                  final alreadyAdded = playlist.containsMusic(widget.musicId);
                  return ListTile(
                    key: ValueKey('add_to_playlist_tile_${playlist.id}'),
                    leading: Icon(
                      playlist.isPublic
                          ? Icons.queue_music
                          : Icons.lock_outline,
                      color: Colors.white54,
                    ),
                    title: Text(
                      playlist.name,
                      style: TextStyle(
                        color: alreadyAdded
                            ? Colors.white.withValues(alpha: 0.4)
                            : Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      alreadyAdded
                          ? 'Already added'
                          : '${playlist.trackCount} track${playlist.trackCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: alreadyAdded
                            ? const Color(0xFF2DD4BF).withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    trailing: alreadyAdded
                        ? const Icon(
                            Icons.check_circle,
                            color: Color(0xFF2DD4BF),
                            size: 20,
                          )
                        : null,
                    onTap: alreadyAdded ? null : () => _addToPlaylist(playlist),
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
