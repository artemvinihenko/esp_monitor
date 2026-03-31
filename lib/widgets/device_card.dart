import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/device_model.dart';
import '../services/mqtt_manager.dart';

class DeviceCard extends StatelessWidget {
  final DeviceModel device;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;
  final MqttManager? mqttManager;

  const DeviceCard({
    super.key,
    required this.device,
    required this.onDelete,
    required this.onRefresh,
    this.mqttManager,
  });

  @override
  Widget build(BuildContext context) {
    final lastUpdate = device.lastUpdate > 0
        ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(device.lastUpdate))
        : 'нет данных';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${device.type.icon} ',
                  style: const TextStyle(fontSize: 20),
                ),
                Expanded(
                  child: Text(
                    device.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: device.isOnline ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    device.isOnline ? '● Онлайн' : '○ Офлайн',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              device.mac,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            // Отображение данных в зависимости от типа устройства
            if (device.type == DeviceType.dat) ...[
              _buildSensorCard(),
            ] else if (device.type == DeviceType.termo1) ...[
              _buildTermostatCard(),
            ] else if (device.type == DeviceType.led) ...[
              _buildLedCard(),
            ]  else if (device.type == DeviceType.lamp) ...[
              _buildSwitchCard(),
            ] else if (device.type == DeviceType.roz) ...[
              _buildSwitchCard(),
            ] else ...[
              _buildSwitchCard(),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'обн: $lastUpdate',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    // Отправляем запрос на получение данных
                    if (mqttManager != null && device.login.isNotEmpty) {
                      mqttManager!.pollDevice(device.login, device.mac);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Запрос данных...'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  tooltip: 'Обновить',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: onDelete,
                  tooltip: 'Удалить',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorCard() {
    return Row(
      children: [
        Expanded(
          child: _SensorCard(
            title: 'Температура',
            value: device.temperature != null
                ? '${device.temperature!.toStringAsFixed(1)}°C'
                : '---°C',
            icon: Icons.thermostat,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _SensorCard(
            title: 'Влажность',
            value: device.humidity != null
                ? '${device.humidity!.toStringAsFixed(1)}%'
                : '---%',
            icon: Icons.water_drop,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchCard() {
    return Center(
      child: _ControlCard(
        title: device.type.displayName,
        isOn: device.isOn ?? false,
        onToggle: (value) => _sendCommand({'state': value ? 'ON' : 'OFF'}),
        icon: _getControlIcon(),
      ),
    );
  }///end rele lamp roz

  Widget _buildLedCard() {
    return Column(
      children: [
        _ControlCard(
          title: device.type.displayName,
          isOn: device.isOn ?? false,
          onToggle: (value) => _sendCommand({'state': value ? 'ON' : 'OFF'}),
          icon: Icons.lightbulb,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.brightness_6, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: (device.brightness ?? 0).toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                label: '${device.brightness ?? 0}%',
                onChanged: (value) {
                  _sendCommand({
                    'state': (device.isOn ?? false) ? 'ON' : 'OFF',
                    'value': value.toInt(),
                  });
                },
              ),
            ),
            Text('${device.brightness ?? 0}%'),
          ],
        ),
      ],
    );
  }///end led lamp

  Widget _buildTermostatCard() {
    return Column(
      children: [
        _SensorCard(
          title: 'Текущая температура',
          value: device.temperature != null
              ? '${device.temperature!.toStringAsFixed(1)}°C'
              : '---°C',
          icon: Icons.thermostat,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.settings, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: device.targetTemperature ?? 20.0,
                min: 5,
                max: 35,
                divisions: 60,
                label: '${device.targetTemperature ?? 20}°C',
                onChanged: (value) {
                  _sendCommand({
                    'state': (device.isOn ?? false) ? 'ON' : 'OFF',
                    'value': value.toInt(),
                  });
                },
              ),
            ),
            Text('${device.targetTemperature ?? 20}°C'),
          ],
        ),
      ],
    );
  }////end termo1

  IconData _getControlIcon() {
    switch (device.type) {
      case DeviceType.lamp:
        return Icons.lightbulb;
      case DeviceType.roz:
        return Icons.power_settings_new;
      case DeviceType.rele:
        return Icons.bolt;
      default:
        return Icons.power_settings_new;
    }
  }

  void _sendCommand(Map<String, dynamic> command) {
    final topic = device.getControlTopic(device.login);
    if (topic == null) {
      print('No control topic for device type: ${device.type}');
      return;
    }

    final payload = jsonEncode(command);
    print('Sending command to $topic: $payload');
    mqttManager?.publish(topic, payload);
  }
}

// Остальные классы остаются без изменений
class _SensorCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _SensorCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 24, color: Colors.blue),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _ControlCard extends StatelessWidget {
  final String title;
  final bool isOn;
  final ValueChanged<bool> onToggle;
  final IconData icon;

  const _ControlCard({
    required this.title,
    required this.isOn,
    required this.onToggle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOn ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 40,
            color: isOn ? Colors.green : Colors.grey,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Switch(
            value: isOn,
            onChanged: onToggle,
            activeColor: Colors.green,
          ),
          Text(
            isOn ? 'ВКЛЮЧЕНО' : 'ВЫКЛЮЧЕНО',
            style: TextStyle(
              fontSize: 12,
              color: isOn ? Colors.green : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
