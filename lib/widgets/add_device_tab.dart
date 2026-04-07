import 'package:flutter/material.dart';
import '../screens/smart_config_screen.dart';
import '../screens/manual_add_screen.dart';
import '../screens/qr_add_screen.dart';

class AddDeviceTab extends StatefulWidget {
  const AddDeviceTab({super.key});

  @override
  State<AddDeviceTab> createState() => _AddDeviceTabState();
}

class _AddDeviceTabState extends State<AddDeviceTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);  // 3 вкладки
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Вкладки для добавления устройств
        Expanded(
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.wifi_tethering), text: 'Автонастройка'),
                  Tab(icon: Icon(Icons.qr_code_scanner), text: 'QR-код'),
                  Tab(icon: Icon(Icons.edit_note), text: 'Ручное добавление'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Автоматическая настройка
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'Автоматическая настройка нового устройства',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Для настройки нового устройства нажмите кнопку ниже. '
                                'Убедитесь, что устройство включено и находится в режиме SmartConfig.',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SmartConfigScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.wifi_tethering),
                              label: const Text('Настроить новое устройство'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
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
                                    'Убедитесь, что устройство в режиме SmartConfig. '
                                        'Для этого удерживайте кнопку на нем более 10 секунд '
                                        'для сброса настроек до заводских',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // QR-код сканирование
                    const QRAddScreen(),

                    // Ручное добавление
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: ManualAddScreen(
                        onDeviceAdded: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Устройство добавлено!')),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}