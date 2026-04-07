import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import '../models/mqtt_credentials.dart';

class PreferencesManager {
  // Ключи для хранения
  static const String _keyCurrentServer = 'current_server';
  static const String _keyMqttLogin = 'mqtt_login';
  static const String _keyMqttPassword = 'mqtt_password';
  static const String _keyDevicesPrefix = 'devices_';
  static const String _keyHistoryPrefix = 'history_';
  static const String _keyApiLogin = 'api_login';
  static const String _keyApiPassword = 'api_password';
  static const String _keyApiToken = 'api_token';
  
  // ============ УПРАВЛЕНИЕ СЕРВЕРОМ ============
  
  Future<void> saveCurrentServer(String server) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrentServer, server);
  }
  
  Future<String> getCurrentServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCurrentServer) ?? 'iot-mqtt.ru';
  }
  
  // ============ MQTT УЧЕТНЫЕ ДАННЫЕ ============
  
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
  
  // ============ API УЧЕТНЫЕ ДАННЫЕ ============
  
  Future<void> saveApiCredentials(String login, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiLogin, login);
    await prefs.setString(_keyApiPassword, password);
  }
  
  Future<({String login, String password})> getApiCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final login = prefs.getString(_keyApiLogin) ?? '';
    final password = prefs.getString(_keyApiPassword) ?? '';
    return (login: login, password: password);
  }
  
  Future<void> saveApiToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiToken, token);
  }
  
  Future<String> getApiToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiToken) ?? '';
  }
  
  // ============ УСТРОЙСТВА (привязаны к серверу и логину) ============
  
  String _getDevicesKey(String server, String login) {
    return '$_keyDevicesPrefix${server}_$login';
  }
  
  Future<void> saveDevices(List<DeviceModel> devices, String server, String login) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getDevicesKey(server, login);
    final jsonList = devices.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(key, jsonList);
  }
  
  Future<List<DeviceModel>> getDevices(String server, String login) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getDevicesKey(server, login);
    final jsonList = prefs.getStringList(key) ?? [];
    
    return jsonList
        .map((json) => DeviceModel.fromJson(jsonDecode(json)))
        .toList();
  }
  
  Future<void> addDevice(DeviceModel device, String server, String login) async {
    final devices = await getDevices(server, login);
    devices.add(device);
    await saveDevices(devices, server, login);
  }
  
  Future<void> removeDevice(String mac, String server, String login) async {
    final devices = await getDevices(server, login);
    devices.removeWhere((d) => d.mac == mac);
    await saveDevices(devices, server, login);
  }
  
  Future<void> updateDevice(DeviceModel device, String server, String login) async {
    final devices = await getDevices(server, login);
    final index = devices.indexWhere((d) => d.mac == device.mac);
    if (index >= 0) {
      devices[index] = device;
      await saveDevices(devices, server, login);
    }
  }
  
  // ============ ИСТОРИЯ ДАННЫХ ============
  
  String _getHistoryKey(String server, String login, String mac, String dataType) {
    return '$_keyHistoryPrefix${server}_${login}_${mac}_$dataType';
  }
  
  Future<void> saveDataPoint(String mac, String dataType, double value, String server, String login) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getHistoryKey(server, login, mac, dataType);
    
    List<DataPoint> history = await getHistory(mac, dataType, server, login);
    
    history.add(DataPoint(
      timestamp: DateTime.now(),
      value: value,
    ));
    
    if (history.length > 1440) {
      history = history.sublist(history.length - 1440);
    }
    
    final jsonList = history.map((point) => jsonEncode(point.toJson())).toList();
    await prefs.setStringList(key, jsonList);
  }
  
  Future<List<DataPoint>> getHistory(String mac, String dataType, String server, String login) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getHistoryKey(server, login, mac, dataType);
    final jsonList = prefs.getStringList(key) ?? [];
    
    return jsonList
        .map((json) => DataPoint.fromJson(jsonDecode(json)))
        .toList();
  }
  
  // ============ ОЧИСТКА ДАННЫХ ============
  
  Future<void> clearAccountData(String server, String login) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Удаляем устройства
    final devicesKey = _getDevicesKey(server, login);
    await prefs.remove(devicesKey);
    
    // Удаляем историю
    final allKeys = prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith('$_keyHistoryPrefix${server}_$login')) {
        await prefs.remove(key);
      }
    }
  }
  
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Очищаем все ключи приложения
    final allKeys = prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith(_keyDevicesPrefix) ||
          key.startsWith(_keyHistoryPrefix) ||
          key == _keyCurrentServer ||
          key == _keyMqttLogin ||
          key == _keyMqttPassword ||
          key == _keyApiLogin ||
          key == _keyApiPassword ||
          key == _keyApiToken) {
        await prefs.remove(key);
      }
    }
  }

}