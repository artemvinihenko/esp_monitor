import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/device_model.dart';
import '../services/mqtt_manager.dart';
import '../screens/chart_screen.dart';
import '../screens/sauna_screen.dart';

class DeviceCard extends StatefulWidget {
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
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {
  // Локальные переменные для мгновенного обновления UI
  double? _localTargetTemp;
  bool? _localIsOn;
  int? _localBrightness;

  @override
  void initState() {
    super.initState();
    _initLocalValues();
  }

  void _initLocalValues() {
    _localTargetTemp = widget.device.targetTemperature?.toDouble() ?? 20;
    _localIsOn = widget.device.isOn ?? false;
    _localBrightness = widget.device.brightness ?? 0;
  }

  @override
  void didUpdateWidget(DeviceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Обновляем локальные данные при изменении device (например, при получении MQTT)
    if (widget.device.targetTemperature != oldWidget.device.targetTemperature) {
      _localTargetTemp = widget.device.targetTemperature?.toDouble() ?? 20;
    }
    if (widget.device.isOn != oldWidget.device.isOn) {
      _localIsOn = widget.device.isOn ?? false;
    }
    if (widget.device.brightness != oldWidget.device.brightness) {
      _localBrightness = widget.device.brightness ?? 0;
    }
  }

  void _showChartDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return DefaultTabController(
            length: widget.device.type == DeviceType.dat ? 2 : 1,
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                // Заголовок
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.device.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                // Вкладки для датчика (температура и влажность)
                if (widget.device.type == DeviceType.dat)
                  const TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.thermostat), text: 'Температура'),
                      Tab(icon: Icon(Icons.water_drop), text: 'Влажность'),
                    ],
                  ),
                const SizedBox(height: 8),
                // График
                Expanded(
                  child: widget.device.type == DeviceType.dat
                      ? TabBarView(
                    children: [
                      ChartScreen(
                        device: widget.device,
                        dataType: 'temperature',
                      ),
                      ChartScreen(
                        device: widget.device,
                        dataType: 'humidity',
                      ),
                    ],
                  )
                      : ChartScreen(
                    device: widget.device,
                    dataType: 'temperature',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lastUpdate = widget.device.lastUpdate > 0
        ? DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(widget.device.lastUpdate))
        : 'нет данных';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Верхняя строка: иконка, имя, статус
            Row(
              children: [
                Text(
                  '${widget.device.type.icon} ',
                  style: const TextStyle(fontSize: 18),
                ),
                Expanded(
                  child: Text(
                    widget.device.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.device.isOnline ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.device.isOnline ? '● Онлайн' : '○ Офлайн',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),

            // MAC адрес
            Text(
              widget.device.mac,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // Отображение данных в зависимости от типа устройства
            if (widget.device.type == DeviceType.dat) ...[
              _buildCompactSensorCard(),
            ] else if (widget.device.type == DeviceType.termo1) ...[
              _buildCompactTermostatCard(),
            ] else if (widget.device.type == DeviceType.led) ...[
              _buildCompactLedCard(),
            ] else if (widget.device.type == DeviceType.lamp ||
                widget.device.type == DeviceType.rele) ...[
              _buildCompactSwitchCard(),
            ]else if(widget.device.type == DeviceType.roz)...[
              _buildSocketCard(),
            ]else if (widget.device.type == DeviceType.sauna) ...[
               _buildSaunaCard(),
             ],
            const SizedBox(height: 8),

            // Нижняя строка: время обновления и кнопки
            Row(
              children: [
                Text(
                  'обн: $lastUpdate',
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
                const Spacer(),
                // Кнопка графика (только для датчиков и термостата)
                if (widget.device.type == DeviceType.dat || widget.device.type == DeviceType.termo1)
                  IconButton(
                    icon: const Icon(Icons.show_chart, size: 18),
                    onPressed: () {
                      _showChartDialog(context);
                    },
                    tooltip: 'График',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () {
                    if (widget.mqttManager != null && widget.device.login.isNotEmpty) {
                      widget.mqttManager!.pollDevice(widget.device.login, widget.device.mac);
                    }
                  },
                  tooltip: 'Запросить данные',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  onPressed: widget.onDelete,
                  tooltip: 'Удалить',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

///PU04
Widget _buildSaunaCard() {
  final isOn = widget.device.isOn ?? false;
  
  return GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SaunaScreen(
            device: widget.device,
            mqttManager: widget.mqttManager,
          ),
        ),
      );
    },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: isOn ? Colors.orange.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Температура
          Expanded(
            child: Column(
              children: [
                const Icon(Icons.thermostat, size: 20, color: Colors.orange),
                const SizedBox(height: 4),
                Text(
                  widget.device.temperature != null
                      ? '${widget.device.temperature!.toStringAsFixed(1)}°C'
                      : '---°C',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Влажность
          Expanded(
            child: Column(
              children: [
                const Icon(Icons.water_drop, size: 20, color: Colors.blue),
                const SizedBox(height: 4),
                Text(
                  widget.device.humidity != null
                      ? '${widget.device.humidity!.toStringAsFixed(1)}%'
                      : '---%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Кнопка вкл/выкл
         // Switch(
         //   value: isOn,
         //   onChanged: (value) {
         //     _sendCommand({'state': value ? 'ON' : 'OFF'});
         //   },
        //    activeColor: Colors.orange,
        //  ),
         // const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    ),
  );
}
/// 
  // Компактная карточка датчика
  Widget _buildCompactSensorCard() {
    return Row(
      children: [
        Expanded(
          child: _CompactSensorValue(
            value: widget.device.temperature != null
                ? '${widget.device.temperature!.toStringAsFixed(1)}°C'
                : '---°C',
            icon: Icons.thermostat,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CompactSensorValue(
            value: widget.device.humidity != null
                ? '${widget.device.humidity!.toStringAsFixed(1)}%'
                : '---%',
            icon: Icons.water_drop,
          ),
        ),
      ],
    );
  }

  // Компактная карточка переключателя
  Widget _buildCompactSwitchCard() {
    return Row(
      children: [
        Expanded(
          child: _CompactSwitchControl(
            title: widget.device.type.displayName,
            isOn: widget.device.isOn ?? false,
            onToggle: (value) => _sendCommand({'state': value ? 'ON' : 'OFF'}),
            icon: _getControlIcon(),
          ),
        ),
      ],
    );
  }

  // Компактная LED карточка
  Widget _buildCompactLedCard() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CompactSwitchControl(
                title: widget.device.type.displayName,
                isOn: widget.device.isOn ?? false,
                onToggle: (value) => _sendCommand({'state': value ? 'ON' : 'OFF'}),
                icon: Icons.lightbulb,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.brightness_6, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: (_localBrightness ?? widget.device.brightness ?? 0).toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                label: '${_localBrightness ?? widget.device.brightness ?? 0}%',
                onChanged: (value) {
                  setState(() {
                    _localBrightness = value.toInt();
                  });
                },
                onChangeEnd: (value) {
                  final newValue = value.toInt();
                  _sendCommand({
                    'state': (widget.device.isOn ?? false) ? 'ON' : 'OFF',
                    'value': newValue,
                  });
                },
              ),
            ),
            Text(
              '${_localBrightness ?? widget.device.brightness ?? 0}%',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  // Компактная термостат карточка
  Widget _buildCompactTermostatCard() {
    return Column(
      children: [
        // Строка с текущей и установленной температурой + кнопка
        Row(
          children: [
            Expanded(
              child: _CompactSensorValue(
                title: ' ',
                value: widget.device.temperature != null
                    ? '${widget.device.temperature!.toStringAsFixed(1)}°C'
                    : '---°C',
                icon: Icons.thermostat,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactSensorValue(
                title: 'Уст',
                value: '${(_localTargetTemp ?? widget.device.targetTemperature ?? 20).toInt()}°C',
                icon: Icons.settings,
              ),
            ),
            // Кнопка вкл/выкл
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (_localIsOn ?? widget.device.isOn ?? false) ? Colors.green.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    (_localIsOn ?? widget.device.isOn ?? false) ? Icons.power_settings_new : Icons.power_off,
                    size: 16,
                    color: (_localIsOn ?? widget.device.isOn ?? false) ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: _localIsOn ?? widget.device.isOn ?? false,
                    onChanged: (value) {
                      setState(() {
                        _localIsOn = value;
                      });
                      _sendCommand({
                        'state': value ? 'ON' : 'OFF',
                        'value': (_localTargetTemp ?? widget.device.targetTemperature ?? 20).toInt(),
                      });
                    },
                    activeThumbColor: Colors.green,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Слайдер для установки температуры
        Row(
          children: [
            const Icon(Icons.thermostat, size: 16, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                value: _localTargetTemp ?? widget.device.targetTemperature?.toDouble() ?? 20,
                min: 0,
                max: 120,
                divisions: 120,
                label: '${(_localTargetTemp ?? widget.device.targetTemperature ?? 20).toInt()}°C',
                onChanged: (value) {
                  setState(() {
                    _localTargetTemp = value;
                  });
                },
                onChangeEnd: (value) {
                  final newValue = value.toInt();
                  _sendCommand({
                    'state': (_localIsOn ?? widget.device.isOn ?? false) ? 'ON' : 'OFF',
                    'value': newValue,
                  });
                },
              ),
            ),
            Text(
              '${(_localTargetTemp ?? widget.device.targetTemperature ?? 20).toInt()}°C',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }
/////////////////////
  // Карточка розетки с измерением
  Widget _buildSocketCard() {
    return Column(
      children: [
        // Кнопка вкл/выкл (только для rozv)
        if (widget.device.type == DeviceType.roz) ...[
          _CompactSwitchControl(
            title: 'Розетка',
            isOn: widget.device.isOn ?? false,
            onToggle: (value) => _sendCommand({'state': value ? 'ON' : 'OFF'}),
            icon: Icons.power_settings_new,
          ),
          const SizedBox(height: 8),
        ],

        // Показания тока и напряжения
        Row(
          children: [
            Expanded(
              child: _CompactSensorValue(
                title: 'Напряжение',
                value: widget.device.voltage != null
                    ? '${widget.device.voltage!.toStringAsFixed(1)}V'
                    : '---V',
                icon: Icons.flash_on,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _CompactSensorValue(
                title: 'Ток',
                value: widget.device.current != null
                    ? '${widget.device.current!.toStringAsFixed(2)}A'
                    : '---A',
                icon: Icons.electric_bolt,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _CompactSensorValue(
                title: 'Мощность',
                value: widget.device.power != null
                    ? '${widget.device.power!.toStringAsFixed(0)}W'
                    : '---W',
                icon: Icons.speed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(), // Пустой для выравнивания
            ),
          ],
        ),
      ],
    );
  }

 ////////////////////
  IconData _getControlIcon() {
    switch (widget.device.type) {
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
    final topic = widget.device.getControlTopic(widget.device.login);
    if (topic == null) {
      debugPrint('No control topic for device type: ${widget.device.type}');
      return;
    }

    final payload = jsonEncode(command);
    debugPrint('Sending command to $topic: $payload');
    widget.mqttManager?.publish(topic, payload);
  }

}

// Компактный виджет для отображения значения датчика
class _CompactSensorValue extends StatelessWidget {
  final String value;
  final IconData icon;
  final String? title;

  const _CompactSensorValue({
    required this.value,
    required this.icon,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: Colors.blue),
          const SizedBox(width: 4),
          if (title != null) ...[
            Text(
              '$title: ',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// Компактный виджет для управления переключателем
class _CompactSwitchControl extends StatelessWidget {
  final String title;
  final bool isOn;
  final ValueChanged<bool> onToggle;
  final IconData icon;

  const _CompactSwitchControl({
    required this.title,
    required this.isOn,
    required this.onToggle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: isOn ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: isOn ? Colors.green : Colors.grey),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          Switch(
            value: isOn,
            onChanged: onToggle,
            activeThumbColor: Colors.green,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

