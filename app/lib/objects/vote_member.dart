import 'vote_int.dart';

class VoteMember {
  final int id;
  final String email, displayName;
  VoteMember({required this.id, required this.email, required this.displayName});
  factory VoteMember.fromJson(Map<String, dynamic> json) => VoteMember(
    id: voteInt(json['id']),
    email: json['email'] as String? ?? '',
    displayName: json['display_name'] as String? ?? 'Unknown user',
  );
}
