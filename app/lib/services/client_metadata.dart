import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ClientMetadata {
  static Map<String, String> _headers = const {
    'X-Client-Platform': 'unknown',
    'X-Client-Device': 'unknown',
    'X-App-Version': 'unknown',
    'X-Device-Key': 'unknown',
  };

  static Map<String, String> get headers => Map.unmodifiable(_headers);

  static Future<void> initialize() async {
    final package = await PackageInfo.fromPlatform();
    final info = await DeviceInfoPlugin().deviceInfo;
    final data = info.data;
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    _headers = {
      'X-Client-Platform': platform,
      'X-Client-Device': _first(data, [
        'model',
        'prettyName',
        'computerName',
        'browserName',
        'name',
      ]),
      'X-App-Version': '${package.version}+${package.buildNumber}',
      'X-Device-Key': _first(data, [
        'id',
        'identifierForVendor',
        'deviceId',
        'computerName',
        'userAgent',
      ]),
    };
  }

  static String _first(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != 'null') return value;
    }
    return 'unknown';
  }
}
