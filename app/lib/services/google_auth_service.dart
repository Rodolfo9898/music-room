import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart';
import 'package:pmr_music_room/config/constants.dart';
import 'package:pmr_music_room/objects/login_information.dart';
import 'package:pmr_music_room/network/cookies.dart';

class GoogleService {
  GoogleSignIn get _googleInstance => GoogleSignIn.instance;

  bool _isGoogleSignInInitialized = false;

  GoogleService() {
    _initializeGoogleSignIn();
  }

  Future<void> _initializeGoogleSignIn() async {
    String? clientId;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      clientId = const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      clientId = const String.fromEnvironment('GOOGLE_ANDROID_CLIENT_ID');
    }
    if (clientId?.isEmpty == true) clientId = null;
    const configuredServerClientId = String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
    );

    await _googleInstance.initialize(
      clientId: clientId,
      serverClientId: configuredServerClientId.isEmpty
          ? null
          : configuredServerClientId,
    );
    _isGoogleSignInInitialized = true;
  }

  /// Ensure Google Sign-In is initialized
  Future<void> _ensureGoogleSignInInitialized() async {
    if (!_isGoogleSignInInitialized) {
      await _initializeGoogleSignIn();
    }
  }

  /// Check if Google Sign-In is supported
  bool checkGoogleSignInSupport() {
    return _googleInstance.supportsAuthenticate();
  }

  /// Perform Google Sign-In and return ID token
  Future<String?> signIn() async {
    try {
      await _ensureGoogleSignInInitialized();

      final GoogleSignInAccount account = await _googleInstance.authenticate();
      final GoogleSignInAuthentication authentication = account.authentication;

      if (authentication.idToken == null) {
        throw ApiException('Failed to get ID token from Google');
      }
      return authentication.idToken;
    } on GoogleSignInException catch (e) {
      throw ApiException(e.description ?? 'Google Sign-In failed');
    } catch (e) {
      throw ApiException('An unexpected error occurred during Google Sign-In');
    }
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}

class GoogleAuthService {
  final GoogleService _googleService;

  GoogleAuthService(this._googleService);

  Future<LoginInformation?> signInWithGoogle() async {
    try {
      // 1. Get ID token from Google
      final idToken = await _googleService.signIn();

      if (idToken == null) {
        throw ApiException('Failed to get Google ID token');
      }

      // 2. Send ID token to backend
      final response = await post(
        Uri.parse('${Constants.httpServer}/accounts/login/google'),
        headers: await getHeaders(json: true),
        body: jsonEncode({'idToken': idToken}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final payload = decoded['data'] as Map<String, dynamic>? ?? decoded;
        final data = LoginInformation.fromJson(payload);
        return data;
      } else {
        return null;
      }
    } catch (error) {
      return null;
    }
  }
}
