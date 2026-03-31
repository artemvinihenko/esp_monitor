import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../models/mqtt_credentials.dart';

class PreferencesManager {
  static const String _keyDevices = 'devices';
  static const String _keyMqttLogin = 'mqtt_login';
  static const String _keyMqttPassword = 'mqtt_password';
  static const String _keyTokens = 'device_tokens';

  Future<void> saveDevices(List<DeviceModel> devices) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = devices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_keyDevices, jsonList);
  }

  Future<List<DeviceModel>> getDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_keyDevices) ?? [];

    return jsonList
        .map((json) => DeviceModel.fromJson(jsonDecode(json)))
        .toList();
  }

  Future<void> addDevice(DeviceModel device) async {
    final devices = await getDevices();

    // Проверяем на дубликат по MAC
    final exists = devices.any((d) => d.mac == device.mac);
    if (exists) {
      print('Device with MAC ${device.mac} already exists in storage, not adding');
      return;
    }

    devices.add(device);
    await saveDevices(devices);
    print('Device saved to storage: ${device.name} (${device.mac})');
  }

  Future<void> removeDevice(String mac) async {
    final devices = await getDevices();
    devices.removeWhere((d) => d.mac == mac);
    await saveDevices(devices);
  }

  Future<void> updateDevice(DeviceModel device) async {
    final devices = await getDevices();
    final index = devices.indexWhere((d) => d.mac == device.mac);
    if (index >= 0) {
      devices[index] = device;
      await saveDevices(devices);
    }
  }

  Future<void> saveMqttCredentials(String login, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMqttLogin, login);
    await prefs.setString(_keyMqttPassword, password);
  }

  Future<MqttCredentials> getMqttCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final login = prefs.getString(_keyMqttLogin) ?? '';
    final password = prefs.getString(_keyMqttPassword) ?? '';
    return MqttCredentials(login: login, password: password);
  }

  Future<void> saveDeviceToken(String mac, String token) async {
    final prefs = await SharedPreferences.getInstance();
    final tokens = _getTokensMap(prefs);
    tokens[mac] = token;
    await prefs.setString(_keyTokens, jsonEncode(tokens));
  }

  Future<String?> getDeviceToken(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    final tokens = _getTokensMap(prefs);
    return tokens[mac];
  }

  Map<String, String> _getTokensMap(SharedPreferences prefs) {
    final tokensJson = prefs.getString(_keyTokens);
    if (tokensJson == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(tokensJson));
    } catch (e) {
      return {};
    }
  }

}