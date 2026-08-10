import 'package:flutter/foundation.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:pmr_music_room/config/constants.dart';
import '../services/client_metadata.dart';

class GraphQLConnection {
  GraphQLConnection._internal();
  static final GraphQLConnection _instance = GraphQLConnection._internal();
  factory GraphQLConnection() => _instance;

  ValueNotifier<GraphQLClient>? client;

  bool get isInitialized => client != null;

  Future<void> initialize(String token) async {
    _log('initialize() start');
    _log('WS endpoint: ${Constants.wsServer}');
    _log('Token present: ${token.isNotEmpty}');

    await initHiveForFlutter();
    _log('Hive initialized');

    final bearerToken = 'Bearer $token';
    final authHeaders = {
      'Access-Token': token,
      'Authorization': bearerToken,
      ...ClientMetadata.headers,
    };

    final wsUrl = Constants.wsServer;
    final wsLink = WebSocketLink(
      wsUrl,
      subProtocol: GraphQLProtocol.graphqlTransportWs,
      config: SocketClientConfig(
        autoReconnect: true,
        delayBetweenReconnectionAttempts: const Duration(seconds: 2),
        headers: authHeaders,
        initialPayload: () async {
          _log('Sending websocket initial payload with auth header');
          return {
            'Access-Token': token,
            'Authorization': bearerToken,
            'headers': authHeaders,
            ...ClientMetadata.headers,
          };
        },
        onConnectionLost: (code, reason) async {
          _log('WebSocket disconnected. code=$code reason=$reason');
          return const Duration(seconds: 2);
        },
      ),
    );
    _log('WebSocket subProtocol: ${GraphQLProtocol.graphqlTransportWs}');
    _log('Routing GraphQL queries, mutations and subscriptions over websocket');

    client = ValueNotifier(
      GraphQLClient(
        link: wsLink,
        cache: GraphQLCache(store: HiveStore()),
      ),
    );

    _log('GraphQL client initialized successfully');
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[GraphQLConnection] $message');
    }
  }

  Future<void> dispose() async {
    client?.dispose();
  }
}
