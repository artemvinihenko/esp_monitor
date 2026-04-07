import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/device_model.dart';
import '../providers/device_provider.dart';
import '../services/preferences_manager.dart';

class QRAddScreen extends StatefulWidget {
  const QRAddScreen({super.key});

  @override
  State<QRAddScreen> createState() => _QRAddScreenState();
}

class _QRAddScreenState extends State<QRAddScreen> with WidgetsBindingObserver {
  final MobileScannerController _scannerController = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
    detectionSpeed: DetectionSpeed.normal,
    returnImage: false,
  );

  Timer? _debounceTimer;
  bool _isProcessing = false;
  bool _hasPermission = false;
  String _statusMessage = 'Наведите камеру на QR-код устройства';
  String _lastDetected = '';
  final _prefs = PreferencesManager();
  String? _currentServer;
  String? _currentLogin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionAndStart();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionAndStart();
    }
  }

  Future<void> _checkPermissionAndStart() async {
    final status = await Permission.camera.request();

    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
        _statusMessage = 'Наведите камеру на QR-код устройства';
      });
      await _scannerController.start();
    } else if (status.isDenied) {
      setState(() {
        _hasPermission = false;
        _statusMessage = 'Нет разрешения на использование камеры';
      });
      _showPermissionDialog();
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _hasPermission = false;
        _statusMessage = 'Разрешение на камеру заблокировано навсегда';
      });
      _showOpenSettingsDialog();
    }
  }

  Future<void> _processQRCode(String qrData) async {
    if (_isProcessing) return;

    debugPrint('=== QR CODE DETECTED ===');
    debugPrint('Raw QR data: $qrData');

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Обработка QR-кода...';
      _lastDetected = qrData;
    });

    await _scannerController.stop();

    try {
      // Парсим QR данные
      Map<String, dynamic>? deviceData = _parseQRData(qrData);

      if (deviceData == null) {
        debugPrint('Failed to parse QR data');
        _showError('Неверный формат QR-кода');
        _resetScanner();
        return;
      }

      debugPrint('Parsed device data: $deviceData');

      // Проверяем MQTT настройки
      final credentials = await _prefs.getMqttCredentials();
      _currentServer = await _prefs.getCurrentServer();
     _currentLogin = credentials.login;
      if (credentials.login.isEmpty || credentials.password.isEmpty) {
        _showError('Сначала сохраните MQTT настройки');
        _resetScanner();
        return;
      }

      // Проверяем, не существует ли уже устройство
      final existingDevices = await _prefs.getDevices(_currentServer!,_currentLogin!);
      final exists = existingDevices.any((d) => d.mac == deviceData['mac']);

      if (exists) {
        debugPrint('Device already exists: ${deviceData['mac']}');
        _showError('Устройство с таким MAC уже существует');
        _resetScanner();
        return;
      }

      // Создаем устройство
      final device = DeviceModel(
        id: deviceData['mac']!,
        name: deviceData['name'] ?? 'Новое устройство',
        mac: deviceData['mac']!,
        type: _parseDeviceType(deviceData['type']),
        ip: deviceData['ip'] ?? 'Неизвестно',
        login: credentials.login,
      );

      // Сохраняем токен если есть
     // if (deviceData['token'] != null && deviceData['token']!.isNotEmpty) {
    //    await _prefs.saveDeviceToken(device.mac, deviceData['token']!);
     //   print('Token saved: ${deviceData['token']}');
    //  }

      // Добавляем устройство в хранилище
     // await _prefs.addDevice(device);
   //   print('Device saved to storage');

      // ОБНОВЛЯЕМ ПРОВАЙДЕР - ЭТО ГЛАВНОЕ!
      if (context.mounted) {
        final provider = Provider.of<DeviceProvider>(context, listen: false);
        await provider.addDevice(device);
        debugPrint('Device added to provider, notifying listeners');
      }

      setState(() {
        _statusMessage = 'Устройство "${device.name}" успешно добавлено!';
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Устройство "${device.name}" добавлено!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );

        // ПЕРЕХОД НА ГЛАВНУЮ СТРАНИЦУ
        // Через 1.5 секунды возвращаемся на главный экран
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (context.mounted) {
            // Возвращаемся на главный экран (вкладка "Устройства")
            Navigator.popUntil(context, (route) => route.isFirst);

            // Показываем дополнительное уведомление
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Устройство появится в списке через несколько секунд'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        });
      }

    } catch (e, stack) {
      debugPrint('Error processing QR: $e');
      debugPrint('Stack trace: $stack');
      _showError('Ошибка: $e');
      _resetScanner();
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  DeviceType _parseDeviceType(String? type) {
    switch (type?.toLowerCase()) {
      case 'lamp':
        return DeviceType.lamp;
      case 'roz':
      case 'roza':
      case 'rozv':
      case 'rozav':
      case 'socket':
        return DeviceType.roz;
      case 'rele':
        return DeviceType.rele;
      case 'termo1':
        return DeviceType.termo1;
      case 'led':
        return DeviceType.lamp;
      default:
        return DeviceType.dat;
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Необходимо разрешение'),
            content: const Text(
                'Для сканирования QR-кодов нужно разрешить доступ к камере.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _checkPermissionAndStart();
                },
                child: const Text('Разрешить'),
              ),
            ],
          ),
    );
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Доступ к камере заблокирован'),
            content: const Text(
                'Пожалуйста, разрешите доступ к камере в настройках телефона.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('Открыть настройки'),
              ),
            ],
          ),
    );
  }

  void _showError(String message) {
    debugPrint('Error: $message');
    setState(() {
      _statusMessage = message;
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5)),
      );
    }
  }

  void _resetScanner() {
    setState(() {
      _isProcessing = false;
      _statusMessage = 'Наведите камеру на QR-код устройства';
    });
    _scannerController.start();
  }

  void _toggleTorch() {
    _scannerController.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return SingleChildScrollView(
        child: Column(
          children: [
        // Статус
        Container(
          padding: const EdgeInsets.all(16),
          color: _hasPermission ? Colors.blue.shade50 : Colors.red.shade50,
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    _hasPermission ? Icons.qr_code_scanner : Icons.error,
                    color: _hasPermission ? Colors.blue : Colors.red,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _hasPermission ? Colors.blue : Colors.red,
                      ),
                    ),
                  ),
                  if (_hasPermission)
                    IconButton(
                      icon: const Icon(Icons.flash_on),
                      onPressed: _toggleTorch,
                      tooltip: 'Вспышка',
                    ),
                ],
              ),
              if (_lastDetected.isNotEmpty && _isProcessing)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Последний QR: $_lastDetected',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),

        // Камера для сканирования - УВЕЛИЧЕННЫЙ РАЗМЕР
        Container(
          margin: const EdgeInsets.all(16),
          height: screenHeight * 0.55,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: _hasPermission
                ? MobileScanner(
              controller: _scannerController,
              onDetect: (capture) {
                if (_isProcessing) return;
                if (capture.barcodes.isEmpty) return;

                final barcode = capture.barcodes.first;
                String? qrData = barcode.rawValue;

                // Логируем raw bytes для отладки
                if (barcode.rawBytes != null) {
                  debugPrint('Raw bytes length: ${barcode.rawBytes!.length}');
                  String hexString = barcode.rawBytes!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
                  debugPrint('Raw bytes (hex): $hexString');

                  // Пробуем декодировать с разными кодировками
                  if (qrData == null) {
                    // Пробуем UTF-8
                    try {
                      qrData = utf8.decode(barcode.rawBytes!, allowMalformed: true);
                      debugPrint('Decoded with UTF-8: $qrData');
                    } catch (e) {
                      debugPrint('UTF-8 decode error: $e');
                    }

                    // Если UTF-8 не помог, пробуем Latin-1
                    if (qrData == null || qrData.isEmpty) {
                      try {
                        qrData = latin1.decode(barcode.rawBytes!);
                        debugPrint('Decoded with Latin-1: $qrData');
                      } catch (e) {
                        debugPrint('Latin-1 decode error: $e');
                      }
                    }
                  }
                }

                if (qrData != null && qrData.isNotEmpty) {
                  // Дополнительная очистка перед парсингом
                 // qrData = _preprocessQrData(qrData);
                  debugPrint('Final QR data after preprocessing: $qrData');
                  _processQRCode(qrData);
                } else {
                  debugPrint('Could not extract data from QR code');
                }
              },
              errorBuilder: (context, error, child) {
                debugPrint('Camera error: $error');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Ошибка камеры: $error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _checkPermissionAndStart,
                        child: const Text('Попробовать снова'),
                      ),
                    ],
                  ),
                );
              },
            )
                : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(_statusMessage),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _checkPermissionAndStart,
                    child: const Text('Разрешить доступ к камере'),
                  ),
                ],
              ),
            ),
          ),
        ),
          ],
        ),
    );
  }

