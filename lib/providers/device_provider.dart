import 'dart:async';
import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../models/mqtt_credentials.dart';
import '../services/preferences_manager.dart';
import '../services/mqtt_manager.dart';

class DeviceProvider extends ChangeNotifier {
  final PreferencesManager _prefs = PreferencesManager();
  MqttManager? _mqttManager;
  Timer? _pollingTimer;
  Timer? _keepAliveTimer;
  
  final List<DeviceModel> _devices = [];
  bool _isMqttConnected = false;
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _isAppActive = true;
  
  String? _currentServer;
  String? _currentLogin;

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

    _currentServer = await _prefs.getCurrentServer();
    final credentials = await _prefs.getMqttCredentials();
    _currentLogin = credentials.login;
    
    await _loadDevices();
    _startKeepAlive();
  }

  Future<void> _loadDevices() async {
    if (_currentServer == null || _currentLogin == null || _currentLogin!.isEmpty) {
      _devices.clear();
      _isLoading = false;
      notifyListeners();
      return;
    }
    
    _isLoading = true;
    notifyListeners();

    final loadedDevices = await _prefs.getDevices(_currentServer!, _currentLogin!);
    
    debugPrint('=== LOADING DEVICES ===');
    debugPrint('Server: $_currentServer, Login: $_currentLogin');
    debugPrint('Devices count: ${loadedDevices.length}');
    
    _devices.clear();
    _devices.addAll(loadedDevices);

    _isLoading = false;
    notifyListeners();

    if (_devices.isNotEmpty && _isAppActive) {
      await _connectMqtt();
    }
  }

  Future<void> _connectMqtt() async {
    if (_currentServer == null) return;
    
    final credentials = await _prefs.getMqttCredentials();
    if (credentials.login.isEmpty || credentials.password.isEmpty) {
      return;
    }

    debugPrint('App: Connecting MQTT to $_currentServer...');

    _mqttManager = MqttManager(
      broker: _currentServer!,
      onDataReceived: _onMqttDataReceived,
      onConnectionStateChanged: (connected) {
        _isMqttConnected = connected;
        notifyListeners();
        debugPrint('App MQTT state: $connected');
      },
    );

    final connected = await _mqttManager!.connect(
      credentials.login,
      credentials.password,
      _devices,
    );

    _isMqttConnected = connected;
    notifyListeners();

    if (connected) {
      _startAppPolling();
    }
  }

  void _startAppPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_isMqttConnected && _mqttManager != null && _currentLogin != null) {
        for (final device in _devices) {
          _mqttManager!.pollDevice(_currentLogin!, device.mac);
        }
        debugPrint('App: Polling devices');
      }
    });
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isMqttConnected && _mqttManager != null) {
        _mqttManager!.ping();
      } else if (!_isMqttConnected && _devices.isNotEmpty && _isAppActive) {
        _connectMqtt();
      }
    });
  }

  void _onMqttDataReceived(String mac, String type, double value) {
    final index = _devices.indexWhere((d) => d.mac == mac);
    if (index >= 0) {
      var device = _devices[index];
      final now = DateTime.now().millisecondsSinceEpoch;
      bool changed = false;
      
      if (_currentServer != null && _currentLogin != null) {
        if (type == 'temperature' || type == 'humidity') {
          _prefs.saveDataPoint(mac, type, value, _currentServer!, _currentLogin!);
        }
      }
      
      switch (type) {
        case 'temperature':
          if (device.temperature != value) {
            device = device.copyWith(temperature: value, lastUpdate: now, isOnline: true);
            changed = true;
          }
          break;
        case 'humidity':
          if (device.humidity != value) {
            device = device.copyWith(humidity: value, lastUpdate: now, isOnline: true);
            changed = true;
          }
          break;
        case 'state':
          final newIsOn = value == 1.0;
          if (device.isOn != newIsOn) {
            device = device.copyWith(isOn: newIsOn, lastUpdate: now, isOnline: true);
            changed = true;
          }
          break;
        case 'brightness':
          final newBrightness = value.toInt();
          if (device.brightness != newBrightness) {
            device = device.copyWith(brightness: newBrightness, lastUpdate: now, isOnline: true);
            changed = true;
          }
          break;
      }
      
      if (changed && _currentServer != null && _currentLogin != null) {
        _devices[index] = device;
        _prefs.updateDevice(device, _currentServer!, _currentLogin!);
        notifyListeners();
      }
    }
  }

  void onAppPaused() {
    _isAppActive = false;
    _pollingTimer?.cancel();
    _keepAliveTimer?.cancel();
    _mqttManager?.disconnect();
    _isMqttConnected = false;
    debugPrint('App paused - MQTT disconnected');
  }

  void onAppResumed() {
    _isAppActive = true;
    if (_devices.isNotEmpty) {
      _connectMqtt();
    }
    debugPrint('App resumed - reconnecting MQTT');
  }

  Future<void> addDevice(DeviceModel device) async {
    if (_currentServer == null || _currentLogin == null) return;
    
    final existingIndex = _devices.indexWhere((d) => d.mac == device.mac);
    if (existingIndex >= 0) return;
    
    _devices.add(device);
    await _prefs.addDevice(device, _currentServer!, _currentLogin!);
    notifyListeners();
    
    if (_isAppActive && _mqttManager != null && _isMqttConnected) {
      await _mqttManager!.updateSubscriptions(_devices, _currentLogin!);
    }
  }

  Future<void> removeDevice(String mac) async {
    if (_currentServer == null || _currentLogin == null) return;
    
    _devices.removeWhere((d) => d.mac == mac);
    await _prefs.removeDevice(mac, _currentServer!, _currentLogin!);
    notifyListeners();
  }

  Future<void> refreshDevices() async {
    await _loadDevices();
    if (_isAppActive) {
      await _connectMqtt();
    }
  }

  Future<bool> checkCredentials() async {
    final credentials = await _prefs.getMqttCredentials();
    return credentials.login.isNotEmpty && credentials.password.isNotEmpty;
  }

  Future<bool> testMqttConnection() async {
    final credentials = await _prefs.getMqttCredentials();
    final server = await _prefs.getCurrentServer();
    
    if (credentials.login.isEmpty || credentials.password.isEmpty) {
      return false;
    }
    
    final completer = Completer<bool>();
    final testManager = MqttManager(
      broker: server,
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

  Future<void> reconnectMqtt() async {
    if (_isAppActive) {
      await _connectMqtt();
    }
  }

  Future<void> disconnectMqtt() async {
    await _mqttManager?.disconnect();
    _isMqttConnected = false;
    notifyListeners();
  }

  void pollDevice(String mac) {
    if (_mqttManager != null && _isMqttConnected && _currentLogin != null) {
      _mqttManager!.pollDevice(_currentLogin!, mac);
      debugPrint('Manual poll requested for device $mac');
    }
  }

  Future<MqttCredentials> getCredentials() async {
    return await _prefs.getMqttCredentials();
  }
  
  Future<void> switchAccount(String server, String login) async {
    _currentServer = server;
    _currentLogin = login;
    await _loadDevices();
    if (_isAppActive) {
      await _connectMqtt();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _keepAliveTimer?.cancel();
    _mqttManager?.disconnect();
    super.dispose();
  }
}