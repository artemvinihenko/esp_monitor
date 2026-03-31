import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'providers/device_provider.dart';
import 'screens/main_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Включаем Wakelock один раз при старте приложения
  WakelockPlus.enable();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // Глобальный ключ для доступа к провайдеру
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('App lifecycle state: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        print('App resumed - reconnecting MQTT');
        // Получаем доступ к провайдеру через контекст navigator
        _reconnectMqttThroughContext();
        break;

      case AppLifecycleState.paused:
        print('App paused - disabling wakelock');
        // WakelockPlus.disable(); // Опционально
        break;

      default:
        break;
    }
  }

  // Метод для переподключения MQTT через контекст
  void _reconnectMqttThroughContext() {
    // Небольшая задержка, чтобы UI успел восстановиться
    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        // Пытаемся получить контекст через navigatorKey
        final context = navigatorKey.currentContext;
        if (context != null) {
          final provider = Provider.of<DeviceProvider>(context, listen: false);
          provider.reconnectMqtt();
          print('MQTT reconnect triggered successfully');
        } else {
          print('Context not available for MQTT reconnect');
        }
      } catch (e) {
        print('Error reconnecting MQTT: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DeviceProvider(),
      child: MaterialApp(
        title: 'IOT Monitor',
        navigatorKey: navigatorKey, // Добавляем navigatorKey
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}