import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStorage {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'music_room_access_token';
  static const _refreshKey = 'music_room_refresh_token';

  static Future<String?> readAccessToken() => _storage.read(key: _accessKey);
  static Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  static Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  static Future<void> clear() => _storage.deleteAll();
}
