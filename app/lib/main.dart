import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/constants.dart';
import 'config/routes.dart';
import 'state/music_player_controller.dart';
import 'services/client_metadata.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ClientMetadata.initialize();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  ThemeData _buildTheme(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF090B11),
      fontFamily: 'SF Pro Display',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFFF4F7FB),
        elevation: 0,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: const Color(0xFFF4F7FB),
        displayColor: const Color(0xFFF4F7FB),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF090B11),
        contentTextStyle: const TextStyle(color: Color(0xFFF4F7FB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF11141D),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFFF7A45), width: 1.4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final darkScheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF7A45),
          brightness: Brightness.dark,
          surface: const Color(0xFF090B11),
        );

        return ChangeNotifierProvider(
          create: (_) => MusicPlayerController(),
          child: MaterialApp.router(
            key: Constants.materialHomeKey,
            routerConfig: routes,
            debugShowCheckedModeBanner: false,
            title: 'Music room',
            theme: _buildTheme(darkScheme),
            darkTheme: _buildTheme(darkScheme),
            themeMode: ThemeMode.dark,
            builder: (context, child) => LayoutBuilder(
              builder: (context, constraints) => ColoredBox(
                color: const Color(0xFF090B11),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth >= 900
                          ? 1200
                          : constraints.maxWidth,
                    ),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
