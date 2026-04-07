import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/work_manager_service.dart';
import '../providers/device_provider.dart';
import '../models/device_model.dart';
import 'debug_tab.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isBatteryOptimizationIgnored = false;
  bool _hasNotificationPermission = false;
  bool _hasWifiPermission = false;
  int _pollingInterval = 15;
  
  // Для выбора датчика уведомления
  String _selectedDeviceMac = '';
  String _selectedDataType = 'temperature';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkPermissions();
    _loadNotificationSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadNotificationSettings() async {
    // Загружаем сохраненные настройки уведомления
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedDeviceMac = prefs.getString('notification_device_mac') ?? '';
      _selectedDataType = prefs.getString('notification_device_type') ?? 'temperature';
    });
  }

  Future<void> _saveNotificationSettings(String mac, String dataType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notification_device_mac', mac);
    await prefs.setString('notification_device_type', dataType);
    setState(() {
      _selectedDeviceMac = mac;
      _selectedDataType = dataType;
    });
    
    // Обновляем уведомление
    await WorkManagerService.runNow();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки уведомления сохранены')),
      );
    }
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      final notificationStatus = await Permission.notification.status;
      final wifiStatus = await Permission.nearbyWifiDevices.status;

      setState(() {
        _isBatteryOptimizationIgnored = batteryStatus.isGranted;
        _hasNotificationPermission = notificationStatus.isGranted;
        _hasWifiPermission = wifiStatus.isGranted;
      });
    }
  }

  Future<void> _requestBatteryOptimization() async {
    if (Platform.isAndroid) {
      final status = await Permission.ignoreBatteryOptimizations.request();
      setState(() {
        _isBatteryOptimizationIgnored = status.isGranted;
      });

      if (!status.isGranted) {
        _showInfoDialog(
          'Оптимизация батареи',
          'Для стабильной работы приложения в фоне, пожалуйста, отключите оптимизацию батареи для этого приложения в настройках телефона.',
        );
      }
    }
  }

  void _openAppSettings() {
    if (Platform.isAndroid) {
      openAppSettings();
    }
  }

  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _getDeviceName(String mac) {
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    final device = provider.devices.firstWhere(
      (d) => d.mac == mac,
      orElse: () => DeviceModel(
        id: '', name: 'Неизвестно', mac: '', type: DeviceType.dat, ip: '', login: '',
      ),
    );
    return device.name;
  }

  void _showDeviceSelector() {
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SizedBox(
        height: 400,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Выберите устройство для отображения',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: provider.devices.length,
                itemBuilder: (context, index) {
                  final device = provider.devices[index];
                  return ListTile(
                    leading: Text(device.type.icon),
                    title: Text(device.name),
                    subtitle: Text(device.mac),
                    trailing: device.mac == _selectedDeviceMac
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      _showDataTypeSelector(device.mac);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDataTypeSelector(String mac) {
    final provider = Provider.of<DeviceProvider>(context, listen: false);
    final device = provider.devices.firstWhere((d) => d.mac == mac);
    
    final List<Map<String, String>> options = [];
    
    if (device.type == DeviceType.dat) {
      options.add({'type': 'temperature', 'name': '🌡️ Температура'});
      options.add({'type': 'humidity', 'name': '💧 Влажность'});
    } else if (device.type == DeviceType.termo1) {
      options.add({'type': 'temperature', 'name': '🌡️ Температура'});
    } else {
      options.add({'type': 'state', 'name': '⚡ Состояние (ON/OFF)'});
    }
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SizedBox(
        height: 300,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Выберите данные для отображения',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  return ListTile(
                    title: Text(option['name']!),
                    trailing: option['type'] == _selectedDataType
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      _saveNotificationSettings(mac, option['type']!);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: 'Общие'),
            Tab(icon: Icon(Icons.bug_report), text: 'Отладка'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Вкладка "Общие"
          ListView(
            children: [
              const SizedBox(height: 16),
              
              // Важная информация для TECNO
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                color: Colors.orange.shade50,
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.warning_amber, color: Colors.orange),
                      title: Text(
                        'Важно для фоновой работы!',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'На некоторых телефонах (Xiaomi, Huawei, Oppo, TECNO) нужно разрешить автозапуск в настройках системы',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.settings, color: Colors.blue),
                      title: const Text('Открыть настройки приложения'),
                      subtitle: const Text('Разрешить все разрешения вручную'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _openAppSettings,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Секция "Уведомление в статус-баре"
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Text(
                  'УВЕДОМЛЕНИЕ В СТАТУС-БАРЕ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ),
              
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications, color: Colors.blue),
                      title: const Text('Показывать датчик'),
                      subtitle: Text(_selectedDeviceMac.isEmpty 
                          ? 'Не выбран' 
                          : '${_getDeviceName(_selectedDeviceMac)} - ${_getDataTypeName(_selectedDataType)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _showDeviceSelector,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Секция "Периодичность опроса"
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Text(
                  'ФОНОВОЙ ОПРОС',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ),

              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.timer),
                  title: const Text('Интервал опроса'),
                  subtitle: Text('$_pollingInterval минут'),
                  trailing: DropdownButton<int>(
                    value: _pollingInterval,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 минута')),
                      DropdownMenuItem(value: 5, child: Text('5 минут')),
                      DropdownMenuItem(value: 10, child: Text('10 минут')),
                      DropdownMenuItem(value: 15, child: Text('15 минут')),
                      DropdownMenuItem(value: 30, child: Text('30 минут')),
                      DropdownMenuItem(value: 60, child: Text('60 минут')),
                    ],
                    onChanged: (value) async {
                      if (value != null) {
                        setState(() {
                          _pollingInterval = value;
                        });
                        await WorkManagerService.setPollingInterval(value);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Интервал опроса изменён на $value минут')),
                        );
                      }
                    },
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Работа в фоне
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Text(
                  'РАБОТА В ФОНЕ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ),

              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SwitchListTile(
                  title: const Text('Игнорировать оптимизацию батареи'),
                  subtitle: const Text('Позволяет приложению работать в фоне без ограничений'),
                  value: _isBatteryOptimizationIgnored,
                  onChanged: (_) => _requestBatteryOptimization(),
                  activeThumbColor: Colors.green,
                ),
              ),

              const SizedBox(height: 16),

              // Уведомления
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Text(
                  'УВЕДОМЛЕНИЯ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ),

              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SwitchListTile(
                  title: const Text('Показывать уведомления'),
                  subtitle: const Text('Уведомления о статусе подключения и событиях'),
                  value: _hasNotificationPermission,
                  onChanged: (_) async {
                    final status = await Permission.notification.request();
                    setState(() {
                      _hasNotificationPermission = status.isGranted;
                    });
                  },
                  activeThumbColor: Colors.green,
                ),
              ),

              const SizedBox(height: 16),

              // Wi-Fi
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Text(
                  'WI-FI',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ),

              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SwitchListTile(
                  title: const Text('Доступ к Wi-Fi сетям'),
                  subtitle: const Text('Необходимо для SmartConfig и определения сети'),
                  value: _hasWifiPermission,
                  onChanged: (_) async {
                    final status = await Permission.nearbyWifiDevices.request();
                    setState(() {
                      _hasWifiPermission = status.isGranted;
                    });
                  },
                  activeThumbColor: Colors.green,
                ),
              ),

              const SizedBox(height: 24),

              // Информация
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ℹ️ Для стабильной фоновой работы:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '1. Нажмите "Открыть настройки приложения" и разрешите все разрешения\n'
                      '2. Включите "Игнорировать оптимизацию батареи"\n'
                      '3. Разрешите уведомления\n'
                      '4. Выберите датчик для отображения в статус-баре\n'
                      '5. Настройте интервал опроса\n'
                      '6. Для диагностики перейдите на вкладку "Отладка"',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Вкладка "Отладка"
          const DebugTab(),
        ],
      ),
    );
  }
  
  String _getDataTypeName(String type) {
    switch (type) {
      case 'temperature':
        return 'Температура';
      case 'humidity':
        return 'Влажность';
      case 'state':
        return 'Состояние';
      default:
        return 'Температура';
    }
  }
}