//////////////////
  Map<String, dynamic>? _extractWithRegex(String data) {
    debugPrint('Extracting with regex from: $data');

    // Извлекаем MAC
  //  final macRegex = RegExp(r'"mac"\s*:\s*"([A-F0-9]+)"', caseSensitive: false);
    final macRegex = RegExp(
        r'"mac"\s*:\s*"((?:[A-Za-z0-9]{4}-){5}[A-Za-z0-9]{4})"',
        caseSensitive: false
    );
    final macMatch = macRegex.firstMatch(data);
    final mac = macMatch?.group(1)?.toUpperCase();

    if (mac == null) {
      debugPrint('MAC not found');
      return null;
    }

    // Извлекаем тип
    final typeRegex = RegExp(r'"type"\s*:\s*"(\w+)"', caseSensitive: false);
    final typeMatch = typeRegex.firstMatch(data);
    final type = typeMatch?.group(1)?.toLowerCase();
    if (type == null) {
      debugPrint('Type not found');
      return null;
    }

    // Извлекаем имя (русские буквы, цифры, пробелы)
    final nameRegex = RegExp(r'"name"\s*:\s*"([^"]*)"');
    final nameMatch = nameRegex.firstMatch(data);
    var name = nameMatch?.group(1);
    if (name == null) {
      debugPrint('Name not found');
      return null;
    }

    // Очищаем имя от мусора
    name = name.replaceAll(RegExp(r'[^\w\s\u0410-\u044F]'), '');
    name = name.trim();
  
    debugPrint('Regex extract - MAC: $mac, Type: $type, Name: $name');

    return {
      'mac': mac,
      'name': name.isEmpty == true ? null : name,
      'type': type,
      'ip': null,
      'token': null,
    };
  }
  ////////////////////////////////////////////////////////
  Map<String, dynamic>? _parseQRData(String qrData) {
    debugPrint('=== PARSING QR DATA ===');
    debugPrint('Raw input: $qrData');

    if (qrData.isEmpty) return null;

    // Очищаем строку от всех непечатных символов, оставляя только печатные ASCII и Unicode
    String cleanData = qrData.replaceAll(RegExp(r'[^\x20-\x7E\u0400-\u04FF]'), '');

    // Удаляем BOM если есть
    if (cleanData.startsWith('\uFEFF')) {
      cleanData = cleanData.substring(1);
    }

    // Пробуем найти валидный JSON между скобками
    String? extractedJson = _extractJsonFromString(cleanData);

// Пробуем другой подход - ищем JSON с помощью регулярного выражения
    extractedJson ??= _findJsonWithRegex(cleanData);

    if (extractedJson == null) {
      debugPrint('Could not find valid JSON');
      return _extractWithRegex(cleanData);
    }

    // Парсим JSON
    try {
      final jsonData = jsonDecode(extractedJson);

      if (jsonData is! Map<String, dynamic>) {
        debugPrint('JSON is not a Map');
        return null;
      }

      String? mac = jsonData['mac']?.toString();
      if (mac == null || mac.isEmpty) {
        debugPrint('Missing "mac" field');
        return null;
      }

      mac = mac.toUpperCase();
      final name = jsonData['name']?.toString();
      final type = jsonData['type']?.toString() ?? 'dat';
      final ip = jsonData['ip']?.toString();
      final token = jsonData['token']?.toString();

      // Очищаем имя от мусора
      final cleanName = name?.replaceAll(RegExp(r'[^\w\s\u0410-\u044F]'), '').trim() ?? '';

      debugPrint('Parsed - MAC: $mac, Type: $type, Name: $cleanName');

      return {
        'mac': mac,
        'name': cleanName.isEmpty ? null : cleanName,
        'type': type.toLowerCase(),
        'ip': ip,
        'token': token,
      };

    } catch (e) {
      debugPrint('JSON parse error: $e');
      return _extractWithRegex(cleanData);
    }
  }

  String? _extractJsonFromString(String input) {
    // Ищем первый '{' и последний '}'
    int startIndex = -1;
    int endIndex = -1;
    int braceCount = 0;

    for (int i = 0; i < input.length; i++) {
      if (input[i] == '{') {
        if (startIndex == -1) {
          startIndex = i;
        }
        braceCount++;
      } else if (input[i] == '}') {
        braceCount--;
        if (braceCount == 0 && startIndex != -1) {
          endIndex = i;
          break;
        }
      }
    }

    if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
      String candidate = input.substring(startIndex, endIndex + 1);

      // Проверяем, является ли кандидат валидным JSON
      try {
        jsonDecode(candidate);
        debugPrint('Found valid JSON: $candidate');
        return candidate;
      } catch (e) {
        // Если не валидный JSON, пробуем очистить от мусорных символов
        String cleaned = _cleanJsonString(candidate);
        try {
          jsonDecode(cleaned);
          debugPrint('Found JSON after cleaning: $cleaned');
          return cleaned;
        } catch (e) {
          debugPrint('Candidate is not valid JSON');
        }
      }
    }

    return null;
  }

  String? _findJsonWithRegex(String input) {
    // Регулярное выражение для поиска JSON-подобной структуры
    final jsonRegex = RegExp(r'\{[^{}]*"mac"\s*:\s*"[^"]+"[^{}]*\}');
    final match = jsonRegex.firstMatch(input);

    if (match != null) {
      String candidate = match.group(0)!;
      try {
        jsonDecode(candidate);
        debugPrint('Found JSON with regex: $candidate');
        return candidate;
      } catch (e) {
        // Пробуем очистить найденную строку
        String cleaned = _cleanJsonString(candidate);
        try {
          jsonDecode(cleaned);
          debugPrint('Found JSON with regex after cleaning: $cleaned');
          return cleaned;
        } catch (e) {
          debugPrint('Regex match is not valid JSON');
        }
      }
    }

    return null;
  }

  String _cleanJsonString(String jsonStr) {
    // Удаляем все escape-последовательности, которые могут нарушать JSON
    String cleaned = jsonStr.replaceAll(RegExp(r'\\(?!["\\/bfnrt]|u[0-9a-fA-F]{4})'), '');

    // Удаляем недопустимые управляющие символы
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');

    // Исправляем возможные проблемы с кавычками
    cleaned = cleaned.replaceAll(RegExp(r'(?<!\\)"'), '"');

    // Удаляем лишние пробелы в ключах и значениях
    cleaned = cleaned.replaceAll(RegExp(r'"\s+:\s+"'), '":"');
    cleaned = cleaned.replaceAll(RegExp(r',\s+"'), ',"');
    cleaned = cleaned.replaceAll(RegExp(r'{\s+"'), '{"');

    return cleaned;
  }
/////////////////////////////////////////////////////

}