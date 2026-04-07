import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'mqtt_manager.dart';
import 'notification_service.dart';
import '../models/device_model.dart';
import 'package:flutter/foundation.dart';

const String mqttPollTask = "mqttPollTask";

Future<void> _logToFile(String message) async {
  try {
    final appDir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${appDir.path}/mqtt_logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    
    final today = DateTime.now().toString().substring(0, 10);
    final logFile = File('${logDir.path}/workmanager_$today.log');
    final timestamp = DateTime.now().toString().substring(0, 19);
    await logFile.writeAsString('[$timestamp] $message\n', mode: FileMode.append);
  } catch (e) {
    debugPrint('Log error: $e');
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  log('callbackDispatcher called');
  Workmanager().executeTask((task, inputData) async {
    await _logToFile('Task started: $task');
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    
    if (task == mqttPollTask) {
      await _performPolling(prefs);
      // Сохраняем время последнего успешного опроса
      await prefs.setInt('last_poll_timestamp', DateTime.now().millisecondsSinceEpoch);
    }
    
    await _logToFile("Task finished: $task");
    return Future.value(true);
  });
}

Future<void> _performPolling(SharedPreferences prefs) async {
  await _logToFile('Starting MQTT polling...');
  
  final login = prefs.getString('mqtt_login') ?? '';
  final password = prefs.getString('mqtt_password') ?? '';
  
  if (login.isEmpty || password.isEmpty) {
    await _logToFile('No credentials, skipping');
    return;
  }
  
  final devicesJson = prefs.getStringList('devices') ?? [];
  final devices = devicesJson
      .map((json) => DeviceModel.fromJson(jsonDecode(json)))
      .toList();
  
  if (devices.isEmpty) {
    await _logToFile('No devices, skipping');
    return;
  }
  
  await NotificationService.init();
  
  bool hasError = false;
  
  final mqttManager = MqttManager(
    onDataReceived: (mac, type, value) {
      _saveDataToPrefs(mac, type, value);
      _updateNotification(prefs, mac, type, value);
    },
    onConnectionStateChanged: (connected) {
      _logToFile('MQTT state: $connected');
    },
  );
  
  await _logToFile('Connecting to MQTT...');
  
  try {
    final connected = await mqttManager.connect(login, password, devices);
    await _logToFile('Connected: $connected');
    
    if (connected) {
      for (final device in devices) {
        mqttManager.pollDevice(login, device.mac);
        await _logToFile('Polled device: ${device.mac}');
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      await Future.delayed(const Duration(seconds: 5));
      await mqttManager.disconnect();
      await _logToFile('Disconnected');
    } else {
      hasError = true;
    }
  } catch (e) {
    await _logToFile('Polling error: $e');
    hasError = true;
  }
  
  if (!hasError) {
    await prefs.setInt('last_successful_poll', DateTime.now().millisecondsSinceEpoch);
  }
  
  await _logToFile('Polling completed');
}

void _saveDataToPrefs(String mac, String type, double value) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = 'last_${mac}_$type';
    await prefs.setDouble(key, value);
    await prefs.setInt('last_update_${mac}_$type', DateTime.now().millisecondsSinceEpoch);
    await _logToFile('Saved: $key = $value');
  } catch (e) {
    await _logToFile('Error saving: $e');
  }
}

Future<void> _updateNotification(SharedPreferences prefs, String mac, String type, double value) async {
  try {
    final selectedDeviceMac = prefs.getString('notification_device_mac') ?? '';
    final selectedDeviceType = prefs.getString('notification_device_type') ?? 'temperature';
    
    if (mac == selectedDeviceMac && type == selectedDeviceType) {
      final devicesJson = prefs.getStringList('devices') ?? [];
      final devices = devicesJson
          .map((json) => DeviceModel.fromJson(jsonDecode(json)))
          .toList();
      
      final device = devices.firstWhere(
        (d) => d.mac == mac,
        orElse: () => DeviceModel(
          id: '', name: 'Неизвестно', mac: '', type: DeviceType.dat, ip: '', login: '',
        ),
      );
      
      String displayValue;
      String unit;
      
      if (type == 'temperature') {
        displayValue = value.toStringAsFixed(1);
        unit = '°C';
      } else if (type == 'humidity') {
        displayValue = value.toStringAsFixed(1);
        unit = '%';
      } else if (type == 'state') {
        displayValue = value == 1.0 ? 'ON' : 'OFF';
        unit = '';
      } else {
        displayValue = value.toString();
        unit = '';
      }
      
      await NotificationService.updateNotification(
        deviceName: device.name,
        value: displayValue,
        unit: unit,
        timestamp: DateTime.now(),
      );
      
      await _logToFile('Notification updated: ${device.name}: $displayValue$unit');
    }
  } catch (e) {
    await _logToFile('Notification update error: $e');
  }
}

class WorkManagerService {
  static bool _initialized = false;
  
  static Future<void> init() async {
    if (_initialized) return;
    
    await _logToFile('Initializing WorkManager...');
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );
    _initialized = true;
    await _logToFile('WorkManager initialized');
    
    await NotificationService.init();
  }
  
 static Future<void> startPolling({int intervalMinutes = 15}) async {
  await init();
  
  await _logToFile('Starting polling with interval: $intervalMinutes minutes');
  
  // Отменяем все существующие задачи
  await Workmanager().cancelAll();
  
  // Регистрируем новую периодическую задачу
  await Workmanager().registerPeriodicTask(
    mqttPollTask,
    mqttPollTask,
    frequency: Duration(minutes: intervalMinutes),
    initialDelay: const Duration(seconds: 5),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
  
  await _logToFile('Registered periodic task');
  
  // Запускаем первый опрос сразу
  await runNow();
}
  
  static Future<void> stopPolling() async {
    await _logToFile('Stopping polling');
    await Workmanager().cancelAll();
    await NotificationService.cancelNotification();
  }
  
  static Future<void> setPollingInterval(int minutes) async {
    await _logToFile('Setting polling interval to $minutes minutes');
    await startPolling(intervalMinutes: minutes);
  }
  
  static Future<void> runNow() async {
    await init();
    await _logToFile('Triggering one-time polling');
    
    await Workmanager().registerOneOffTask(
      mqttPollTask,
      mqttPollTask,
      initialDelay: const Duration(seconds: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
  
  static Future<bool> isScheduled() async {
    return await Workmanager().isScheduledByUniqueName(mqttPollTask);
  }
  
  static Future<int> getLastPollTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('last_poll_timestamp') ?? 0;
  }
}