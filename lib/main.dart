import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/work_manager_service.dart';
import 'providers/device_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await WorkManagerService.init();
  
  await _requestPermissions();
  
  WakelockPlus.enable();
  runApp(const MyApp());
}

Future<void> _requestPermissions() async {
  final List<Permission> permissions = [];

  if (Platform.isAndroid) {
    permissions.add(Permission.camera);
    permissions.add(Permission.notification);
    permissions.add(Permission.nearbyWifiDevices);
    permissions.add(Permission.location);
    permissions.add(Permission.ignoreBatteryOptimizations);
  }

  if (permissions.isNotEmpty) {
    await permissions.request();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Аметист тема (черно-фиолетовая)
  static final ThemeData _amethystTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: Colors.deepPurple,
    primarySwatch: Colors.deepPurple,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.black,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
    ),
    cardTheme: CardThemeData(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.deepPurple.withOpacity(0.8),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.deepPurple.shade400),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.deepPurple.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white70),
      bodyMedium: TextStyle(color: Colors.white70),
      titleLarge: TextStyle(color: Colors.white),
      titleMedium: TextStyle(color: Colors.white),
    ),
  );

  // Темная тема
  static final ThemeData _darkTheme = ThemeData(
    brightness: Brightness.dark,
    primarySwatch: Colors.blue,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.grey.shade900,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Color.fromARGB(150, 71, 28, 145),
      foregroundColor: Colors.white,
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );

  // Светлая тема
  static final ThemeData _lightTheme = ThemeData(
    brightness: Brightness.light,
    primarySwatch: Colors.blue,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.grey.shade50,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
    ),
    cardTheme: const CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );

  static ThemeData _getThemeData(ThemeProvider provider) {
    if (provider.isAmethyst) {
      return _amethystTheme;
    } else if (provider.isDarkMode) {
      return _darkTheme;
    } else {
      return _lightTheme;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'IOT мониторинг',
            theme: _getThemeData(themeProvider),
            darkTheme: _getThemeData(themeProvider),
            themeMode: themeProvider.themeMode,
            initialRoute: '/',
            routes: {
              '/': (context) => const AuthWrapper(),
              '/login': (context) => const LoginScreen(),
              '/main': (context) => const MainScreen(),
            },
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  Future<bool>? _checkFuture;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('App lifecycle state: $state');
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    
    switch (state) {
      case AppLifecycleState.resumed:
        print('App resumed');
        provider.onAppResumed();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFuture = _checkAuth();
  }

  Future<bool> _checkAuth() async {
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    final hasCredentials = await provider.checkCredentials();

    if (hasCredentials) {
      await WorkManagerService.startPolling(intervalMinutes: 15);
      return await provider.testMqttConnection();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final isAuthenticated = snapshot.data ?? false;

        if (isAuthenticated) {
          return const MainScreen();
        } else {
          WorkManagerService.stopPolling();
          return const LoginScreen();
        }
      },
    );
  }
}