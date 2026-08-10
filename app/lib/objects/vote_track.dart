import 'vote_int.dart';

class VoteTrack {
  final int musicId, votes;
  final String title, artist;
  VoteTrack({
    required this.musicId,
    required this.votes,
    required this.title,
    required this.artist,
  });
  factory VoteTrack.fromJson(Map<String, dynamic> json) => VoteTrack(
    musicId: voteInt(json['music_id']),
    votes: voteInt(json['vote_count']),
    title: json['title'] as String? ?? '',
    artist: json['artist_name'] as String? ?? 'Unknown artist',
  );
}
