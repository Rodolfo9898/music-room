class LoginInformation {
  int accountId;
  String email;
  String token;
  String refreshToken;
  String displayName;

  LoginInformation.fromJson(Map<String, dynamic> json)
    : accountId = json['accountId'],
      token = json['token'],
      refreshToken = json['refreshToken'] as String? ?? '',
      displayName = json['displayName'],
      email = json['email'];
}
