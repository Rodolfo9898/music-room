class FriendRecord {
  final int id;
  final String email;
  final String displayName;
  final String status;
  final String direction;
  const FriendRecord({
    required this.id,
    required this.email,
    required this.displayName,
    required this.status,
    required this.direction,
  });
  factory FriendRecord.fromJson(Map<String, dynamic> json) => FriendRecord(
    id: (json['id'] as num).toInt(),
    email: json['email'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    status: json['status'] as String? ?? 'PENDING',
    direction: json['direction'] as String? ?? 'OUTGOING',
  );
}
