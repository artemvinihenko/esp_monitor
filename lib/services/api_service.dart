import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_model.dart';
import 'package:flutter/foundation.dart';

class ApiService  {
   static String baseUrl = 'https://iot-mqtt.ru';
  
  static void setServer(String server) {
     if(server=='ametist-tech.com'){ 
         server='mqtt.ametist-tech.com';
       }
       baseUrl ='https://$server';
       debugPrint('Base url server: $baseUrl');
  }

 static Future<String?> getAuthToken(String login, String password) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/app/auth/'),
        headers: {
          'Authorization': password,
          'X-Request-Id': '0',
          'X-User-Id': login,
        },
      );
      
      debugPrint('Auth response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['request_token'] as String?;
        
        if (token != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('api_token', token);
          return token;
        }
      } else if (response.statusCode == 403) {
        return await _createNewToken(login, password);
      }
      
      return null;
    } catch (e) {
      debugPrint('Error getting auth token: $e');
      return null;
    }
  }
  
  static Future<String?> _createNewToken(String login, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/app/'),
        headers: {
          'Authorization': 'code',
          'X-Request-Id': password,
          'X-User-Id': login,
        },
      );
      
      debugPrint('Create token response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['request_token'] as String?;
        
        if (token != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('api_token', token);
          return token;
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('Error creating new token: $e');
      return null;
    }
  }
  
  static Future<List<Map<String, dynamic>>> getDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('api_token');
      final login = prefs.getString('api_login');
      
      if (token == null || login == null) {
        debugPrint('No token or login saved');
        return [];
      }
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/app/dev/'),
        headers: {
          'Authorization': token,
          'X-Request-Id': '0',
          'X-User-Id': login,
        },
      );
      
      debugPrint('Get devices response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final devices = data['dev'] as List<dynamic>?;
        
        if (devices != null) {
          return devices.map((d) => Map<String, dynamic>.from(d)).toList();
        }
      } else if (response.statusCode == 403) {
        final password = prefs.getString('api_password');
        if (password != null) {
          final newToken = await getAuthToken(login, password);
          if (newToken != null) {
            return await getDevices();
          }
        }
      }
      
      return [];
    } catch (e) {
      debugPrint('Error getting devices: $e');
      return [];
    }
  }
  
  // Преобразование типа устройства из API в наш формат
  static DeviceType parseDeviceType(String mem) {
    switch (mem.toUpperCase()) {
      case 'DAT':
        return DeviceType.dat;
      case 'LAMP':
        return DeviceType.lamp;
      case 'ROZ':
      case 'ROZA':
      case 'ROZV':
      case 'ROZAV':
        return DeviceType.roz;
      case 'RELE':
        return DeviceType.rele;
      case 'TERMO1':
        return DeviceType.termo1;
      case 'PU04':
      case 'PU08':
      case 'PU09':
      case 'FUTURUS':
        return DeviceType.sauna;
      case 'LED':
      case 'LED11':
        return DeviceType.led;
      default:
        return DeviceType.none;
    }
  }
  
   static Future<bool> hasSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final login = prefs.getString('api_login');
    final password = prefs.getString('api_password');
    return login != null && password != null && login.isNotEmpty && password.isNotEmpty;
  }
  
  static Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('api_token');
    await prefs.remove('api_login');
    await prefs.remove('api_password');
  }

}