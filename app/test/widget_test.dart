import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmr_music_room/objects/user_profile.dart';
import 'package:pmr_music_room/views/track_vote.dart';

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
    await tester.pumpWidget(const MaterialApp(home: TrackVoteScreen()));

    expect(find.text('Realtime connection unavailable'), findsOneWidget);
  });
}
