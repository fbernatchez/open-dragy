import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'providers/dragy_provider.dart';
import 'screens/dashboard_screen.dart';
import 'services/debug_adb_bridge.dart';
import 'services/pocket_foreground_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  PocketForegroundService.ensureInitialized();
  await Hive.initFlutter();
  FlutterBluePlus.setLogLevel(LogLevel.error);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  DebugAdbBridge.install();
  runApp(const OpenDragyApp());
}

class OpenDragyApp extends StatelessWidget {
  const OpenDragyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DragyProvider()),
      ],
      child: MaterialApp(
        title: kDebugMode ? 'OpenDragy Debug' : 'OpenDragy',
        navigatorKey: DebugAdbBridge.navigatorKey,
        debugShowCheckedModeBanner: kDebugMode,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black, // True OLED black
          primaryColor: const Color(0xFFFFBF00), // Neon Amber
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFFBF00),
            secondary: Color(0xFF39FF14), // Neon Green
            surface: Color(0xFF111111),
          ),
          textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.black,
            elevation: 0,
            centerTitle: true,
          ),
          useMaterial3: true,
        ),
        home: WithForegroundTask(
          child: const DashboardScreen(),
        ),
      ),
    );
  }
}
