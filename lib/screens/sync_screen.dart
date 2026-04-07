import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/preferences_manager.dart';
import '../providers/device_provider.dart';
import '../models/device_model.dart';


class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isSyncing = false;
  List<Map<String, dynamic>> _devicesFromServer = [];
  String _statusMessage = '';
  String _currentServer = '';
  
  final _prefs = PreferencesManager();

  @override
  void initState() {
    super.initState();
    _loadData();
  }
  
  Future<void> _loadData() async {
    final server = await _prefs.getCurrentServer();
    final credentials = await _prefs.getApiCredentials();
    
    setState(() {
      _currentServer = server;
      _loginController.text = credentials.login;
      _passwordController.text = credentials.password;
    });
  }
  
  Future<void> _authenticate() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Авторизация...';
      _devicesFromServer = [];
    });
    
    final login = _loginController.text.trim();
    final password = _passwordController.text.trim();
    
    await _prefs.saveApiCredentials(login, password);
    ApiService.setServer(_currentServer);
    
    final token = await ApiService.getAuthToken(login, password);
    
    if (token != null) {
      await _prefs.saveApiToken(token);
      setState(() {
        _statusMessage = 'Авторизация успешна! Загрузка устройств...';
      });
      await _loadDevices();
    } else {
      setState(() {
        _statusMessage = 'Ошибка авторизации. Проверьте логин и пароль.';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadDevices() async {
    setState(() {
      _isSyncing = true;
      _statusMessage = 'Загрузка устройств...';
    });
    
    final devices = await ApiService.getDevices();
    
    setState(() {
      _devicesFromServer = devices;
      _isLoading = false;
      _isSyncing = false;
      _statusMessage = devices.isEmpty 
          ? 'Устройства не найдены' 
          : 'Найдено ${devices.length} устройств';
    });
  }
  
  Future<void> _syncDevices() async {
    if (_devicesFromServer.isEmpty) return;
    
    setState(() {
      _isSyncing = true;
      _statusMessage = 'Синхронизация устройств...';
    });
    
    final login = _loginController.text.trim();
    final server = _currentServer;
    
    int addedCount = 0;
    int skippedCount = 0;
    
    final existingDevices = await _prefs.getDevices(server, login);
    final existingMacs = existingDevices.map((d) => d.mac).toSet();
    
    for (final deviceData in _devicesFromServer) {
      final id = deviceData['idd'] as String?;
      final name = deviceData['name'] as String;
      final mem = deviceData['mem'] as String? ?? 'none';
      final type = ApiService.parseDeviceType(mem);
      
      if (id == null || id.isEmpty) {
        skippedCount++;
        continue;
      }
      if (name.isEmpty) {
        skippedCount++;
        continue;
      }
      if (type ==DeviceType.none ) {
        skippedCount++;
        continue;
      }
      
      if (existingMacs.contains(id)) {
        skippedCount++;
        continue;
      }
      
      final device = DeviceModel(
        id: id,
        name: name,
        mac: id,
        type: type,
        ip: 'Неизвестно',
        login: login,
      );
      
      await _prefs.addDevice(device, server, login);
      
      if (context.mounted) {
        final provider = Provider.of<DeviceProvider>(context, listen: false);
        await provider.refreshDevices();
      }
      
      addedCount++;
    }
    
    setState(() {
      _isSyncing = false;
      _statusMessage = 'Синхронизация завершена: добавлено $addedCount, пропущено $skippedCount';
      _devicesFromServer = [];
    });
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Добавлено $addedCount устройств для сервера $server'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Текущий сервер: $_currentServer',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Синхронизация с сервером',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Для синхронизации используйте логин и пароль от вашего аккаунта',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _loginController,
                            decoration: const InputDecoration(
                              labelText: 'Логин аккаунта',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите логин';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Пароль аккаунта',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.lock),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Введите пароль';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isLoading ? null : _authenticate,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.cloud_sync),
                              label: const Text('Загрузить устройства'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_statusMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusMessage.contains('успешна') || _statusMessage.contains('завершена')
                        ? Colors.green.shade50
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _statusMessage.contains('успешна') || _statusMessage.contains('завершена')
                            ? Icons.check_circle
                            : Icons.info,
                        color: _statusMessage.contains('успешна') || _statusMessage.contains('завершена')
                            ? Colors.green
                            : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_statusMessage)),
                    ],
                  ),
                ),
              ),
            if (_devicesFromServer.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Найденные устройства',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ..._devicesFromServer.map((device) => ListTile(
                        leading: Icon(_getTypeIcon(device['mem'])),
                        title: Text(device['name'] ?? 'Без имени'),
                        subtitle: Text('ID: ${device['idd']}'),
                        dense: true,
                      )),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSyncing ? null : _syncDevices,
                          icon: _isSyncing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.add),
                          label: const Text('Добавить все устройства'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  IconData _getTypeIcon(String? mem) {
    switch (mem?.toUpperCase()) {
      case 'DAT':
        return Icons.thermostat;
      case 'LAMP':
        return Icons.lightbulb;
      case 'ROZ':
      case 'ROZAV':
        return Icons.power_settings_new;
      case 'RELE':
        return Icons.bolt;
      case 'TERMO1':
        return Icons.thermostat;
      case 'LED':
      case 'LED11':
        return Icons.lightbulb_outline;
      default:
        return Icons.devices;
    }
  }
}