import 'package:flutter_test/flutter_test.dart';
import 'package:pmr_music_room/objects/vote_event.dart';

void main() {
  VoteEvent buildEvent({String? canVoteReason, bool canVote = false}) =>
      VoteEvent.fromJson({
        'id': 1,
        'owner_id': 2,
        'version': 0,
        'name': 'Test event',
        'vote_policy': 'LOCATION_TIME',
        'is_public': true,
        'can_vote': canVote,
        'can_vote_reason': canVoteReason,
        'user_vote_music_ids': [],
        'tracks': [],
        'members': [],
      });

  group('VoteEvent.canVoteReasonMessage', () {
    test('maps each known reason code to a precise message', () {
      expect(
        buildEvent(canVoteReason: 'NOT_VIEWABLE').canVoteReasonMessage,
        contains("don't have access"),
      );
      expect(
        buildEvent(canVoteReason: 'NOT_INVITED').canVoteReasonMessage,
        contains("haven't been invited"),
      );
      expect(
        buildEvent(
          canVoteReason: 'WINDOW_NOT_CONFIGURED',
        ).canVoteReasonMessage,
        contains('voting window'),
      );
      expect(
        buildEvent(canVoteReason: 'OUTSIDE_TIME_WINDOW').canVoteReasonMessage,
        contains('not currently open'),
      );
      expect(
        buildEvent(
          canVoteReason: 'LOCATION_NOT_CONFIGURED',
        ).canVoteReasonMessage,
        contains("location isn't configured"),
      );
      expect(
        buildEvent(canVoteReason: 'LOCATION_UNAVAILABLE').canVoteReasonMessage,
        contains('location could not be determined'),
      );
      expect(
        buildEvent(canVoteReason: 'OUTSIDE_RADIUS').canVoteReasonMessage,
        contains('too far'),
      );
    });

    test('falls back to a generic message for an unknown/absent reason', () {
      expect(
        buildEvent(canVoteReason: null).canVoteReasonMessage,
        contains('does not satisfy this voting license'),
      );
    });
  });

  test('fromJson parses can_vote_reason', () {
    final event = buildEvent(canVoteReason: 'OUTSIDE_RADIUS', canVote: false);
    expect(event.canVote, false);
    expect(event.canVoteReason, 'OUTSIDE_RADIUS');
  });

  group('VoteEvent.membersManageable', () {
    VoteEvent eventWith({required String votePolicy, required bool isPublic}) =>
        VoteEvent.fromJson({
          'id': 1,
          'owner_id': 2,
          'version': 0,
          'name': 'Test event',
          'vote_policy': votePolicy,
          'is_public': isPublic,
          'can_vote': false,
          'can_vote_reason': null,
          'user_vote_music_ids': [],
          'tracks': [],
          'members': [],
        });

    test('is manageable for INVITED policy regardless of visibility', () {
      expect(
        eventWith(votePolicy: 'INVITED', isPublic: true).membersManageable,
        isTrue,
      );
      expect(
        eventWith(votePolicy: 'INVITED', isPublic: false).membersManageable,
        isTrue,
      );
    });

    test('is manageable for private events regardless of vote policy', () {
      expect(
        eventWith(
          votePolicy: 'EVERYONE',
          isPublic: false,
        ).membersManageable,
        isTrue,
      );
      expect(
        eventWith(
          votePolicy: 'LOCATION_TIME',
          isPublic: false,
        ).membersManageable,
        isTrue,
      );
    });

    test('is not manageable for public events with EVERYONE/LOCATION_TIME', () {
      expect(
        eventWith(votePolicy: 'EVERYONE', isPublic: true).membersManageable,
        isFalse,
      );
      expect(
        eventWith(
          votePolicy: 'LOCATION_TIME',
          isPublic: true,
        ).membersManageable,
        isFalse,
      );
    });
  });
}
