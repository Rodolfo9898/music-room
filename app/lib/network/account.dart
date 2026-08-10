import 'dart:convert';

import 'package:http/http.dart';

import '../config/constants.dart';
import 'cookies.dart';
import '../objects/login_information.dart';
import '../objects/account_action_result.dart';
import '../objects/token_validation_result.dart';
import '../objects/user_profile.dart';
import '../objects/friend_record.dart';
import '../objects/device_record.dart';
import '../services/session_storage.dart';

const String url = '${Constants.httpServer}/accounts';

class _ApiError {
  final String? code;
  final String? message;

  const _ApiError({this.code, this.message});
}

class AccountService {
  static Map<String, dynamic> _dataObject(Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
    final data = decoded['data'];
    return data is Map<String, dynamic> ? data : decoded;
  }

  static Future<AccountActionResult> login(
    String email,
    String password,
  ) async {
    try {
      final response = await post(
        Uri.parse('$url/login'),
        headers: await getHeaders(json: true),
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (response.statusCode == 200) {
        return AccountActionResult(
          success: true,
          message: 'Login successful',
          loginInformation: LoginInformation.fromJson(_dataObject(response)),
        );
      }

      final apiError = _extractApiError(response);

      return AccountActionResult(
        success: false,
        errorCode: apiError.code,
        message: apiError.message ?? 'Unable to login with these credentials.',
      );
    } catch (_) {
      return const AccountActionResult(
        success: false,
        message: 'Network error. Please check your internet connection.',
      );
    }
  }

  static Future<AccountActionResult> signup(
    String email,
    String displayName,
    String password,
    String confirmPassword,
  ) async {
    try {
      final response = await post(
        Uri.parse('$url/signup'),
        headers: await getHeaders(json: true),
        body: jsonEncode({
          'email': email,
          'displayName': displayName,
          'password': password,
          'confirmPassword': confirmPassword,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return const AccountActionResult(
          success: true,
          message:
              'Account created. A confirmation email has been sent — please verify your email before logging in.',
        );
      }

      final apiError = _extractApiError(response);

      return AccountActionResult(
        success: false,
        errorCode: apiError.code,
        message: apiError.message ?? 'Unable to create account right now.',
      );
    } catch (_) {
      return const AccountActionResult(
        success: false,
        message: 'Network error. Please check your internet connection.',
      );
    }
  }

  static Future<AccountActionResult> forgotPassword(String email) async {
    try {
      final response = await post(
        Uri.parse('$url/forgot-password'),
        headers: await getHeaders(json: true),
        body: jsonEncode({'email': email}),
      );
      if (response.statusCode == 200) {
        return const AccountActionResult(
          success: true,
          message:
              'If an account exists for this email, a reset link has been sent.',
        );
      }

      final apiError = _extractApiError(response);

      return AccountActionResult(
        success: false,
        errorCode: apiError.code,
        message:
            apiError.message ?? 'Unable to request a password reset right now.',
      );
    } catch (_) {
      return const AccountActionResult(
        success: false,
        message: 'Network error. Please check your internet connection.',
      );
    }
  }

  static Future<AccountActionResult> updateDisplayName(
    String displayName,
  ) async {
    try {
      final response = await patch(
        Uri.parse('$url/me'),
        headers: await getHeaders(json: true, token: true),
        body: jsonEncode({'displayName': displayName}),
      );
      if (response.statusCode == 200) {
        final body = _dataObject(response);
        return AccountActionResult(
          success: true,
          message: body['displayName'] as String? ?? displayName,
        );
      }
      final apiError = _extractApiError(response);
      return AccountActionResult(
        success: false,
        errorCode: apiError.code,
        message: apiError.message ?? 'Unable to update display name.',
      );
    } catch (_) {
      return const AccountActionResult(
        success: false,
        message: 'Network error. Please check your internet connection.',
      );
    }
  }

  static Future<UserProfile?> fetchProfile() async {
    try {
      final response = await get(
        Uri.parse('$url/me'),
        headers: await getHeaders(token: true),
      );
      if (response.statusCode != 200) return null;
      return UserProfile.fromJson(_dataObject(response));
    } catch (_) {
      return null;
    }
  }

  static Future<AccountActionResult> updateProfile({
    required String displayName,
    required String publicInfo,
    required String friendsInfo,
    required String privateInfo,
    required bool hasPublicPreference,
  }) async {
    try {
      final response = await patch(
        Uri.parse('$url/me'),
        headers: await getHeaders(json: true, token: true),
        body: jsonEncode({
          'displayName': displayName,
          'publicInfo': publicInfo,
          'friendsInfo': friendsInfo,
          'privateInfo': privateInfo,
          'hasPublicPreference': hasPublicPreference,
        }),
      );
      if (response.statusCode == 200) {
        final profile = UserProfile.fromJson(_dataObject(response));
        return AccountActionResult(success: true, message: profile.displayName);
      }
      final apiError = _extractApiError(response);
      return AccountActionResult(
        success: false,
        errorCode: apiError.code,
        message: apiError.message ?? 'Unable to update profile.',
      );
    } catch (_) {
      return const AccountActionResult(
        success: false,
        message: 'Network error. Please check your internet connection.',
      );
    }
  }

  static Future<UserProfile?> updateMusicPreferences(List<int> genreIds) async {
    try {
      final response = await patch(
        Uri.parse('$url/me/preferences'),
        headers: await getHeaders(json: true, token: true),
        body: jsonEncode({'genreIds': genreIds}),
      );
      if (response.statusCode != 200) return null;
      return UserProfile.fromJson(_dataObject(response));
    } catch (_) {
      return null;
    }
  }

  static Future<AccountActionResult> linkGoogleAccount(String idToken) async {
    try {
      final response = await post(
        Uri.parse('$url/me/google'),
        headers: await getHeaders(json: true, token: true),
        body: jsonEncode({'idToken': idToken}),
      );
      if (response.statusCode == 200) {
        return const AccountActionResult(
          success: true,
          message: 'Google account linked.',
        );
      }
      final apiError = _extractApiError(response);
      return AccountActionResult(
        success: false,
        errorCode: apiError.code,
        message: apiError.message ?? 'Unable to link Google account.',
      );
    } catch (_) {
      return const AccountActionResult(
        success: false,
        message: 'Network error. Please check your internet connection.',
      );
    }
  }

  static Future<AccountActionResult> deleteAccount() async {
    try {
      final response = await delete(
        Uri.parse('$url/me'),
        headers: await getHeaders(token: true),
      );
      if (response.statusCode == 200) {
        return const AccountActionResult(
          success: true,
          message: 'Account deleted.',
        );
      }
      final apiError = _extractApiError(response);
      return AccountActionResult(
        success: false,
        errorCode: apiError.code,
        message: apiError.message ?? 'Unable to delete account.',
      );
    } catch (_) {
      return const AccountActionResult(
        success: false,
        message: 'Network error. Please check your internet connection.',
      );
    }
  }

  static Future<TokenValidationResult> refreshToken() async {
    try {
      final refreshToken = await SessionStorage.readRefreshToken();
      final response = await post(
        Uri.parse('$url/refresh'),
        headers: await getHeaders(json: true),
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (response.statusCode == 200) {
        return TokenValidationResult(
          success: true,
          loginInformation: LoginInformation.fromJson(_dataObject(response)),
          message: 'Session refreshed',
        );
      }

      final apiError = _extractApiError(response);
      return TokenValidationResult(
        success: false,
        message:
            apiError.message ??
            'Session is no longer valid. Please login again.',
        errorCode: apiError.code,
      );
    } catch (_) {
      return const TokenValidationResult(
        success: false,
        message: 'Network error. Please check your internet connection.',
      );
    }
  }

  static Future<void> logout() async {
    try {
      await post(
        Uri.parse('$url/logout'),
        headers: await getHeaders(token: true),
      );
    } finally {
      await SessionStorage.clear();
    }
  }

  static Future<List<FriendRecord>> fetchFriends() async {
    final response = await get(
      Uri.parse('$url/me/friends'),
      headers: await getHeaders(token: true),
    );
    return _records(response, FriendRecord.fromJson);
  }

  static Future<List<FriendRecord>> requestFriend(String email) async {
    final response = await post(
      Uri.parse('$url/me/friends'),
      headers: await getHeaders(json: true, token: true),
      body: jsonEncode({'email': email}),
    );
    return _records(response, FriendRecord.fromJson);
  }

  static Future<List<FriendRecord>> acceptFriend(int id) async {
    final response = await post(
      Uri.parse('$url/me/friends/$id/accept'),
      headers: await getHeaders(token: true),
    );
    return _records(response, FriendRecord.fromJson);
  }

  static Future<List<FriendRecord>> removeFriend(int id) async {
    final response = await delete(
      Uri.parse('$url/me/friends/$id'),
      headers: await getHeaders(token: true),
    );
    return _records(response, FriendRecord.fromJson);
  }

  static Future<List<DeviceRecord>> fetchDevices() async {
    final response = await get(
      Uri.parse('$url/me/devices'),
      headers: await getHeaders(token: true),
    );
    return _records(response, DeviceRecord.fromJson);
  }

  static Future<List<DeviceRecord>> registerCurrentDevice() async {
    final headers = await getHeaders(json: true, token: true);
    final response = await post(
      Uri.parse('$url/me/devices'),
      headers: headers,
      body: jsonEncode({
        'deviceKey': headers['X-Device-Key'],
        'name': headers['X-Client-Device'],
        'platform': headers['X-Client-Platform'],
        'appVersion': headers['X-App-Version'],
      }),
    );
    return _records(response, DeviceRecord.fromJson);
  }

  static Future<List<DeviceRecord>> setDeviceControl(
    int id,
    bool canControl,
  ) async {
    final response = await patch(
      Uri.parse('$url/me/devices/$id'),
      headers: await getHeaders(json: true, token: true),
      body: jsonEncode({'canControl': canControl}),
    );
    return _records(response, DeviceRecord.fromJson);
  }

  static Future<List<DeviceRecord>> setDeviceDelegate(
    int deviceId,
    int friendId,
    bool granted,
  ) async {
    final endpoint = Uri.parse('$url/me/devices/$deviceId/delegates/$friendId');
    final response = granted
        ? await post(endpoint, headers: await getHeaders(token: true))
        : await delete(endpoint, headers: await getHeaders(token: true));
    return _records(response, DeviceRecord.fromJson);
  }

  static List<T> _records<T>(
    Response response,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (response.statusCode < 200 || response.statusCode >= 300) return [];
    final decoded = jsonDecode(response.body);
    final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
    return data is List
        ? data.whereType<Map<String, dynamic>>().map(parser).toList()
        : [];
  }

  static _ApiError _extractApiError(Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final code = decoded['error'];
        final message = decoded['message'];
        return _ApiError(
          code: code is String && code.trim().isNotEmpty ? code : null,
          message: message is String && message.trim().isNotEmpty
              ? message
              : null,
        );
      }
    } catch (_) {
      // Ignore invalid body and use fallback values.
    }
    return const _ApiError();
  }
}
