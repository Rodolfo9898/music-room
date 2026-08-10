class UserProfile {
  final int accountId;
  final String email;
  final String displayName;
  final bool googleLinked;
  final bool hasPublicPreference;
  final String publicInfo;
  final String friendsInfo;
  final String privateInfo;
  final List<int> musicPreferenceGenreIds;

  const UserProfile({
    required this.accountId,
    required this.email,
    required this.displayName,
    required this.googleLinked,
    required this.hasPublicPreference,
    required this.publicInfo,
    required this.friendsInfo,
    required this.privateInfo,
    required this.musicPreferenceGenreIds,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final rawPreferences = json['musicPreferenceGenreIds'];
    return UserProfile(
      accountId: json['accountId'] as int? ?? 0,
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      googleLinked: json['googleLinked'] == true,
      hasPublicPreference: json['hasPublicPreference'] != false,
      publicInfo: json['publicInfo'] as String? ?? '',
      friendsInfo: json['friendsInfo'] as String? ?? '',
      privateInfo: json['privateInfo'] as String? ?? '',
      musicPreferenceGenreIds: rawPreferences is List
          ? rawPreferences.whereType<int>().toList()
          : const [],
    );
  }
}
