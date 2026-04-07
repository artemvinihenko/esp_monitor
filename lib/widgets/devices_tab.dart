import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import 'device_card.dart';

class DevicesTab extends StatelessWidget {
  const DevicesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.devices.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.devices, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Нет добавленных устройств',
                  style: TextStyle(fontSize: 18),
                ),
                SizedBox(height: 8),
                Text(
                  'Нажмите "Добавить" чтобы настроить новое устройство',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.refreshDevices(),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: provider.devices.length,
            itemBuilder: (context, index) {
              return DeviceCard(
                device: provider.devices[index],
                onDelete: () => _confirmDelete(context, provider, provider.devices[index]),
                onRefresh: () => provider.refreshDevices(),
                mqttManager: provider.mqttManager, // передаем для управления
              );
            },
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, DeviceProvider provider, device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить устройство'),
        content: Text('Удалить ${device.name} из списка?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              provider.removeDevice(device.mac);
              Navigator.pop(context);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }
}