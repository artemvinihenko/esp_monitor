import 'dart:async';
import 'package:flutter/material.dart';
import 'package:esp_smartconfig/esp_smartconfig.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../models/device_model.dart';
import '../services/preferences_manager.dart';
import 'success_screen.dart';

class SmartConfigScreen extends StatefulWidget {
  const SmartConfigScreen({super.key});

  @override
  State<SmartConfigScreen> createState() => _SmartConfigScreenState();
}

class _SmartConfigScreenState extends State<SmartConfigScreen> {
  final _provisioner = Provisioner.espTouch();
  final _formKey = GlobalKey<FormState>();
  final _wifiPasswordController = TextEditingController();
  final _deviceNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _wifiSsidController = TextEditingController(); // Добавляем контроллер для SSID

  String? _currentSsid;
  bool _isLoading = false;
  bool _isCheckingPermissions = true;
  String _status = 'Готов к настройке';
  final _prefs = PreferencesManager();
  bool _isApMode = false;
  final NetworkInfo _networkInfo = NetworkInfo();

  static const List<String> _apPrefixes = ['RELE_','DAT_','IOT_DAT', 'LAMP_IOT', 'TERMO_IOT', 'UNI_IOT'];
  static const String _apDefaultIp = '192.168.4.1';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _checkAndRequestPermissions();
  }

  /// Проверка и запрос всех необходимых разрешений
  Future<void> _checkAndRequestPermissions() async {
    setState(() {
      _isCheckingPermissions = true;
      _status = 'Проверка разрешений...';
    });

    // Список необходимых разрешений для Android
    List<Permission> permissions = [
      Permission.location,
      Permission.nearbyWifiDevices, // Для Android 12+
    ];

    // Запрашиваем разрешения
    Map<Permission, PermissionStatus> statuses = await permissions.request();

    // Проверяем все разрешения
    bool allGranted = true;
    for (var permission in permissions) {
      if (statuses[permission] != PermissionStatus.granted) {
        allGranted = false;
        break;
      }
    }

    if (allGranted) {
      // Разрешения получены, получаем Wi-Fi информацию
      await _getCurrentWifi();
    } else {
      // Показываем диалог о необходимости разрешений
      _showPermissionsDeniedDialog();
    }

    setState(() {
      _isCheckingPermissions = false;
    });
  }

  void _showPermissionsDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Необходимы разрешения'),
        content: const Text(
          'Для работы приложения необходимы разрешения на определение местоположения.\n\n'
              'Это нужно для определения имени Wi-Fi сети и настройки устройства.\n\n'
              'Пожалуйста, предоставьте разрешения в настройках телефона.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Возвращаемся на предыдущий экран
            },
            child: const Text('Выйти'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _checkAndRequestPermissions(); // Повторный запрос
            },
            child: const Text('Попробовать снова'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPreferences() async {
    final credentials = await _prefs.getMqttCredentials();
    _usernameController.text = credentials.login;
    _passwordController.text = credentials.password;

    final devices = await _prefs.getDevices();
    if (devices.isNotEmpty) {
      _deviceNameController.text = '${devices[0].name}_new';
    } else {
      _deviceNameController.text = 'esp8266_sensor';
    }
  }

  Future<void> _getCurrentWifi() async {
    try {
      setState(() {
        _status = 'Получение информации о Wi-Fi...';
      });

      final ssid = await _networkInfo.getWifiName();

      setState(() {
        _currentSsid = ssid?.replaceAll('"', '');
        if (_currentSsid == null || _currentSsid == 'null' || _currentSsid == '') {
          _currentSsid = 'Не удалось определить сеть';
        }
        _checkIfApMode();
      });

      if (_currentSsid == 'Не удалось определить сеть') {
        _showNoWifiDialog();
      }
    } catch (e) {
      print('Error getting WiFi info: $e');
      setState(() {
        _currentSsid = 'Не удалось определить сеть';
      });
      _showNoWifiDialog();
    }
  }

  void _showNoWifiDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Wi-Fi не подключен'),
        content: const Text(
          'Для настройки устройства необходимо подключиться к Wi-Fi сети (2.4 GHz).\n\n'
              'Пожалуйста, подключитесь к Wi-Fi и вернитесь в приложение.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Возвращаемся на предыдущий экран
            },
            child: const Text('Выйти'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _getCurrentWifi(); // Повторная попытка
            },
            child: const Text('Проверить снова'),
          ),
        ],
      ),
    );
  }

  void _checkIfApMode() {
    if (_currentSsid != null &&
        _currentSsid != 'Не удалось определить сеть' &&
        _currentSsid != 'Нет разрешения на определение Wi-Fi') {
      _isApMode = _apPrefixes.any((prefix) => _currentSsid!.startsWith(prefix));

      // Если мы в режиме AP, очищаем поле для ввода SSID
      if (_isApMode) {
        _wifiSsidController.clear();
      }

      setState(() {});
    }
  }

  Future<void> _startConfiguration() async {
    if (!_formKey.currentState!.validate()) return;

    // Проверяем наличие SSID в зависимости от режима
    if (_isApMode) {
      if (_wifiSsidController.text.trim().isEmpty) {
        _showError('Введите имя Wi-Fi сети');
        return;
      }
    } else {
      if (_currentSsid == null ||
          _currentSsid == 'Не удалось определить сеть' ||
          _currentSsid == 'Нет разрешения на определение Wi-Fi') {
        _showError('Не удалось определить Wi-Fi сеть. Убедитесь, что вы подключены к Wi-Fi.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _status = _isApMode
          ? 'Отправка настроек на устройство...'
          : 'Отправка данных на устройство через SmartConfig...\nУбедитесь, что устройство в режиме SmartConfig';
    });

    if (_isApMode) {
      await _sendConfigToAp();
    } else {
      await _startSmartConfig();
    }
  }

  DeviceType devicesType(String device) {
    switch(device.toUpperCase()) {
      case "DAT":
        return DeviceType.dat;
      case "RELE":
        return DeviceType.rele;
      case "LAMP":
        return DeviceType.lamp;
      case "ROZ":
        return DeviceType.roz;
      case "TERMO1":
        return DeviceType.termo1;
      default:
        return DeviceType.dat; // Значение по умолчанию
    }
  }

  Future<void> _sendConfigToAp() async {
    try {
      // Используем введенный SSID в режиме AP
      final targetSsid = _wifiSsidController.text.trim();

      final config = {
        'ssid': targetSsid,  // Используем введенный SSID
        'wifi_password': _wifiPasswordController.text.trim(),
        'mqtt_server': 'iot-mqtt.ru',
        'mqtt_port': 1883,
        'device_type': 'dat',
        'mqtt_user': _usernameController.text.trim(),
        'mqtt_password': _passwordController.text.trim(),
        'device_name': _deviceNameController.text.trim(),
        'update_interval': 120,
        'dat': 'DHT',
      };

      print('Sending config to AP mode');
      print('Target SSID: $targetSsid');
      print('Config: $config');

      final response = await http.post(
        Uri.parse('http://$_apDefaultIp/api/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        // Парсим ответ для получения MAC и типа устройства
        DeviceType deviceType = DeviceType.dat;
        String deviceMac = '';
        String? deviceMacFromResponse;
        String? deviceDatFromResponse;

        try {
          bool err=false;
          final responseData = jsonDecode(response.body);
          // Если устройство возвращает MAC в ответе
          if (responseData is Map && responseData.containsKey('mac') ) {
            deviceMacFromResponse = responseData['mac'] as String?;

            if (deviceMacFromResponse != null &&
                deviceMacFromResponse.isNotEmpty) {
              deviceMac = deviceMacFromResponse;
              print('MAC from device response: $deviceMac');
            } else {
              err = true;
            }
          }else {
            err = true;
          }

          if (responseData is Map && responseData.containsKey('type') ) {
            deviceDatFromResponse = responseData['type'] as String?;
            if (deviceDatFromResponse != null &&
                deviceDatFromResponse.isNotEmpty) {
              deviceType = devicesType(deviceDatFromResponse);
              print('DAT from device response: $deviceType');
            } else {
              err = true;
            }
          }else {
            err = true;
          }

          if(err==true)
          {
            print('MAC адресс или тип датчика нераспознан!');
            _showError('Тип датчика нераспознан: ${response.statusCode}\n${response.body}');
            setState(() {
              _isLoading = false;
            });
            return;
          }

        } catch (e) {
          print('Could not parse response: $e');
        }

        final device = DeviceModel(
          id: deviceMac.isNotEmpty ? deviceMac : targetSsid,
          type: deviceType,
          name: _deviceNameController.text.trim(),
          mac: deviceMac,
          ip: _apDefaultIp,
          login: _usernameController.text.trim(),
        );

      //  await _prefs.addDevice(device);

        if (context.mounted) {
          final provider = Provider.of<DeviceProvider>(context, listen: false);
          await provider.addDevice(device);
        }

        _showSuccess('Настройки успешно отправлены!\n'
            'Устройство подключится к сети: $targetSsid\n'
            'IP-адрес можно будет увидеть в списке устройств после перезагрузки.');
      } else {
        _showError('Ошибка отправки: ${response.statusCode}\n${response.body}');
      }
    } catch (e) {
      _showError('Ошибка соединения: $e\n\n'
          'Убедитесь, что вы подключены к точке доступа устройства (${_apPrefixes.join(", ")})');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _startSmartConfig() async {
    // Подписываемся на результат SmartConfig
    late StreamSubscription<ProvisioningResponse> subscription;
    Completer<ProvisioningResponse> completer = Completer();

    subscription = _provisioner.listen((result) {
      print('SmartConfig result: ${result.bssidText}');
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    });

    try {
      final request = ProvisioningRequest.fromStrings(
        ssid: _currentSsid!,
        password: _wifiPasswordController.text.trim(),
      );

      // Запускаем SmartConfig
      await _provisioner.start(request);

      // Ждем результат с таймаутом 60 секунд
      final result = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw TimeoutException('SmartConfig timeout');
        },
      );

      // Устройство найдено!
      // Исправление: преобразуем Uint8List в String
      String deviceIp;
      if (result.ipAddress is List<int>) {
        // IP приходит как Uint8List, например [192, 168, 1, 100]
        deviceIp = (result.ipAddress as List<int>).join('.');
      } else {
        deviceIp = result.ipAddress.toString();
      }

      final deviceMac = result.bssidText;

      setState(() {
        _status = 'Устройство найдено!\nIP: $deviceIp\nMAC: $deviceMac\nОтправка настроек...';
      });

      // Останавливаем SmartConfig
      await subscription.cancel();
      _provisioner.stop();

      // Отправляем остальные настройки
      await _sendConfigToDevice(deviceIp, deviceMac);

    } catch (e, s) {
      print('SmartConfig error: $e');
      print('Stack trace: $s');
      _showError('Ошибка SmartConfig: $e\n\nУбедитесь, что устройство в режиме SmartConfig');
      setState(() {
        _isLoading = false;
      });
      _provisioner.stop();
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _sendConfigToDevice(String deviceIp, String deviceMacFromSmartConfig) async {
    try {
      final config = {
        'mqtt_server': 'iot-mqtt.ru',
        'mqtt_port': 1883,
        'device_type': 'dat',  // Добавляем тип устройства
        'mqtt_user': _usernameController.text.trim(),
        'mqtt_password': _passwordController.text.trim(),
        'device_name': _deviceNameController.text.trim(),
        'update_interval': 120,
        'dat': 'DHT',
        'api_key': '',
      };

      print('Sending config to: http://$deviceIp/api/config');
      print('Config: $config');

      final response = await http.post(
        Uri.parse('http://$deviceIp/api/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config),
      ).timeout(const Duration(seconds: 10));

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        // Парсим ответ от устройства
        DeviceType deviceType = DeviceType.dat;
        String deviceMac = deviceMacFromSmartConfig;
        String? deviceMacFromResponse;
        String? deviceDatFromResponse;

        try {
          bool err=false;
          final responseData = jsonDecode(response.body);
          // Если устройство возвращает MAC в ответе
          if (responseData is Map && responseData.containsKey('mac') ) {
            deviceMacFromResponse = responseData['mac'] as String?;

            if (deviceMacFromResponse != null &&
                deviceMacFromResponse.isNotEmpty) {
              deviceMac = deviceMacFromResponse;
              print('MAC from device response: $deviceMac');
            } else {
              err = true;
            }
          }else {
            err = true;
          }

          if (responseData is Map && responseData.containsKey('type') ) {
            deviceDatFromResponse = responseData['type'] as String?;
            if (deviceDatFromResponse != null &&
                deviceDatFromResponse.isNotEmpty) {
              deviceType = devicesType(deviceDatFromResponse);
              print('DAT from device response: $deviceType');
            } else {
              err = true;
            }
          }else {
            err = true;
          }

          if(err==true)
            {
              print('MAC адресс или тип датчика нераспознан!');
              _showError('Тип датчика нераспознан: ${response.statusCode}\n${response.body}');
              setState(() {
                _isLoading = false;
              });
              return;
            }

        } catch (e) {
          print('Could not parse response: $e');
        }

        final device = DeviceModel(
          id: deviceMac,
          name: _deviceNameController.text.trim(),
          type: deviceType,  // Добавляем тип устройства
          mac: deviceMac,
          ip: deviceIp,
          login: _usernameController.text.trim(),
        );

       // await _prefs.addDevice(device);

        if (context.mounted) {
          final provider = Provider.of<DeviceProvider>(context, listen: false);
          await provider.addDevice(device);
        }

        _showSuccess('Настройки успешно отправлены!');
      } else {
        _showError('Ошибка отправки настроек: ${response.statusCode}\n${response.body}');
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error sending config: $e');
      _showError('Ошибка соединения: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccess(String message) {
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SuccessScreen(message: message),
        ),
      );
    }
  }

  void _showError(String message) {
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ошибка'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _isLoading = false;
                  _status = 'Готов к настройке';
                });
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройка устройства'),
      ),
      body: _isCheckingPermissions
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Проверка разрешений...'),
          ],
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Информация о текущем подключении
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isApMode ? Colors.blue.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isApMode ? Icons.wifi_tethering : Icons.wifi,
                      color: _isApMode ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isApMode ? 'Режим: настройка через точку доступа' : (_currentSsid ?? 'Определение сети...'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (_isApMode)
                            const Text(
                              'Вы подключены к точке доступа устройства',
                              style: TextStyle(fontSize: 12, color: Colors.blue),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Поле для ввода SSID - показываем ТОЛЬКО в режиме AP
              if (_isApMode) ...[
                TextFormField(
                  controller: _wifiSsidController,
                  decoration: const InputDecoration(
                    labelText: 'Имя Wi-Fi сети',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.wifi),
                    helperText: 'Введите имя вашей домашней Wi-Fi сети',
                  ),
                  validator: (value) {
                    if (_isApMode && (value == null || value.trim().isEmpty)) {
                      return 'Введите имя Wi-Fi сети';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Поле для пароля Wi-Fi
              TextFormField(
                controller: _wifiPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль Wi-Fi',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                  helperText: 'Пароль от вашей домашней Wi-Fi сети',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите пароль Wi-Fi';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _deviceNameController,
                decoration: const InputDecoration(
                  labelText: 'Имя устройства',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.devices),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите имя устройства';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Логин MQTT',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите логин MQTT';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль MQTT',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите пароль MQTT';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Индикатор загрузки или кнопка
              if (_isLoading) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
                Center(child: Text(_status)),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startConfiguration,
                    icon: Icon(_isApMode ? Icons.send : Icons.wifi_tethering),
                    label: Text(_isApMode ? 'Отправить настройки' : 'Начать настройку'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],

              // Информационные подсказки
              if (!_isApMode && !_isLoading) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Убедитесь, что устройство находится в режиме SmartConfig.\n'
                              'Нажмите кнопку на устройстве или перезагрузите его.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_isApMode && !_isLoading) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Вы подключены к точке доступа устройства. '
                              'Введите имя вашей домашней Wi-Fi сети и нажмите "Отправить настройки".',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
