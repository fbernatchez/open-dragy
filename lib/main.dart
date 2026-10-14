import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'providers/dragy_provider.dart';
import 'screens/main_navigation_screen.dart';

import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  FlutterBluePlus.setLogLevel(LogLevel.error);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const OpenDragyApp());
}

class OpenDragyApp extends StatelessWidget {
  const OpenDragyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => DragyProvider())],
      child: Selector<DragyProvider, ThemeMode>(
        selector: (_, dragy) => dragy.themeMode,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: 'OpenDragy',
            debugShowCheckedModeBanner: false,
            themeMode: themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const MainNavigationScreen(),
          );
        },
      ),
    );
  }
}
