import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/work_manager_service.dart';
import 'debug_tab.dart';
import '../providers/theme_provider.dart';


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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkPermissions();
    _loadPollingInterval();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPollingInterval() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt('polling_interval') ?? 15;
    setState(() {
      _pollingInterval = interval;
    });
  }

  Future<void> _savePollingInterval(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('polling_interval', minutes);
    await WorkManagerService.setPollingInterval(minutes);
    setState(() {
      _pollingInterval = minutes;
    });
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
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
              
              // Секция "Внешний вид"
              Card(
  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  child: Column(
    children: [
      ListTile(
        leading: const Icon(Icons.brightness_4),
        title: const Text('Тема оформления'),
        subtitle: Text(_getThemeName(themeProvider.currentTheme)),
        trailing: DropdownButton<AppTheme>(
          value: themeProvider.currentTheme,
          items: const [
            DropdownMenuItem(
              value: AppTheme.light,
              child: Text('Светлая'),
            ),
            DropdownMenuItem(
              value: AppTheme.dark,
              child: Text('Темная'),
            ),
            DropdownMenuItem(
              value: AppTheme.amethyst,
              child: Text('Аметист'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              themeProvider.setTheme(value);
            }
          },
        ),
      ),
      if (themeProvider.isAmethyst)
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.black,
                Colors.deepPurple.shade900,
                Colors.deepPurple.shade700,
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✨ Аметист тема',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Черно-фиолетовая тема с градиентным фоном',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
    ],
  ),
),
              
              const SizedBox(height: 16),
              
              // Секция "Фоновой опрос"
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
                        await _savePollingInterval(value);
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
                      '4. Настройте интервал опроса\n'
                      '5. Для диагностики перейдите на вкладку "Отладка"',
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
  
  String _getThemeName(AppTheme theme) {
  switch (theme) {
    case AppTheme.light:
      return 'Светлая';
    case AppTheme.dark:
      return 'Темная';
    case AppTheme.amethyst:
      return 'Аметист';
  }
}

}