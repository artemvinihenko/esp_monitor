import 'package:flutter/material.dart';
import '../services/preferences_manager.dart';
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
  final _prefs = PreferencesManager();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);  // 3 вкладки
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    final credentials = await _prefs.getMqttCredentials();
    _loginController.text = credentials.login;
    _passwordController.text = credentials.password;
  }

  Future<void> _saveMqttCredentials() async {
    final login = _loginController.text.trim();
    final password = _passwordController.text.trim();

    if (login.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите логин MQTT')),
      );
      return;
    }

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите пароль MQTT')),
      );
      return;
    }

    await _prefs.saveMqttCredentials(login, password);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('MQTT настройки сохранены')),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // MQTT настройки вверху
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MQTT настройки',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _loginController,
                decoration: const InputDecoration(
                  labelText: 'Логин MQTT',
                  hintText: 'zavr',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Пароль MQTT',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveMqttCredentials,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Сохранить MQTT настройки'),
                ),
              ),
            ],
          ),
        ),

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
                                final login = _loginController.text.trim();
                                final password = _passwordController.text.trim();
                                if (login.isEmpty || password.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Сначала сохраните MQTT настройки')),
                                  );
                                  return;
                                }
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