import 'package:flutter_test/flutter_test.dart';
import 'package:pmr_music_room/objects/login_information.dart';

void main() {
  group('LoginInformation.fromJson', () {
    test('maps all fields from a complete response', () {
      final info = LoginInformation.fromJson({
        'accountId': 42,
        'email': 'user@example.com',
        'token': 'access-token-value',
        'refreshToken': 'refresh-token-value',
        'displayName': 'Jane Doe',
      });

      expect(info.accountId, 42);
      expect(info.email, 'user@example.com');
      expect(info.token, 'access-token-value');
      expect(info.refreshToken, 'refresh-token-value');
      expect(info.displayName, 'Jane Doe');
    });

    test('defaults refreshToken to an empty string when missing', () {
      final info = LoginInformation.fromJson({
        'accountId': 1,
        'email': 'user@example.com',
        'token': 'access-token-value',
        'displayName': 'Jane Doe',
      });

      expect(info.refreshToken, '');
    });
  });
}
