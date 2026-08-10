import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pmr_music_room/network/playlist.dart';
import 'package:pmr_music_room/network/web_socket.dart';
import 'package:pmr_music_room/objects/user_playlist.dart';

class MockGraphQLClient extends Mock implements GraphQLClient {}

class FakeQueryOptions extends Fake implements QueryOptions {}

class FakeMutationOptions extends Fake implements MutationOptions {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeQueryOptions());
    registerFallbackValue(FakeMutationOptions());
  });

  tearDown(() {
    GraphQLConnection().client = null;
  });

  group('UserPlaylist.fromJson', () {
    test('derives musicIds from tracks when present', () {
      final playlist = UserPlaylist.fromJson({
        'id': 1,
        'name': 'Chill',
        'owner_id': 2,
        'is_public': true,
        'tracks': [
          {'music_id': 10, 'id': 10, 'title': 'A', 'duration': 100},
          {'music_id': 20, 'id': 20, 'title': 'B', 'duration': 200},
        ],
      });

      expect(playlist.musicIds, [10, 20]);
      expect(playlist.totalDuration, 300);
      expect(playlist.tracks, hasLength(2));
      expect(playlist.containsMusic(10), true);
      expect(playlist.containsMusic(99), false);
    });

    test('derives musicIds from music_ids when tracks are absent', () {
      final playlist = UserPlaylist.fromJson({
        'id': 1,
        'name': 'Chill',
        'owner_id': 2,
        'is_public': false,
        'music_ids': [5, 6, 7],
      });

      expect(playlist.musicIds, [5, 6, 7]);
      expect(playlist.tracks, isEmpty);
      expect(playlist.totalDuration, 0);
    });

    test('parses collaborator_ids and defaults can_edit to true', () {
      final playlist = UserPlaylist.fromJson({
        'id': 1,
        'name': 'Shared',
        'owner_id': 2,
        'is_public': true,
        'collaborator_ids': [3, 4],
      });

      expect(playlist.collaboratorIds, [3, 4]);
      expect(playlist.canEdit, true);
    });

    test('can_edit is false when explicitly false', () {
      final playlist = UserPlaylist.fromJson({
        'id': 1,
        'name': 'Locked',
        'owner_id': 2,
        'is_public': true,
        'can_edit': false,
      });

      expect(playlist.canEdit, false);
    });

    test('track_count falls back to musicIds.length when missing', () {
      final playlist = UserPlaylist.fromJson({
        'id': 1,
        'name': 'Chill',
        'owner_id': 2,
        'is_public': true,
        'music_ids': [1, 2, 3],
      });

      expect(playlist.trackCount, 3);
    });

    test('edit_policy defaults to EVERYONE when missing', () {
      final playlist = UserPlaylist.fromJson({
        'id': 1,
        'name': 'Chill',
        'owner_id': 2,
        'is_public': true,
      });

      expect(playlist.editPolicy, 'EVERYONE');
    });
  });

  group('PlaylistService.fetchMyPlaylists', () {
    test('returns an empty list when no client is initialized', () async {
      GraphQLConnection().client = null;
      final playlists = await PlaylistService.fetchMyPlaylists();
      expect(playlists, isEmpty);
    });

    test('returns parsed playlists on success', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);

      when(() => mockClient.query(any())).thenAnswer(
        (_) async => QueryResult(
          options: QueryOptions(document: gql('query { myPlaylists { id } }')),
          source: QueryResultSource.network,
          data: {
            'myPlaylists': [
              {'id': 1, 'name': 'A', 'owner_id': 1, 'is_public': true},
            ],
          },
        ),
      );

      final playlists = await PlaylistService.fetchMyPlaylists();

      expect(playlists, hasLength(1));
      expect(playlists.first.name, 'A');
    });

    test('returns an empty list when the query has an exception', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);

      when(() => mockClient.query(any())).thenAnswer(
        (_) async => QueryResult(
          options: QueryOptions(document: gql('query { myPlaylists { id } }')),
          source: QueryResultSource.network,
          exception: OperationException(
            linkException: const ServerException(originalException: 'boom'),
          ),
        ),
      );

      final playlists = await PlaylistService.fetchMyPlaylists();

      expect(playlists, isEmpty);
    });
  });

  group('PlaylistService.createPlaylist', () {
    test('returns the created playlist on success', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);

      when(() => mockClient.mutate(any())).thenAnswer(
        (_) async => QueryResult(
          options: MutationOptions(
            document: gql('mutation { createPlaylist { id } }'),
          ),
          source: QueryResultSource.network,
          data: {
            'createPlaylist': {
              'id': 9,
              'name': 'New',
              'owner_id': 1,
              'is_public': true,
            },
          },
        ),
      );

      final result = await PlaylistService.createPlaylist('New', true);

      expect(result.error, isNull);
      expect(result.playlist?.id, 9);
      expect(result.playlist?.name, 'New');
    });

    test('extracts the GraphQL error message on failure', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);

      when(() => mockClient.mutate(any())).thenAnswer(
        (_) async => QueryResult(
          options: MutationOptions(
            document: gql('mutation { createPlaylist { id } }'),
          ),
          source: QueryResultSource.network,
          exception: OperationException(
            graphqlErrors: [const GraphQLError(message: 'Name already taken')],
          ),
        ),
      );

      final result = await PlaylistService.createPlaylist('New', true);

      expect(result.playlist, isNull);
      expect(result.error, 'Name already taken');
    });

    test(
      'returns a connectivity error when no client is initialized',
      () async {
        GraphQLConnection().client = null;

        final result = await PlaylistService.createPlaylist('New', true);

        expect(result.playlist, isNull);
        expect(result.error, 'Could not reach the server.');
      },
    );
  });

  group('PlaylistService.addTrack / removeTrack', () {
    test('addTrack returns true when the mutation succeeds', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);

      when(() => mockClient.mutate(any())).thenAnswer(
        (_) async => QueryResult(
          options: MutationOptions(
            document: gql('mutation { addTrackToPlaylist { id } }'),
          ),
          source: QueryResultSource.network,
          data: {
            'addTrackToPlaylist': {
              'id': 1,
              'name': 'A',
              'owner_id': 1,
              'is_public': true,
            },
          },
        ),
      );

      final success = await PlaylistService.addTrack(1, 2);

      expect(success, true);
    });

    test('removeTrack returns false when the mutation fails', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);

      when(() => mockClient.mutate(any())).thenAnswer(
        (_) async => QueryResult(
          options: MutationOptions(
            document: gql('mutation { removeTrackFromPlaylist { id } }'),
          ),
          source: QueryResultSource.network,
          exception: OperationException(
            linkException: const ServerException(originalException: 'boom'),
          ),
        ),
      );

      final success = await PlaylistService.removeTrack(1, 2);

      expect(success, false);
    });
  });
}
