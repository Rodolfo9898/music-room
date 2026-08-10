import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../network/account.dart';
import '../network/web_socket.dart';
import '../services/session_storage.dart';
import '../utils/check_network.dart';
import 'home.dart';
import 'login.dart';

class SplashScreen extends StatefulWidget {
  static const routeName = '/';

  const SplashScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    return _SplashScreenState();
  }
}

class _SplashScreenState extends State<SplashScreen> {
  String version = '';
  String packageNumber = '';
  bool timerStarted = false;
  String _statusMessage = 'Checking your session...';

  @override
  void initState() {
    super.initState();
    _hasNetwork = hasNetwork();
  }

  late Future<bool> _hasNetwork;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: InkWell(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 7,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Padding(padding: EdgeInsets.only(top: 10.0)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      FutureBuilder(
                        future: _hasNetwork,
                        builder: ((BuildContext context, AsyncSnapshot snapshot) {
                          if (snapshot.hasData && snapshot.data != false) {
                            if (snapshot.data == true) {
                              startTimer();
                            }
                            return Column(
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 12),
                                Text(
                                  _statusMessage,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            );
                          }
                          return Text(
                            "This app needs internet connection to work.\nPlease check your connection and restart the app.",
                          );
                        }),
                      ),
                      Container(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: <Widget>[
                          const Spacer(),
                          FutureBuilder(
                            future: getVersionName(),
                            builder:
                                ((
                                  BuildContext context,
                                  AsyncSnapshot snapshot,
                                ) {
                                  return Text(
                                    'Version $version, B$packageNumber',
                                  );
                                }),
                          ),
                          const Spacer(flex: 4),
                          const Spacer(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> getVersionName() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    version = packageInfo.version;
    packageNumber = packageInfo.buildNumber;
  }

  Future<void> startTimer() async {
    if (timerStarted) {
      return;
    }
    timerStarted = true;
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = await SessionStorage.readRefreshToken();
    if (refreshToken == null) {
      if (!mounted) {
        return;
      }
      context.go(LoginScreen.routeName);
      return;
    }

    setState(() => _statusMessage = 'Refreshing your session...');

    final refreshedSession = await AccountService.refreshToken();
    final loginInformation = refreshedSession.loginInformation;
    if (!refreshedSession.success || loginInformation == null) {
      await prefs.clear();
      await SessionStorage.clear();
      if (!mounted) return;
      context.go(LoginScreen.routeName);
      return;
    }

    await SessionStorage.write(
      accessToken: loginInformation.token,
      refreshToken: loginInformation.refreshToken,
    );
    await prefs.setString(
      SharedPreferencesKeys.accountEmail,
      loginInformation.email,
    );
    await prefs.setInt(
      SharedPreferencesKeys.accountId,
      loginInformation.accountId,
    );
    await prefs.setString(
      SharedPreferencesKeys.displayName,
      loginInformation.displayName,
    );

    if (!mounted) return;
    setState(() => _statusMessage = 'Opening Music Room...');

    final graphQL = GraphQLConnection();
    debugPrint('[Splash] Starting GraphQL initialization');

    try {
      await graphQL.initialize(loginInformation.token);
      await AccountService.registerCurrentDevice();
      debugPrint('[Splash] GraphQL initialization complete');
    } on Object catch (error, stackTrace) {
      debugPrint('[Splash] GraphQL initialization failed: $error');
      debugPrint('$stackTrace');
      if (mounted) {
        setState(() {
          _statusMessage = 'Unable to initialize realtime connection.';
        });
      }
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) {
      return;
    }
    context.go(HomeScreen.routeName);
  }
}
