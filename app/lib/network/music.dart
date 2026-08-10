import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../config/constants.dart';
import '../objects/music_track.dart';
import '../objects/music_service_result.dart';
import '../objects/genre_option.dart';
import 'web_socket.dart';

const String musicUrl = '${Constants.httpServer}/musics';

class MusicService {
  static const String _musicsQuery = r'''
    query Musics {
      musics {
        id
        title
        artist_id
        genre_id
        file_path
        duration
      }
    }
  ''';

  static const String _searchMusicsQuery = r'''
    query SearchMusics($query: String!) {
      searchMusics(query: $query) {
        id
        title
        artist_id
        genre_id
        file_path
        duration
        artist_name
      }
    }
  ''';

  static Future<MusicServiceResult> fetchTracks() async {
    final graphQLClient = GraphQLConnection().client?.value;
    if (graphQLClient == null) {
      return MusicServiceResult(
        success: false,
        message: 'Socket connection is not initialized.',
        tracks: const [],
      );
    }

    try {
      final result = await graphQLClient.query(
        QueryOptions(
          document: gql(_musicsQuery),
          fetchPolicy: FetchPolicy.noCache,
        ),
      );

      if (result.hasException) {
        return MusicServiceResult(
          success: false,
          message: 'Unable to load tracks from the socket server.',
          tracks: const [],
        );
      }

      final data = result.data?['musics'];
      if (data is! List) {
        return MusicServiceResult(
          success: false,
          message: 'The music list socket response is invalid.',
          tracks: const [],
        );
      }

      final tracks = data
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList();

      return MusicServiceResult(success: true, tracks: tracks);
    } catch (_) {
      return MusicServiceResult(
        success: false,
        message: 'Socket server unavailable.',
        tracks: const [],
      );
    }
  }

  static Future<List<GenreOption>> fetchGenres() async {
    try {
      final response = await http.get(Uri.parse('$musicUrl/genres'));
      if (response.statusCode != 200) return [];
      final decoded = jsonDecode(response.body);
      final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
      if (data is! List) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(GenreOption.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<MusicServiceResult> searchTracks(String query) async {
    final graphQLClient = GraphQLConnection().client?.value;
    if (graphQLClient == null) {
      return const MusicServiceResult(
        success: false,
        message: 'Socket connection is not initialized.',
        tracks: [],
      );
    }

    try {
      final result = await graphQLClient.query(
        QueryOptions(
          document: gql(_searchMusicsQuery),
          variables: {'query': query},
          fetchPolicy: FetchPolicy.noCache,
        ),
      );

      if (result.hasException) {
        return const MusicServiceResult(
          success: false,
          message: 'Search failed.',
          tracks: [],
        );
      }

      final data = result.data?['searchMusics'];
      if (data is! List) {
        return const MusicServiceResult(success: true, tracks: []);
      }

      final tracks = data
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList();

      return MusicServiceResult(success: true, tracks: tracks);
    } catch (_) {
      return const MusicServiceResult(
        success: false,
        message: 'Search request failed.',
        tracks: [],
      );
    }
  }
}
