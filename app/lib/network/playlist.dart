import 'package:graphql_flutter/graphql_flutter.dart';

import '../objects/user_playlist.dart';
import 'web_socket.dart';

class PlaylistService {
  static const String _playlistFields = r'''
    id
    name
    owner_id
    is_public
    edit_policy
    version
    can_edit
    track_count
    music_ids
    collaborator_ids
    tracks {
      id
      playlist_id
      music_id
      position
      title
      artist_id
      genre_id
      duration
      file_path
      artist_name
    }
  ''';

  static const String _myPlaylistsQuery =
      r'''
    query MyPlaylists {
      myPlaylists {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static const String _searchPlaylistsQuery =
      r'''
    query SearchPlaylists($query: String!) {
      searchPlaylists(query: $query) {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static const String _playlistDetailQuery =
      r'''
    query PlaylistDetail($id: Int!) {
      playlist(id: $id) {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static const String _playlistUpdatedSubscription =
      r'''
    subscription PlaylistUpdated($playlistId: Int!) {
      playlistUpdated(playlistId: $playlistId) {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static const String _createPlaylistMutation =
      r'''
    mutation CreatePlaylist($name: String!, $isPublic: Boolean!, $editPolicy: PlaylistEditPolicy!) {
      createPlaylist(name: $name, isPublic: $isPublic, editPolicy: $editPolicy) {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static const String _addTrackMutation =
      r'''
    mutation AddTrackToPlaylist($playlistId: Int!, $musicId: Int!, $expectedVersion: Int) {
      addTrackToPlaylist(playlistId: $playlistId, musicId: $musicId, expectedVersion: $expectedVersion) {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static const String _removeTrackMutation =
      r'''
    mutation RemoveTrackFromPlaylist($playlistId: Int!, $musicId: Int!, $expectedVersion: Int) {
      removeTrackFromPlaylist(playlistId: $playlistId, musicId: $musicId, expectedVersion: $expectedVersion) {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static const String _moveTrackMutation =
      r'''
    mutation MoveTrackInPlaylist($playlistId: Int!, $musicId: Int!, $newPosition: Int!, $expectedVersion: Int) {
      moveTrackInPlaylist(playlistId: $playlistId, musicId: $musicId, newPosition: $newPosition, expectedVersion: $expectedVersion) {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static const String _visibilityMutation =
      r'''
    mutation UpdatePlaylistVisibility($playlistId: Int!, $isPublic: Boolean!, $expectedVersion: Int) {
      updatePlaylistVisibility(playlistId: $playlistId, isPublic: $isPublic, expectedVersion: $expectedVersion) {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static const String _editPolicyMutation =
      r'''
    mutation UpdatePlaylistEditPolicy($playlistId: Int!, $editPolicy: PlaylistEditPolicy!, $expectedVersion: Int) {
      updatePlaylistEditPolicy(playlistId: $playlistId, editPolicy: $editPolicy, expectedVersion: $expectedVersion) {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static const String _inviteMutation =
      r'''
    mutation InvitePlaylistCollaborator($playlistId: Int!, $email: String!, $expectedVersion: Int) {
      invitePlaylistCollaborator(playlistId: $playlistId, email: $email, expectedVersion: $expectedVersion) {
''' +
      _playlistFields +
      r'''
      }
    }
  ''';

  static Future<List<UserPlaylist>> fetchMyPlaylists() async {
    final client = GraphQLConnection().client?.value;
    if (client == null) return [];

    try {
      final result = await client.query(
        QueryOptions(
          document: gql(_myPlaylistsQuery),
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
      final data = result.data?['myPlaylists'];
      if (result.hasException || data is! List) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(UserPlaylist.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<UserPlaylist>> searchPlaylists(String query) async {
    final client = GraphQLConnection().client?.value;
    if (client == null) return [];

    try {
      final result = await client.query(
        QueryOptions(
          document: gql(_searchPlaylistsQuery),
          variables: {'query': query},
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
      final data = result.data?['searchPlaylists'];
      if (result.hasException || data is! List) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(UserPlaylist.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<UserPlaylist?> fetchPlaylist(int id) async {
    final client = GraphQLConnection().client?.value;
    if (client == null) return null;

    try {
      final result = await client.query(
        QueryOptions(
          document: gql(_playlistDetailQuery),
          variables: {'id': id},
          fetchPolicy: FetchPolicy.noCache,
        ),
      );

      if (result.hasException) return null;

      final data = result.data?['playlist'];

      if (data is! Map<String, dynamic>) return null;
      return UserPlaylist.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static Future<({UserPlaylist? playlist, String? error})> createPlaylist(
    String name,
    bool isPublic, {
    String editPolicy = 'EVERYONE',
  }) async {
    final client = GraphQLConnection().client?.value;
    if (client == null) {
      return (playlist: null, error: 'Could not reach the server.');
    }

    try {
      final result = await client.mutate(
        MutationOptions(
          document: gql(_createPlaylistMutation),
          variables: {
            'name': name,
            'isPublic': isPublic,
            'editPolicy': editPolicy,
          },
        ),
      );

      if (result.hasException) {
        final message = result.exception?.graphqlErrors.firstOrNull?.message;
        return (playlist: null, error: message ?? 'Failed to create playlist.');
      }

      final data = result.data?['createPlaylist'];
      if (data is! Map<String, dynamic>) {
        return (playlist: null, error: 'Invalid response from server.');
      }

      return (playlist: UserPlaylist.fromJson(data), error: null);
    } catch (e) {
      return (playlist: null, error: 'Could not reach the server.');
    }
  }

  static Future<bool> addTrack(
    int playlistId,
    int musicId, {
    int? expectedVersion,
  }) async {
    return _runPlaylistMutation(_addTrackMutation, {
      'playlistId': playlistId,
      'musicId': musicId,
      'expectedVersion': expectedVersion,
    }, 'addTrackToPlaylist');
  }

  static Future<bool> removeTrack(
    int playlistId,
    int musicId, {
    int? expectedVersion,
  }) async {
    return _runPlaylistMutation(_removeTrackMutation, {
      'playlistId': playlistId,
      'musicId': musicId,
      'expectedVersion': expectedVersion,
    }, 'removeTrackFromPlaylist');
  }

  static Future<bool> moveTrack(
    int playlistId,
    int musicId,
    int newPosition, {
    int? expectedVersion,
  }) async {
    return _runPlaylistMutation(_moveTrackMutation, {
      'playlistId': playlistId,
      'musicId': musicId,
      'newPosition': newPosition,
      'expectedVersion': expectedVersion,
    }, 'moveTrackInPlaylist');
  }

  static Future<UserPlaylist?> updateVisibility(
    int playlistId,
    bool isPublic, {
    int? expectedVersion,
  }) async {
    return _runPlaylistMutationReturningPlaylist(_visibilityMutation, {
      'playlistId': playlistId,
      'isPublic': isPublic,
      'expectedVersion': expectedVersion,
    }, 'updatePlaylistVisibility');
  }

  static Future<UserPlaylist?> updateEditPolicy(
    int playlistId,
    String editPolicy, {
    int? expectedVersion,
  }) async {
    return _runPlaylistMutationReturningPlaylist(_editPolicyMutation, {
      'playlistId': playlistId,
      'editPolicy': editPolicy,
      'expectedVersion': expectedVersion,
    }, 'updatePlaylistEditPolicy');
  }

  static Future<UserPlaylist?> inviteCollaborator(
    int playlistId,
    String email, {
    int? expectedVersion,
  }) async {
    return _runPlaylistMutationReturningPlaylist(_inviteMutation, {
      'playlistId': playlistId,
      'email': email,
      'expectedVersion': expectedVersion,
    }, 'invitePlaylistCollaborator');
  }

  static SubscriptionOptions playlistUpdatedOptions(int playlistId) {
    return SubscriptionOptions(
      document: gql(_playlistUpdatedSubscription),
      variables: {'playlistId': playlistId},
      fetchPolicy: FetchPolicy.noCache,
    );
  }

  static Future<bool> _runPlaylistMutation(
    String mutation,
    Map<String, dynamic> variables,
    String dataKey,
  ) async {
    final playlist = await _runPlaylistMutationReturningPlaylist(
      mutation,
      variables,
      dataKey,
    );
    return playlist != null;
  }

  static Future<UserPlaylist?> _runPlaylistMutationReturningPlaylist(
    String mutation,
    Map<String, dynamic> variables,
    String dataKey,
  ) async {
    final client = GraphQLConnection().client?.value;
    if (client == null) return null;

    try {
      final result = await client.mutate(
        MutationOptions(
          document: gql(mutation),
          variables: variables,
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
      final data = result.data?[dataKey];
      if (result.hasException || data is! Map<String, dynamic>) return null;
      return UserPlaylist.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
