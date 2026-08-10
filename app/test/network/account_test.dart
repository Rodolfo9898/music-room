import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:pmr_music_room/network/account.dart';
import 'package:pmr_music_room/objects/account_action_result.dart';
import 'package:pmr_music_room/objects/device_record.dart';
import 'package:pmr_music_room/objects/friend_record.dart';
import 'package:pmr_music_room/objects/token_validation_result.dart';
import 'package:pmr_music_room/objects/user_profile.dart';
import 'package:pmr_music_room/services/session_storage.dart';

import '../helpers/fake_secure_storage_platform.dart';

class MockHttpClient extends Mock implements http.Client {}

http.Response _jsonResponse(Map<String, dynamic> data, int statusCode) {
  return http.Response(jsonEncode(data), statusCode);
}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
  });

  late MockHttpClient mockClient;

  setUp(() {
    mockClient = MockHttpClient();
    FakeSecureStoragePlatform.install();
  });

  Future<T> withMockClient<T>(Future<T> Function() body) {
    return http.runWithClient(body, () => mockClient);
  }

  group('model parsing', () {
    test('UserProfile.fromJson applies defaults for missing fields', () {
      final profile = UserProfile.fromJson({'accountId': 7});

      expect(profile.accountId, 7);
      expect(profile.email, '');
      expect(profile.displayName, '');
      expect(profile.googleLinked, false);
      expect(profile.hasPublicPreference, true);
      expect(profile.publicInfo, '');
      expect(profile.friendsInfo, '');
      expect(profile.privateInfo, '');
      expect(profile.musicPreferenceGenreIds, isEmpty);
    });

    test(
      'UserProfile.fromJson preserves privacy tiers and filters non-int preferences',
      () {
        final profile = UserProfile.fromJson({
          'accountId': 7,
          'email': 'listener@example.com',
          'displayName': 'Listener',
          'publicInfo': 'public',
          'friendsInfo': 'friends',
          'privateInfo': 'private',
          'musicPreferenceGenreIds': [1, 'bad', 3],
        });

        expect(profile.friendsInfo, 'friends');
        expect(profile.privateInfo, 'private');
        expect(profile.musicPreferenceGenreIds, [1, 3]);
      },
    );

    test('UserProfile.fromJson respects hasPublicPreference == false', () {
      final profile = UserProfile.fromJson({
        'accountId': 1,
        'hasPublicPreference': false,
      });
      expect(profile.hasPublicPreference, false);
    });

    test('FriendRecord.fromJson maps fields with defaults', () {
      final friend = FriendRecord.fromJson({
        'id': 3,
        'email': 'friend@example.com',
      });

      expect(friend.id, 3);
      expect(friend.email, 'friend@example.com');
      expect(friend.displayName, '');
      expect(friend.status, 'PENDING');
      expect(friend.direction, 'OUTGOING');
    });

    test('DeviceRecord.fromJson parses delegate_ids CSV and can_control', () {
      final device = DeviceRecord.fromJson({
        'id': 9,
        'name': 'Pixel',
        'platform': 'android',
        'app_version': '1.2.3',
        'can_control': 1,
        'delegate_ids': '1,2,3',
      });

      expect(device.id, 9);
      expect(device.canControl, true);
      expect(device.delegateIds, {1, 2, 3});
    });

    test('DeviceRecord.fromJson handles empty delegate_ids gracefully', () {
      final device = DeviceRecord.fromJson({
        'id': 1,
        'delegate_ids': '',
      });

      expect(device.delegateIds, isEmpty);
    });

    test('DeviceRecord.fromJson can_control accepts boolean true', () {
      final device = DeviceRecord.fromJson({'id': 1, 'can_control': true});
      expect(device.canControl, true);
    });

    test('DeviceRecord.fromJson can_control defaults to false', () {
      final device = DeviceRecord.fromJson({'id': 1});
      expect(device.canControl, false);
    });
  });

  group('isEmailNotVerified', () {
    test('AccountActionResult recognizes both accepted error codes', () {
      const a = AccountActionResult(
        success: false,
        message: 'x',
        errorCode: 'email_not_verified',
      );
      const b = AccountActionResult(
        success: false,
        message: 'x',
        errorCode: 'UNVERIFIED_EMAIL',
      );
      const c = AccountActionResult(
        success: false,
        message: 'x',
        errorCode: 'SOMETHING_ELSE',
      );
      const d = AccountActionResult(success: false, message: 'x');

      expect(a.isEmailNotVerified, true);
      expect(b.isEmailNotVerified, true);
      expect(c.isEmailNotVerified, false);
      expect(d.isEmailNotVerified, false);
    });

    test('TokenValidationResult recognizes both accepted error codes', () {
      const a = TokenValidationResult(
        success: false,
        message: 'x',
        errorCode: 'Email_Not_Verified',
      );
      const b = TokenValidationResult(success: false, message: 'x');

      expect(a.isEmailNotVerified, true);
      expect(b.isEmailNotVerified, false);
    });
  });

  group('AccountService.login', () {
    test('returns success with login information on HTTP 200', () async {
      when(
        () => mockClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')),
      ).thenAnswer(
        (_) async => _jsonResponse({
          'data': {
            'accountId': 1,
            'email': 'user@example.com',
            'token': 'tok',
            'refreshToken': 'refresh',
            'displayName': 'User',
          },
        }, 200),
      );

      final result = await withMockClient(
        () => AccountService.login('user@example.com', 'password'),
      );

      expect(result.success, true);
      expect(result.loginInformation?.accountId, 1);
      expect(result.loginInformation?.token, 'tok');
    });

    test('returns failure with server-provided error message/code', () async {
      when(
        () => mockClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')),
      ).thenAnswer(
        (_) async => _jsonResponse({
          'error': 'EMAIL_NOT_VERIFIED',
          'message': 'Please verify your email first.',
        }, 401),
      );

      final result = await withMockClient(
        () => AccountService.login('user@example.com', 'wrong'),
      );

      expect(result.success, false);
      expect(result.errorCode, 'EMAIL_NOT_VERIFIED');
      expect(result.isEmailNotVerified, true);
      expect(result.message, 'Please verify your email first.');
    });

    test('returns a network-error message when the request throws', () async {
      when(
        () => mockClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')),
      ).thenThrow(Exception('boom'));

      final result = await withMockClient(
        () => AccountService.login('user@example.com', 'password'),
      );

      expect(result.success, false);
      expect(result.message, contains('Network error'));
    });

    test('falls back to a generic message when the body has no message', () async {
      when(
        () => mockClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')),
      ).thenAnswer((_) async => _jsonResponse({}, 400));

      final result = await withMockClient(
        () => AccountService.login('user@example.com', 'password'),
      );

      expect(result.success, false);
      expect(result.errorCode, isNull);
      expect(result.message, 'Unable to login with these credentials.');
    });
  });

  group('AccountService.signup', () {
    test('returns success message on HTTP 200/201', () async {
      when(
        () => mockClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')),
      ).thenAnswer((_) async => _jsonResponse({}, 201));

      final result = await withMockClient(
        () => AccountService.signup(
          'user@example.com',
          'User',
          'password',
          'password',
        ),
      );

      expect(result.success, true);
      expect(result.message, contains('confirmation email'));
    });

    test('returns failure with server error on non-2xx', () async {
      when(
        () => mockClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')),
      ).thenAnswer(
        (_) async => _jsonResponse({'message': 'Email already used.'}, 409),
      );

      final result = await withMockClient(
        () => AccountService.signup(
          'user@example.com',
          'User',
          'password',
          'password',
        ),
      );

      expect(result.success, false);
      expect(result.message, 'Email already used.');
    });
  });

  group('AccountService.fetchProfile', () {
    test('returns a parsed profile on success', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => _jsonResponse({
          'data': {'accountId': 5, 'displayName': 'Someone'},
        }, 200),
      );

      final profile = await withMockClient(() => AccountService.fetchProfile());

      expect(profile, isNotNull);
      expect(profile!.accountId, 5);
      expect(profile.displayName, 'Someone');
    });

    test('returns null on non-200 response', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => _jsonResponse({}, 500));

      final profile = await withMockClient(() => AccountService.fetchProfile());

      expect(profile, isNull);
    });

    test('returns null when the request throws', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenThrow(Exception('boom'));

      final profile = await withMockClient(() => AccountService.fetchProfile());

      expect(profile, isNull);
    });
  });

  group('AccountService.updateDisplayName', () {
    test('returns success with updated display name', () async {
      when(
        () => mockClient.patch(any(), headers: any(named: 'headers'), body: any(named: 'body')),
      ).thenAnswer(
        (_) async => _jsonResponse({
          'data': {'displayName': 'New Name'},
        }, 200),
      );

      final result = await withMockClient(
        () => AccountService.updateDisplayName('New Name'),
      );

      expect(result.success, true);
      expect(result.message, 'New Name');
    });
  });

  group('AccountService.refreshToken', () {
    test('returns success with refreshed login information', () async {
      when(
        () => mockClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')),
      ).thenAnswer(
        (_) async => _jsonResponse({
          'data': {
            'accountId': 1,
            'email': 'user@example.com',
            'token': 'new-tok',
            'refreshToken': 'new-refresh',
            'displayName': 'User',
          },
        }, 200),
      );

      final result = await withMockClient(() => AccountService.refreshToken());

      expect(result.success, true);
      expect(result.loginInformation?.token, 'new-tok');
    });

    test('returns failure when the session is no longer valid', () async {
      when(
        () => mockClient.post(any(), headers: any(named: 'headers'), body: any(named: 'body')),
      ).thenAnswer((_) async => _jsonResponse({}, 401));

      final result = await withMockClient(() => AccountService.refreshToken());

      expect(result.success, false);
      expect(result.message, contains('Session is no longer valid'));
    });
  });

  group('AccountService.logout', () {
    test('clears the session even if the request throws', () async {
      when(
        () => mockClient.post(any(), headers: any(named: 'headers')),
      ).thenThrow(Exception('boom'));

      // SessionStorage.clear() runs in a `finally` block, but the original
      // exception still propagates (no catch) — verify both.
      await withMockClient(() async {
        await SessionStorage.write(
          accessToken: 'access',
          refreshToken: 'refresh',
        );
        await expectLater(() => AccountService.logout(), throwsException);
        expect(await SessionStorage.readAccessToken(), isNull);
        expect(await SessionStorage.readRefreshToken(), isNull);
      });
    });
  });

  group('AccountService friends/devices', () {
    test('fetchFriends parses the returned list', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => _jsonResponse({
          'data': [
            {
              'id': 1,
              'email': 'a@example.com',
              'display_name': 'A',
              'status': 'ACCEPTED',
              'direction': 'INCOMING',
            },
          ],
        }, 200),
      );

      final friends = await withMockClient(() => AccountService.fetchFriends());

      expect(friends, hasLength(1));
      expect(friends.first.email, 'a@example.com');
      expect(friends.first.status, 'ACCEPTED');
    });

    test('fetchFriends returns an empty list on failure status codes', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer((_) async => _jsonResponse({}, 403));

      final friends = await withMockClient(() => AccountService.fetchFriends());

      expect(friends, isEmpty);
    });

    test('fetchDevices parses the returned list', () async {
      when(
        () => mockClient.get(any(), headers: any(named: 'headers')),
      ).thenAnswer(
        (_) async => _jsonResponse({
          'data': [
            {
              'id': 2,
              'name': 'Phone',
              'platform': 'ios',
              'app_version': '2.0',
              'can_control': true,
              'delegate_ids': '4,5',
            },
          ],
        }, 200),
      );

      final devices = await withMockClient(() => AccountService.fetchDevices());

      expect(devices, hasLength(1));
      expect(devices.first.name, 'Phone');
      expect(devices.first.delegateIds, {4, 5});
    });
  });
}
