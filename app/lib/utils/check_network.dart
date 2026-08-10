import 'package:flutter/foundation.dart';
import 'package:http/http.dart';

Future<bool> hasNetwork() async {
  if (kIsWeb) {
    return true;
  }
  while (true) {
    final result = await get(Uri.parse('https://www.google.com'));
    if (result.statusCode == 200) {
      return true;
    }
    await Future.delayed(const Duration(seconds: 1));
  }
}
