import 'login_information.dart';

class AccountActionResult {
  final bool success;
  final String message;
  final String? errorCode;
  final LoginInformation? loginInformation;

  const AccountActionResult({
    required this.success,
    required this.message,
    this.errorCode,
    this.loginInformation,
  });

  bool get isEmailNotVerified {
    final code = errorCode?.toUpperCase() ?? '';
    return code == 'EMAIL_NOT_VERIFIED' || code == 'UNVERIFIED_EMAIL';
  }
}
