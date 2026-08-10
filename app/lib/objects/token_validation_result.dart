import 'login_information.dart';

class TokenValidationResult {
  final bool success;
  final LoginInformation? loginInformation;
  final String message;
  final String? errorCode;

  const TokenValidationResult({
    required this.success,
    this.loginInformation,
    required this.message,
    this.errorCode,
  });

  bool get isEmailNotVerified {
    final code = errorCode?.toUpperCase() ?? '';
    return code == 'EMAIL_NOT_VERIFIED' || code == 'UNVERIFIED_EMAIL';
  }
}
