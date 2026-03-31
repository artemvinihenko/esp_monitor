import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../widgets/devices_tab.dart';
import '../widgets/add_device_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('ESP8266 Monitor'),
            actions: [
              // Кнопка переподключения MQTT
              IconButton(
                icon: const Icon(Icons.sync),
                tooltip: 'Переподключить MQTT',
                onPressed: () {
                  provider.reconnectMqtt();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Попытка переподключения к MQTT...'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              // Индикатор MQTT подключения
              Tooltip(
                message: provider.isMqttConnected
                    ? 'MQTT подключен'
                    : 'MQTT отключен. Проверьте интернет и настройки',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: provider.isMqttConnected
                        ? Colors.green.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: provider.isMqttConnected ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'MQTT',
                        style: TextStyle(
                          fontSize: 12,
                          color: provider.isMqttConnected ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.devices), text: 'Устройства'),
                Tab(icon: Icon(Icons.add), text: 'Добавить'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: const [
              DevicesTab(),
              AddDeviceTab(),
            ],
          ),
        );
      },
    );
  }
}