import 'music_track.dart';

class UserPlaylist {
  final int id;
  final String name;
  final int ownerId;
  final bool isPublic;
  final String editPolicy;
  final int version;
  final bool canEdit;
  final int trackCount;
  final List<int> musicIds;
  final List<int> collaboratorIds;
  final List<MusicTrack> tracks;
  final int totalDuration;

  const UserPlaylist({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.isPublic,
    required this.editPolicy,
    required this.version,
    required this.canEdit,
    required this.trackCount,
    this.musicIds = const [],
    this.collaboratorIds = const [],
    this.tracks = const [],
    this.totalDuration = 0,
  });

  bool containsMusic(int musicId) => musicIds.contains(musicId);

  factory UserPlaylist.fromJson(Map<String, dynamic> json) {
    List<int> musicIds = [];
    var rawTracks = [];
    if (json['tracks'] != null) {
      rawTracks = json['tracks'] as List<dynamic>;
      musicIds = rawTracks
          .whereType<Map<String, dynamic>>()
          .map((trackJson) => trackJson['music_id'] as int)
          .toList();
    } else if (json['music_ids'] != null) {
      final rawMusicIds = json['music_ids'] as List<dynamic>;
      musicIds = rawMusicIds.whereType<int>().toList();
    }
    final rawCollaborators = json['collaborator_ids'];
    var collaboratorIds = <int>[];
    if (rawCollaborators is List) {
      collaboratorIds = rawCollaborators.whereType<int>().toList();
    }
    var tracks = <MusicTrack>[];
    if (json['tracks'] is List) {
      tracks = (json['tracks'] as List)
          .whereType<Map<String, dynamic>>()
          .map(_trackFromPlaylistJson)
          .toList();
    }
    final totalDuration = tracks.fold<int>(
      0,
      (sum, track) => sum + track.duration,
    );
    return UserPlaylist(
      id: json['id'] as int,
      name: json['name'] as String,
      ownerId: json['owner_id'] as int,
      isPublic: json['is_public'] == true,
      editPolicy: json['edit_policy'] as String? ?? 'EVERYONE',
      version: json['version'] as int? ?? 0,
      canEdit: json['can_edit'] == null || json['can_edit'] == true,
      trackCount: json['track_count'] as int? ?? musicIds.length,
      musicIds: musicIds,
      collaboratorIds: collaboratorIds,
      totalDuration: totalDuration,
      tracks: tracks,
    );
  }

  static MusicTrack _trackFromPlaylistJson(Map<String, dynamic> json) {
    final musicId = json['music_id'];
    if (musicId is int) {
      return MusicTrack.fromJson({...json, 'id': musicId});
    }
    return MusicTrack.fromJson(json);
  }
}
