import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pmr_music_room/views/utils/scaffold.dart';

import '../network/playlist.dart';
import '../objects/user_playlist.dart';
import 'playlist.dart';

class MyPlaylistsScreen extends StatefulWidget {
  static const routeName = '/my-playlists';

  const MyPlaylistsScreen({super.key});

  @override
  State<MyPlaylistsScreen> createState() => _MyPlaylistsScreenState();
}

class _MyPlaylistsScreenState extends State<MyPlaylistsScreen> {
  List<UserPlaylist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _isLoading = true);
    final playlists = await PlaylistService.fetchMyPlaylists();
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _isLoading = false;
    });
  }

  Future<void> _showCreateDialog() async {
    final dialogFormKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    bool isPublic = true;
    String editPolicy = 'EVERYONE';

    bool isSubmitting = false;

    String? validateName(String? value) {
      final name = value?.trim() ?? '';
      if (name.isEmpty) {
        return 'Name is required';
      }

      return null;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final isValid = dialogFormKey.currentState?.validate() ?? false;
              if (!isValid || isSubmitting) {
                return;
              }

              setDialogState(() {
                isSubmitting = true;
              });

              final result = await PlaylistService.createPlaylist(
                nameController.text.trim(),
                isPublic,
                editPolicy: editPolicy,
              );

              if (!dialogContext.mounted) {
                return;
              }

              Navigator.of(dialogContext).pop();

              if (!mounted) {
                return;
              }

              if (result.playlist != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Created "${result.playlist!.name}"')),
                );
                _loadPlaylists();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.error ?? 'Failed to create playlist'),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Text('New playlist'),
              content: Form(
                key: dialogFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const Key('playlist_dialog_name_field'),
                      controller: nameController,
                      autofocus: true,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Playlist name',
                      ),
                      onFieldSubmitted: (_) => submit(),
                      validator: validateName,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      key: const Key('playlist_dialog_public_switch'),
                      title: const Text('Public'),
                      subtitle: Text(
                        isPublic
                            ? 'Anyone can see this playlist'
                            : 'Only you and collaborators',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      value: isPublic,
                      onChanged: (v) => setDialogState(() => isPublic = v),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      key: const Key('playlist_dialog_edit_policy_switch'),
                      title: const Text('Collaborators only'),
                      subtitle: Text(
                        editPolicy == 'EVERYONE'
                            ? 'Everyone with access can edit'
                            : 'Only invited collaborators can edit',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      value: editPolicy == 'COLLABORATORS',
                      onChanged: (v) => setDialogState(
                        () => editPolicy = v ? 'COLLABORATORS' : 'EVERYONE',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const Key('playlist_dialog_create_button'),
                  onPressed: isSubmitting || nameController.value.text.isEmpty
                      ? null
                      : submit,
                  child: isSubmitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create playlist'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MusicRoomScaffold(
      appBar: AppBar(title: const Text('My playlists')),
      floatingActionButton: FloatingActionButton(
        key: const Key('my_playlists_fab'),
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.queue_music,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No playlists yet',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to create one',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _playlists.length,
              itemBuilder: (context, index) {
                final playlist = _playlists[index];
                return _PlaylistListTile(
                  key: ValueKey('playlist_tile_${playlist.id}'),
                  playlist: playlist,
                  onTap: () async {
                    await context.push(
                      PlaylistScreen.routeName,
                      extra: PlaylistScreenArgs(
                        title: playlist.name,
                        subtitle:
                            '${playlist.trackCount} track${playlist.trackCount == 1 ? '' : 's'}',
                        playlistId: playlist.id,
                      ),
                    );
                    _loadPlaylists();
                  },
                );
              },
            ),
    );
  }
}

class _PlaylistListTile extends StatelessWidget {
  final UserPlaylist playlist;
  final VoidCallback onTap;

  const _PlaylistListTile({
    super.key,
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF1E2030),
        child: Icon(playlist.isPublic ? Icons.queue_music : Icons.lock_outline),
      ),
      title: Text(
        playlist.name,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      subtitle: Text(
        '${playlist.trackCount} track${playlist.trackCount == 1 ? '' : 's'} · ${playlist.isPublic ? 'Public' : 'Private'} · ${playlist.editPolicy == 'EVERYONE' ? 'Everyone edits' : 'Collaborators edit'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
