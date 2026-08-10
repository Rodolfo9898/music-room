import 'package:flutter/widgets.dart';

const String server = String.fromEnvironment(
  'MUSIC_ROOM_SERVER',
  defaultValue: 'localhost:8080',
);

class Constants {
  static const String httpServer = 'http://$server';
  static const String wsServer = 'ws://$server/subscriptions';

  static GlobalKey materialHomeKey = GlobalKey();
}

class SharedPreferencesKeys {
  static const String loginToken = 'notificationToken';
  static const String accountEmail = 'accountEmail';
  static const String accountId = 'accountId';
  static const String displayName = 'displayName';
}
