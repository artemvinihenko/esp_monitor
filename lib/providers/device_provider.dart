import 'dart:async';
import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../services/preferences_manager.dart';
import '../services/mqtt_manager.dart';

class DeviceProvider extends ChangeNotifier {
  final PreferencesManager _prefs = PreferencesManager();
  MqttManager? _mqttManager;
  Timer? _updateTimer;
  Timer? _keepAliveTimer;

  List<DeviceModel> _devices = [];
  bool _isMqttConnected = false;
  bool _isLoading = false;
  bool _isReconnecting = false;
  bool _isInitialized = false;

  List<DeviceModel> get devices => _devices;
  bool get isMqttConnected => _isMqttConnected;
  bool get isLoading => _isLoading;
  MqttManager? get mqttManager => _mqttManager;

  DeviceProvider() {
    _init();
  }

  Future<void> _init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _loadDevices();
    _startKeepAlive();
  }

  Future<void> _loadDevices() async {
    _isLoading = true;
    notifyListeners();

    // Получаем устройства из хранилища
    final loadedDevices = await _prefs.getDevices();

    print('=== LOADING DEVICES ===');
    print('Raw loaded devices count: ${loadedDevices.length}');

    // Очищаем текущий список
    _devices.clear();

    // Добавляем устройства с проверкой на дубликаты
    final uniqueDevices = <String, DeviceModel>{};
    for (final device in loadedDevices) {
      if (!uniqueDevices.containsKey(device.mac)) {
        uniqueDevices[device.mac] = device;
        print('  Adding: ${device.name} (${device.mac})');
      } else {
        print('  DUPLICATE SKIPPED: ${device.name} (${device.mac})');
      }
    }

    _devices.addAll(uniqueDevices.values);

    _isLoading = false;
    notifyListeners();

    print('Final devices count: ${_devices.length}');

    if (_devices.isNotEmpty) {
      await _connectMqtt();
    }
  }

  Future<bool> checkCredentials() async {
    final credentials = await _prefs.getMqttCredentials();
    return credentials.login.isNotEmpty && credentials.password.isNotEmpty;
  }

  Future<bool> testMqttConnection() async {
    final credentials = await _prefs.getMqttCredentials();
    if (credentials.login.isEmpty || credentials.password.isEmpty) {
      return false;
    }

    final completer = Completer<bool>();

    final testManager = MqttManager(
      onDataReceived: (mac, type, value) {},
      onConnectionStateChanged: (connected) {
        if (!completer.isCompleted) {
          completer.complete(connected);
        }
      },
    );

    try {
      final connected = await testManager.connect(credentials.login, credentials.password, []);
      if (connected) {
        await Future.delayed(const Duration(seconds: 1));
        await testManager.disconnect();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    } finally {
      await testManager.disconnect();
    }
  }

  Future<void> disconnectMqtt() async {
    await _mqttManager?.disconnect();
    _isMqttConnected = false;
    notifyListeners();
  }

  Future<void> _connectMqtt() async {
    final credentials = await _prefs.getMqttCredentials();
    if (credentials.login.isEmpty || credentials.password.isEmpty) {
      print('MQTT credentials not set');
      _isMqttConnected = false;
      notifyListeners();
      return;
    }

    print('Connecting MQTT with login: ${credentials.login}');

    _mqttManager = MqttManager(
      onDataReceived: _onMqttDataReceived,
      onConnectionStateChanged: _onMqttConnectionStateChanged,
    );

    final connected = await _mqttManager!.connect(
      credentials.login,
      credentials.password,
      _devices,
    );

    _isMqttConnected = connected;
    _isReconnecting = false;
    notifyListeners();

    if (connected) {
      print('MQTT connected, starting periodic update');
      _startPeriodicUpdate();
    } else {
      print('MQTT connection failed');
      Future.delayed(const Duration(seconds: 10), () {
        if (!_isMqttConnected && _devices.isNotEmpty) {
          _reconnectMqtt();
        }
      });
    }
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isMqttConnected && _mqttManager != null) {
        _mqttManager!.ping();
      } else if (!_isMqttConnected && _devices.isNotEmpty && !_isReconnecting) {
        _reconnectMqtt();
      }
    });
  }

  Future<void> reconnectMqtt() async {
    await _reconnectMqtt();
  }

  Future<void> _reconnectMqtt() async {
    if (_isReconnecting) {
      print('Already reconnecting, skipping...');
      return;
    }
    if (!_isMqttConnected ) {
      _isReconnecting = true;
      print('Attempting to reconnect MQTT...');

      await _mqttManager?.disconnect();
      _isMqttConnected = false;
      notifyListeners();

      await Future.delayed(const Duration(seconds: 2));

      await _connectMqtt();
    }
  }

  void _onMqttConnectionStateChanged(bool connected) {
    if (_isMqttConnected != connected) {
      _isMqttConnected = connected;
      _isReconnecting = false;
      notifyListeners();
      print('MQTT connection state changed: $connected');

      if (!connected && _devices.isNotEmpty) {
        Future.delayed(const Duration(seconds: 5), () {
          if (!_isMqttConnected) {
            _reconnectMqtt();
          }
        });
      }
    }
  }

  void _onMqttDataReceived(String mac, String type, double value) {
    print('Data received: device=$mac, type=$type, value=$value');

    final index = _devices.indexWhere((d) => d.mac == mac);
    if (index >= 0) {
      var device = _devices[index];
      final now = DateTime.now().millisecondsSinceEpoch;

      switch (type) {
        case 'temperature':
          device = device.copyWith(
            temperature: value,
            lastUpdate: now,
            isOnline: true,
          );
          print('Updated temperature for ${device.name}: $value°C');
          break;

        case 'humidity':
          device = device.copyWith(
            humidity: value,
            lastUpdate: now,
            isOnline: true,
          );
          print('Updated humidity for ${device.name}: $value%');
          break;

        case 'state':
          device = device.copyWith(
            isOn: value == 1.0,
            lastUpdate: now,
            isOnline: true,
          );
          print('Updated state for ${device.name}: ${value == 1.0 ? "ON" : "OFF"}');
          break;

        case 'brightness':
          device = device.copyWith(
            brightness: value.toInt(),
            lastUpdate: now,
            isOnline: true,
          );
          print('Updated brightness for ${device.name}: ${value.toInt()}%');
          break;

        case 'target_temperature':
          device = device.copyWith(
            targetTemperature: value,
            lastUpdate: now,
            isOnline: true,
          );
          print('Updated target temperature for ${device.name}: $value°C');
          break;

      }

      _devices[index] = device;
      _prefs.updateDevice(device);
      notifyListeners();
    } else {
      print('Device not found for MAC: $mac');
    }
  }

  void _startPeriodicUpdate() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _updateOnlineStatus();
    });
  }

  void _updateOnlineStatus() {
    final now = DateTime.now().millisecondsSinceEpoch;
    bool updated = false;

    for (int i = 0; i < _devices.length; i++) {
      final device = _devices[i];
      if (device.lastUpdate > 0 && now - device.lastUpdate > 120000) {
        if (device.isOnline) {
          _devices[i] = device.copyWith(isOnline: false);
          updated = true;
          print('Device ${device.name} is offline (no data for 120s)');
        }
      }
    }

    if (updated) {
      notifyListeners();
    }
  }

  Future<void> addDevice(DeviceModel device) async {
    print('=== ADDING DEVICE ===');
    print('Name: ${device.name}, MAC: ${device.mac}');

    // Проверяем в текущем списке
    final existingIndex = _devices.indexWhere((d) => d.mac == device.mac);
    if (existingIndex >= 0) {
      print('Device with MAC ${device.mac} already exists in memory, skipping...');
      return;
    }

    // Проверяем в хранилище
    final storedDevices = await _prefs.getDevices();
    final existsInStorage = storedDevices.any((d) => d.mac == device.mac);

    if (existsInStorage) {
      print('Device with MAC ${device.mac} already exists in storage, skipping...');
      return;
    }

    _devices.add(device);
    await _prefs.addDevice(device);

    // ВАЖНО: Уведомляем слушателей об изменении списка
    notifyListeners();
    print('Device added successfully, total devices: ${_devices.length}');

    // Обновляем подписки MQTT
    if (_mqttManager != null && _isMqttConnected) {
      final credentials = await _prefs.getMqttCredentials();
      await _mqttManager!.updateSubscriptions(_devices, credentials.login);
    }
  }

  Future<void> removeDevice(String mac) async {
    print('Removing device with MAC: $mac');
    _devices.removeWhere((d) => d.mac == mac);
    await _prefs.removeDevice(mac);
    notifyListeners();

    if (_devices.isEmpty) {
      await _mqttManager?.disconnect();
      _isMqttConnected = false;
      _isReconnecting = false;
    } else if (_mqttManager != null && _isMqttConnected) {
      final credentials = await _prefs.getMqttCredentials();
      await _mqttManager!.updateSubscriptions(_devices, credentials.login);
    }
    notifyListeners();
  }

  Future<void> refreshDevices() async {
    print('Refreshing devices...');
    _devices = await _prefs.getDevices();
    notifyListeners();
    print('Devices refreshed, count: ${_devices.length}');
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _keepAliveTimer?.cancel();
    _mqttManager?.disconnect();
    super.dispose();
  }
}