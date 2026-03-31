import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device_model.dart';
import '../providers/device_provider.dart';
import '../services/preferences_manager.dart';

class ManualAddScreen extends StatefulWidget {
  final VoidCallback? onDeviceAdded;

  const ManualAddScreen({super.key, this.onDeviceAdded});

  @override
  State<ManualAddScreen> createState() => _ManualAddScreenState();
}

class _ManualAddScreenState extends State<ManualAddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _macController = TextEditingController();
  final _ipController = TextEditingController();

  DeviceType _selectedType = DeviceType.dat;

  final _prefs = PreferencesManager();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _macController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _addDevice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final credentials = await _prefs.getMqttCredentials();
      final login = credentials.login;
      final password = credentials.password;

      if (login.isEmpty || password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сначала сохраните MQTT настройки на вкладке "Автонастройка"'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final mqttMac = _macController.text.trim().toUpperCase();
      final deviceName = _nameController.text.trim();
      final deviceIp = _ipController.text.trim().isEmpty ? 'Неизвестно' : _ipController.text.trim();

      final device = DeviceModel(
        id: mqttMac,
        name: deviceName,
        mac: mqttMac,
        type: _selectedType,
        ip: deviceIp,
        login: login,
      );

      // Проверяем, не существует ли уже такое устройство
      final existingDevices = await _prefs.getDevices();
      final exists = existingDevices.any((d) => d.mac == device.mac);

      if (exists) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Устройство с таким MAC уже существует!'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      await _prefs.addDevice(device);

      if (context.mounted) {
        final provider = Provider.of<DeviceProvider>(context, listen: false);
        await provider.addDevice(device);
      }

      widget.onDeviceAdded?.call();

      // Очищаем форму
      _nameController.clear();
      _macController.clear();
      _ipController.clear();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Устройство "$deviceName" добавлено!\nТип: ${_selectedType.displayName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ручное добавление устройства',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Добавьте устройство, которое уже настроено и подключено к MQTT серверу.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 24),

          // Тип устройства
          DropdownButtonFormField<DeviceType>(
            value: _selectedType,
            decoration: const InputDecoration(
              labelText: 'Тип устройства *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.category),
            ),
            items: DeviceType.values.map((type) {
              return DropdownMenuItem(
                value: type,
                child: Row(
                  children: [
                    Text(type.icon),
                    const SizedBox(width: 8),
                    Text(type.displayName),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedType = value;
                });
              }
            },
          ),
          const SizedBox(height: 16),

          // Имя устройства
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Имя устройства *',
              hintText: 'Датчик в гостиной',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.devices),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Введите имя устройства';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // MAC адрес
          TextFormField(
            controller: _macController,
            decoration: const InputDecoration(
              labelText: 'MAC адрес устройства *',
              hintText: 'MC82B961BEBCE',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.settings_ethernet),
              helperText: 'Вводится в формате M + 12 шестнадцатеричных символов',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Введите MAC адрес';
              }
              if (value.length < 13) {
                return 'MAC адрес должен начинаться с M и содержать 12 символов после него';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // IP адрес (опционально)
          TextFormField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'IP адрес (опционально)',
              hintText: '192.168.1.100',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dns),
            ),
          ),
          const SizedBox(height: 24),

          // Информация о формате
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Информация о топиках:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_selectedType == DeviceType.dat) ...[
                  const Text('• Датчик (температура/влажность)', style: TextStyle(fontSize: 12)),
                  Text(
                    '  datESP/{логин}/${_macController}/temperature1',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                  Text(
                    '  datESP/{логин}/${_macController}/hum1',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ] else ...[
                  Text(
                    _selectedType == DeviceType.lamp ? '• Освещение' : '• Розетка',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '  Топик состояния: datESP/{логин}/${_macController}/state',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                  Text(
                    '  Топик управления: datESP/{логин}/${_macController}/state/set',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const Text(
                    '  Формат команды: {"state":"ON"} или {"state":"OFF"}',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _addDevice,
                icon: const Icon(Icons.add),
                label: const Text('Добавить устройство'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}