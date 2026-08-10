import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pmr_music_room/objects/user_profile.dart';
import 'package:pmr_music_room/state/music_player_controller.dart';
import 'package:pmr_music_room/views/track_vote.dart';
import 'package:provider/provider.dart';

class MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  test('profile model preserves privacy tiers and preferences', () {
    final profile = UserProfile.fromJson({
      'accountId': 7,
      'email': 'listener@example.com',
      'displayName': 'Listener',
      'publicInfo': 'public',
      'friendsInfo': 'friends',
      'privateInfo': 'private',
      'musicPreferenceGenreIds': [1, 3],
    });

    expect(profile.accountId, 7);
    expect(profile.friendsInfo, 'friends');
    expect(profile.privateInfo, 'private');
    expect(profile.musicPreferenceGenreIds, [1, 3]);
  });

  testWidgets('track vote has a safe disconnected state', (tester) async {
    final mockPlayer = MockAudioPlayer();
    when(
      () => mockPlayer.onPlayerStateChanged,
    ).thenAnswer((_) => const Stream<PlayerState>.empty());
    when(
      () => mockPlayer.onPositionChanged,
    ).thenAnswer((_) => const Stream<Duration>.empty());
    when(
      () => mockPlayer.onDurationChanged,
    ).thenAnswer((_) => const Stream<Duration>.empty());
    when(
      () => mockPlayer.onPlayerComplete,
    ).thenAnswer((_) => const Stream<void>.empty());
    when(() => mockPlayer.dispose()).thenAnswer((_) async {});

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MusicPlayerController(audioPlayer: mockPlayer),
        child: const MaterialApp(home: TrackVoteScreen()),
      ),
    );

    expect(find.text('Realtime connection unavailable'), findsOneWidget);
  });
}
