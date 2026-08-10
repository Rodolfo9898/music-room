import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// An in-memory fake for [FlutterSecureStoragePlatform] so tests exercising
/// `SessionStorage` (which wraps `FlutterSecureStorage`) don't need a real
/// platform implementation (method channel) registered.
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  /// Installs this fake as the active [FlutterSecureStoragePlatform.instance]
  /// and clears any previously stored values. Call from `setUp`.
  static FakeSecureStoragePlatform install() {
    final fake = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = fake;
    return fake;
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return _values.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(_values);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }
}
