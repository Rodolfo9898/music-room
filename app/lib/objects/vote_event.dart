import 'vote_int.dart';
import 'vote_member.dart';
import 'vote_track.dart';

class VoteEvent {
  final int id, ownerId, version;
  final String name, votePolicy;
  final bool isPublic, canVote;
  final String? canVoteReason;
  final List<int> userVoteMusicIds;
  final List<VoteTrack> tracks;
  final List<VoteMember> members;
  VoteEvent({
    required this.id,
    required this.ownerId,
    required this.version,
    required this.name,
    required this.votePolicy,
    required this.isPublic,
    required this.canVote,
    this.canVoteReason,
    required this.userVoteMusicIds,
    required this.tracks,
    required this.members,
  });
  factory VoteEvent.fromJson(Map<String, dynamic> json) => VoteEvent(
    id: voteInt(json['id']),
    ownerId: voteInt(json['owner_id']),
    version: voteInt(json['version']),
    name: json['name'] as String? ?? 'Voting event',
    votePolicy: json['vote_policy'] as String? ?? 'EVERYONE',
    isPublic: json['is_public'] == true,
    canVote: json['can_vote'] == true,
    canVoteReason: json['can_vote_reason'] as String?,
    userVoteMusicIds: (json['user_vote_music_ids'] as List? ?? [])
        .map(voteInt)
        .toList(),
    tracks: (json['tracks'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(VoteTrack.fromJson)
        .toList(),
    members: (json['members'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(VoteMember.fromJson)
        .toList(),
  );
  // Private events gate access via an invite list regardless of vote policy,
  // so the owner must be able to manage invitees whenever the event is
  // private, in addition to the INVITED policy. Otherwise (public event with
  // a policy that has no invite mechanism), members show as a read-only list
  // of users who voted.
  bool get membersManageable => votePolicy == 'INVITED' || !isPublic;
  String get policyLabel => switch (votePolicy) {
    'INVITED' => 'Invited users can vote',
    'LOCATION_TIME' => 'Nearby users can vote during the event window',
    _ => 'Everyone with access can vote',
  };

  // Precise, per-reason explanation mirroring the server's
  // VoteEligibilityReason codes, shown instead of a generic message.
  String get canVoteReasonMessage => switch (canVoteReason) {
    'NOT_VIEWABLE' => "You don't have access to this event.",
    'NOT_INVITED' => "You haven't been invited to vote on this event.",
    'WINDOW_NOT_CONFIGURED' =>
      "This event's voting window isn't configured yet.",
    'OUTSIDE_TIME_WINDOW' =>
      'The voting window for this event is not currently open.',
    'LOCATION_NOT_CONFIGURED' => "This event's location isn't configured.",
    'LOCATION_UNAVAILABLE' => 'Your location could not be determined.',
    'OUTSIDE_RADIUS' => "You're too far from the event's location.",
    _ =>
      'Your current invitation, location, or time does not satisfy this voting license.',
  };
}
