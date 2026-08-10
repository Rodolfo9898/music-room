import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pmr_music_room/network/web_socket.dart';
import 'package:pmr_music_room/state/music_player_controller.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

class MockGraphQLClient extends Mock implements GraphQLClient {}

class FakeQueryOptions extends Fake implements QueryOptions {}

class FakeSource extends Fake implements Source {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeQueryOptions());
    registerFallbackValue(FakeSource());
    registerFallbackValue(Duration.zero);
  });

  late MockAudioPlayer mockPlayer;
  late StreamController<PlayerState> stateController;
  late StreamController<Duration> positionController;
  late StreamController<Duration> durationController;
  late StreamController<void> completeController;

  setUp(() {
    mockPlayer = MockAudioPlayer();
    stateController = StreamController<PlayerState>.broadcast();
    positionController = StreamController<Duration>.broadcast();
    durationController = StreamController<Duration>.broadcast();
    completeController = StreamController<void>.broadcast();

    when(
      () => mockPlayer.onPlayerStateChanged,
    ).thenAnswer((_) => stateController.stream);
    when(
      () => mockPlayer.onPositionChanged,
    ).thenAnswer((_) => positionController.stream);
    when(
      () => mockPlayer.onDurationChanged,
    ).thenAnswer((_) => durationController.stream);
    when(
      () => mockPlayer.onPlayerComplete,
    ).thenAnswer((_) => completeController.stream);
    when(() => mockPlayer.stop()).thenAnswer((_) async {});
    when(() => mockPlayer.pause()).thenAnswer((_) async {});
    when(() => mockPlayer.resume()).thenAnswer((_) async {});
    when(() => mockPlayer.seek(any())).thenAnswer((_) async {});
    when(() => mockPlayer.play(any())).thenAnswer((_) async {});

    GraphQLConnection().client = null;
  });

  tearDown(() async {
    await stateController.close();
    await positionController.close();
    await durationController.close();
    await completeController.close();
    GraphQLConnection().client = null;
  });

  MusicPlayerController makeController() =>
      MusicPlayerController(audioPlayer: mockPlayer);

  void mockTracksQuery(List<Map<String, dynamic>> tracks) {
    final mockClient = MockGraphQLClient();
    GraphQLConnection().client = ValueNotifier(mockClient);
    when(() => mockClient.query(any())).thenAnswer(
      (_) async => QueryResult(
        options: QueryOptions(document: gql('query { musics { id } }')),
        source: QueryResultSource.network,
        data: {'musics': tracks},
      ),
    );
  }

  group('loadTracks', () {
    test('populates tracks and flips isLoading', () async {
      mockTracksQuery([
        {'id': 1, 'title': 'Song A'},
        {'id': 2, 'title': 'Song B'},
      ]);

      final controller = makeController();
      expect(controller.isLoading, false);
      expect(controller.tracks, isEmpty);

      final future = controller.loadTracks();
      expect(controller.isLoading, true);
      await future;

      expect(controller.isLoading, false);
      expect(controller.tracks, hasLength(2));
      expect(controller.tracks.first.title, 'Song A');
    });

    test('does not reload once tracks have already been loaded', () async {
      final mockClient = MockGraphQLClient();
      GraphQLConnection().client = ValueNotifier(mockClient);
      var callCount = 0;
      when(() => mockClient.query(any())).thenAnswer((_) async {
        callCount++;
        return QueryResult(
          options: QueryOptions(document: gql('query { musics { id } }')),
          source: QueryResultSource.network,
          data: {
            'musics': [
              {'id': 1, 'title': 'Song A'},
            ],
          },
        );
      });

      final controller = makeController();
      await controller.loadTracks();
      await controller.loadTracks();

      expect(callCount, 1);
    });
  });

  group('playTrack / playQueueTrack', () {
    test('playTrack starts playback of the selected catalog track', () async {
      mockTracksQuery([
        {'id': 1, 'title': 'Song A'},
        {'id': 2, 'title': 'Song B'},
      ]);

      final controller = makeController();
      await controller.loadTracks();

      await controller.playTrack(1, syncRoomQueue: false);

      expect(controller.currentTrack?.id, 2);
      verify(() => mockPlayer.stop()).called(1);
      verify(() => mockPlayer.play(any())).called(1);
    });

    test('playTrack ignores an out-of-range index', () async {
      mockTracksQuery([
        {'id': 1, 'title': 'Song A'},
      ]);
      final controller = makeController();
      await controller.loadTracks();

      await controller.playTrack(5, syncRoomQueue: false);

      expect(controller.currentTrack, isNull);
      verifyNever(() => mockPlayer.play(any()));
    });
  });

  group('togglePlay', () {
    test(
      'starts playback from the current index when nothing has played yet',
      () async {
        mockTracksQuery([
          {'id': 1, 'title': 'Song A'},
        ]);
        final controller = makeController();
        await controller.loadTracks();

        await controller.togglePlay();

        expect(controller.currentTrack?.id, 1);
        verify(() => mockPlayer.play(any())).called(1);
      },
    );

    test('pauses when currently playing', () async {
      mockTracksQuery([
        {'id': 1, 'title': 'Song A'},
      ]);
      final controller = makeController();
      await controller.loadTracks();
      await controller.playTrack(0, syncRoomQueue: false);

      stateController.add(PlayerState.playing);
      await Future<void>.delayed(Duration.zero);
      expect(controller.isPlaying, true);

      await controller.togglePlay();

      verify(() => mockPlayer.pause()).called(1);
    });
  });

  group('canSkipNext / canSkipPrevious', () {
    test('reflect position within the loaded catalog', () async {
      mockTracksQuery([
        {'id': 1, 'title': 'Song A'},
        {'id': 2, 'title': 'Song B'},
        {'id': 3, 'title': 'Song C'},
      ]);
      final controller = makeController();
      await controller.loadTracks();

      expect(controller.canSkipPrevious, false);
      expect(controller.canSkipNext, false);

      await controller.playTrack(1, syncRoomQueue: false);

      expect(controller.canSkipPrevious, true);
      expect(controller.canSkipNext, true);

      await controller.playTrack(2, syncRoomQueue: false);

      expect(controller.canSkipNext, false);
    });

    test('skipNext advances to the next catalog track', () async {
      mockTracksQuery([
        {'id': 1, 'title': 'Song A'},
        {'id': 2, 'title': 'Song B'},
      ]);
      final controller = makeController();
      await controller.loadTracks();
      await controller.playTrack(0, syncRoomQueue: false);

      await controller.skipNext();

      expect(controller.currentTrack?.id, 2);
    });

    test('skipPrevious does nothing at the start of the catalog', () async {
      mockTracksQuery([
        {'id': 1, 'title': 'Song A'},
        {'id': 2, 'title': 'Song B'},
      ]);
      final controller = makeController();
      await controller.loadTracks();
      await controller.playTrack(0, syncRoomQueue: false);

      await controller.skipPrevious();

      expect(controller.currentTrack?.id, 1);
      verify(() => mockPlayer.play(any())).called(1);
    });
  });
}
