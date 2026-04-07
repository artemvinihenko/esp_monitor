import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/work_manager_service.dart';
import 'services/notification_service.dart';
import 'providers/device_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация WorkManager
  await WorkManagerService.init();
  
  // Инициализация уведомлений
  await NotificationService.init();
  
  // Запрос разрешений
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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DeviceProvider(),
      lazy: false,
      child: MaterialApp(
        title: 'IOT мониторинг',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (context) => const AuthWrapper(),
          '/login': (context) => const LoginScreen(),
          '/main': (context) => const MainScreen(),
        },
        debugShowCheckedModeBanner: false,
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFuture = _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

 @override
void didChangeAppLifecycleState(AppLifecycleState state) {
  debugPrint('App lifecycle state: $state');
  final provider = Provider.of<DeviceProvider>(context, listen: false);
  
  switch (state) {
    case AppLifecycleState.resumed:
     debugPrint('App resumed');
      // Просто переподключаем MQTT, не проверяем время опроса
      provider.onAppResumed();
      // Запускаем опрос сейчас
      WorkManagerService.runNow();
      break;
    default:
      break;
  }
}


  Future<bool> _checkAuth() async {
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    final hasCredentials = await provider.checkCredentials();

    if (hasCredentials) {
      // Запускаем WorkManager для фонового опроса
      await WorkManagerService.startPolling(intervalMinutes: 15);

     // await provider.loadBackgroundData();
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