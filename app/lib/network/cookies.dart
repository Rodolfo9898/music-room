import '../services/client_metadata.dart';
import '../services/session_storage.dart';

Future<Map<String, String>> getHeaders({
  bool json = false,
  bool token = false,
  String? version,
}) async {
  Map<String, String> ret = {...ClientMetadata.headers};
  if (token) {
    final token = await SessionStorage.readAccessToken() ?? '';
    ret.addAll({'Access-Token': token});
  }
  if (json) {
    ret.addAll({'Content-Type': 'application/json; charset=UTF-8'});
  }
  return ret;
}
