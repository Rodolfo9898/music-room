import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pmr_music_room/network/music.dart';
import 'package:pmr_music_room/network/web_socket.dart';
import 'package:pmr_music_room/objects/genre_option.dart';
import 'package:pmr_music_room/objects/music_track.dart';

class MockGraphQLClient extends Mock implements GraphQLClient {}

class MockHttpClient extends Mock implements http.Client {}

class FakeQueryOptions extends Fake implements QueryOptions {}

http.Response _jsonResponse(Object data, int statusCode) {
  return http.Response(jsonEncode(data), statusCode);
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeQueryOptions());
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  group('MusicTrack.fromJson', () {
    test('applies defaults for missing optional fields', () {
      final track = MusicTrack.fromJson({'id': 1});

      expect(track.id, 1);
      expect(track.title, 'Untitled track');
      expect(track.artistId, 0);
      expect(track.genreId, 0);
      expect(track.duration, 0);
      expect(track.artistName, isNull);
    });

    test('streamUrl falls back to /musics/{id}/stream when missing', () {
      final track = MusicTrack.fromJson({'id': 42});
      expect(track.streamUrl, endsWith('/musics/42/stream'));
    });

    test('streamUrl passes through an already-absolute http(s) URL', () {
      final track = MusicTrack.fromJson({
        'id': 1,
        'streamUrl': 'https://cdn.example.com/track.mp3',
      });
      expect(track.streamUrl, 'https://cdn.example.com/track.mp3');
    });

    test('streamUrl resolves a leading-slash relative path against the server', () {
      final track = MusicTrack.fromJson({
        'id': 1,
        'streamUrl': '/static/track.mp3',
      });
      expect(track.streamUrl, endsWith('/static/track.mp3'));
      expect(track.streamUrl, isNot(startsWith('/')));
    });

    test('streamUrl resolves a bare relative path against the server', () {
      final track = MusicTrack.fromJson({
        'id': 1,
        'streamUrl': 'static/track.mp3',
      });
      expect(track.streamUrl, endsWith('/static/track.mp3'));
    });
  });

  group('GenreOption.fromJson', () {
    test('falls back to a generated name when missing', () {
      final genre = GenreOption.fromJson({'id': 5});
      expect(genre.id, 5);
      expect(genre.name, 'Genre 5');
      expect(genre.description, '');
    });

    test('maps provided name and description', () {
      final genre = GenreOption.fromJson({
        'id': 5,
        'name': 'Rock',
        'description': 'Guitar-driven music',
      });
      expect(genre.name, 'Rock');
      expect(genre.description, 'Guitar-driven music');
    });
  });

  group('MusicService.fetchTracks', () {
    tearDown(() {
      GraphQLConnection().client = null;
    });

    test('returns a failure when no GraphQL client is initialized', () async {
      GraphQLConnection().client = null;

      final result = await MusicService.fetchTracks();

      expect(result.success, false);
      expect(result.tracks, isEmpty);
    });

    test('returns parsed tracks on a successful query', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);

      when(() => mockClient.query(any())).thenAnswer(
        (_) async => QueryResult(
          options: QueryOptions(document: gql('query { musics { id } }')),
          source: QueryResultSource.network,
          data: {
            'musics': [
              {'id': 1, 'title': 'Song A'},
              {'id': 2, 'title': 'Song B'},
            ],
          },
        ),
      );

      final result = await MusicService.fetchTracks();

      expect(result.success, true);
      expect(result.tracks, hasLength(2));
      expect(result.tracks.first.title, 'Song A');
    });

    test('returns a failure when the query has an exception', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);

      when(() => mockClient.query(any())).thenAnswer(
        (_) async => QueryResult(
          options: QueryOptions(document: gql('query { musics { id } }')),
          source: QueryResultSource.network,
          exception: OperationException(
            linkException: const ServerException(originalException: 'boom'),
          ),
        ),
      );

      final result = await MusicService.fetchTracks();

      expect(result.success, false);
      expect(result.tracks, isEmpty);
    });

    test('returns a failure when the response data shape is invalid', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);

      when(() => mockClient.query(any())).thenAnswer(
        (_) async => QueryResult(
          options: QueryOptions(document: gql('query { musics { id } }')),
          source: QueryResultSource.network,
          data: {'musics': 'not-a-list'},
        ),
      );

      final result = await MusicService.fetchTracks();

      expect(result.success, false);
      expect(result.tracks, isEmpty);
    });
  });

  group('MusicService.searchTracks', () {
    tearDown(() {
      GraphQLConnection().client = null;
    });

    test('returns parsed tracks on a successful query', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);

      when(() => mockClient.query(any())).thenAnswer(
        (_) async => QueryResult(
          options: QueryOptions(document: gql('query { searchMusics(query: "") { id } }')),
          source: QueryResultSource.network,
          data: {
            'searchMusics': [
              {'id': 3, 'title': 'Found Song'},
            ],
          },
        ),
      );

      final result = await MusicService.searchTracks('found');

      expect(result.success, true);
      expect(result.tracks.single.title, 'Found Song');
    });
  });

  group('MusicService.fetchGenres', () {
    test('returns parsed genres on success', () async {
      final mockHttp = MockHttpClient();
      when(() => mockHttp.get(any())).thenAnswer(
        (_) async => _jsonResponse({
          'data': [
            {'id': 1, 'name': 'Rock'},
          ],
        }, 200),
      );

      final genres = await http.runWithClient(
        () => MusicService.fetchGenres(),
        () => mockHttp,
      );

      expect(genres, hasLength(1));
      expect(genres.first.name, 'Rock');
    });

    test('returns an empty list on failure status codes', () async {
      final mockHttp = MockHttpClient();
      when(() => mockHttp.get(any())).thenAnswer(
        (_) async => _jsonResponse({}, 500),
      );

      final genres = await http.runWithClient(
        () => MusicService.fetchGenres(),
        () => mockHttp,
      );

      expect(genres, isEmpty);
    });
  });
}
