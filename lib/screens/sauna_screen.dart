import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/device_model.dart';
import '../services/mqtt_manager.dart';

class SaunaScreen extends StatefulWidget {
  final DeviceModel device;
  final MqttManager? mqttManager;
  
  const SaunaScreen({
    super.key,
    required this.device,
    required this.mqttManager,
  });

  @override
  State<SaunaScreen> createState() => _SaunaScreenState();
}

class _SaunaScreenState extends State<SaunaScreen> with SingleTickerProviderStateMixin {
  late double _targetTemperature;
  bool _isOn = false;
  bool _steamGen = false;
  bool _fan = false;
  bool _light = false;
  bool _heater = false;
  
  Timer? _steamTimer;
  Timer? _steamParticleTimer;
  final List<_SteamCloud> _steamClouds = [];
  final Random _random = Random();
  
  // Константы для кругового регулятора
  static const double _minTemp = 30;
  static const double _maxTemp = 120;
  static const double _startAngleDeg = 150;  // 150° - начальная точка (нижняя левая)
  static const double _sweepAngleDeg = 240;   // 240° - полный диапазон (от 30°C до 120°C)
  
  @override
  void initState() {
    super.initState();
    _loadCurrentState();
  }
  
  void _loadCurrentState() {
    setState(() {
      _isOn = widget.device.isOn ?? false;
      _targetTemperature = widget.device.targetTemperature ?? 60;
      _steamGen = widget.device.steamGen ?? false;
      _fan = widget.device.fan ?? false;
      _light = widget.device.light ?? false;
      _heater = widget.device.heater ?? false;
    });
  }
  
  void _startSteamAnimation() {
    _steamTimer?.cancel();
    _steamParticleTimer?.cancel();
    
    _steamTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (mounted && _steamGen) {
        setState(() {
          _steamClouds.add(_SteamCloud(
            left: _random.nextDouble() * 100 + 50,
            top: 300,
            size: _random.nextDouble() * 80 + 60,
            opacity: 0.5,
            speed: _random.nextDouble() * 2.5 + 0.8,
          ));
        });
      }
    });
    
    _steamParticleTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (mounted && _steamGen) {
        setState(() {
          for (int i = _steamClouds.length - 1; i >= 0; i--) {
            final cloud = _steamClouds[i];
            cloud.top -= cloud.speed;
            cloud.opacity -= 0.008;
            cloud.size += 2;
            
            if (cloud.top < -100 || cloud.opacity <= 0) {
              _steamClouds.removeAt(i);
            }
            
            if (_fan) {
              cloud.left += 1.5;
            }
          }
        });
      }
    });
  }
  
  void _stopSteamAnimation() {
    _steamTimer?.cancel();
    _steamParticleTimer?.cancel();
    setState(() {
      _steamClouds.clear();
    });
  }
  
  void _sendCommand(Map<String, dynamic> command) {
    final topic = widget.device.getControlTopic(widget.device.login);
    if (topic == null) return;
    
    final payload = jsonEncode(command);
    debugPrint('Sending command to $topic: $payload');
    widget.mqttManager?.publish(topic, payload);
  }
  
  void _togglePower() {
    setState(() {
      _isOn = !_isOn;
      
      if (!_isOn) {
        if (_steamGen) {
          _steamGen = false;
          _stopSteamAnimation();
          _sendCommand({'steamGen': 'OFF'});
        }
        if (_fan) {
          _fan = false;
          _sendCommand({'fan': 'OFF'});
        }
        if (_heater) {
          _heater = false;
          _sendCommand({'heater': 'OFF'});
        }
      }
    });
    _sendCommand({'state': _isOn ? 'ON' : 'OFF'});
  }
  
  void _toggleSteamGen() {
    setState(() {
      _steamGen = !_steamGen;
      if (_steamGen) {
        _startSteamAnimation();
      } else {
        _stopSteamAnimation();
      }
    });
    _sendCommand({'steamGen': _steamGen ? 'ON' : 'OFF'});
  }
  
  void _toggleFan() {
    setState(() {
      _fan = !_fan;
    });
    _sendCommand({'fan': _fan ? 'ON' : 'OFF'});
  }
  
  void _toggleLight() {
    setState(() {
      _light = !_light;
    });
    _sendCommand({'light': _light ? 'ON' : 'OFF'});
  }
  
  void _toggleHeater() {
    setState(() {
      _heater = !_heater;
    });
    _sendCommand({'heater': _heater ? 'ON' : 'OFF'});
  }
  
  void _updateTemperature(double temp) {
    setState(() {
      _targetTemperature = temp.clamp(_minTemp, _maxTemp);
    });
    _sendCommand({'targetTemperature': _targetTemperature.toInt()});
  }
  
  // Преобразование температуры в угол (0°C = 150°, 120°C = 150°+240°=390°)
  double _temperatureToAngle(double temp) {
    return _startAngleDeg + ((temp - _minTemp) / (_maxTemp - _minTemp)) * _sweepAngleDeg;
  }
  
  // Преобразование угла в температуру
  double _angleToTemperature(double angleDeg) {
    double relativeAngle = angleDeg - _startAngleDeg;
    if (relativeAngle < 0) relativeAngle += 360;
    if (relativeAngle > _sweepAngleDeg) relativeAngle = _sweepAngleDeg;
    return _minTemp + (relativeAngle / _sweepAngleDeg) * (_maxTemp - _minTemp);
  }
  
  @override
  void dispose() {
    _steamTimer?.cancel();
    _steamParticleTimer?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        backgroundColor: Colors.brown.shade700,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _light ? Colors.amber.shade200 : Colors.brown.shade900,
              Colors.brown.shade800,
              Colors.brown.shade700,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Анимация пара
              if (_steamGen)
                ..._steamClouds.map((cloud) => Positioned(
                  left: cloud.left,
                  top: cloud.top,
                  child: Opacity(
                    opacity: cloud.opacity,
                    child: Container(
                      width: cloud.size,
                      height: cloud.size,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withOpacity(0.4),
                            Colors.white.withOpacity(0.1),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                )),
              
              // Основной контент
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _InfoCard(
                            title: 'Температура',
                            value: widget.device.temperature != null
                                ? '${widget.device.temperature!.toStringAsFixed(1)}°C'
                                : '---°C',
                            icon: Icons.thermostat,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _InfoCard(
                            title: 'Влажность',
                            value: widget.device.humidity != null
                                ? '${widget.device.humidity!.toStringAsFixed(1)}%'
                                : '---%',
                            icon: Icons.water_drop,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Круговой термостат
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = constraints.biggest.width;
                          final radius = size * 0.35;
                          final angleDeg = _temperatureToAngle(_targetTemperature);
                          final center = Offset(size / 2, size / 2);
                          
                          return SizedBox(
                            width: size,
                            height: size,
                            child: GestureDetector(
                              onPanUpdate: (details) {
                                if (!_isOn) return;
                                
                                final localPos = details.localPosition;
                                final dx = localPos.dx - center.dx;
                                final dy = localPos.dy - center.dy;
                                final distance = sqrt(dx * dx + dy * dy);
                                
                                if (distance > radius - 30 && distance < radius + 30) {
                                  double rad = atan2(dy, dx);
                                  double angleDegRaw = rad * 180 / pi;
                                  if (angleDegRaw < 0) angleDegRaw += 360;
                                  
                                  // Проверяем попадание в диапазон
                                  if (angleDegRaw >= _startAngleDeg && 
                                      angleDegRaw <= _startAngleDeg + _sweepAngleDeg) {
                                    final newTemp = _angleToTemperature(angleDegRaw);
                                    _updateTemperature(newTemp);
                                  }
                                }
                              },
                              child: CustomPaint(
                                painter: _CircularSliderPainter(
                                  angleDeg: angleDeg,
                                  startAngleDeg: _startAngleDeg,
                                  sweepAngleDeg: _sweepAngleDeg,
                                  isOn: _isOn,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _targetTemperature.toInt().toString(),
                                        style: TextStyle(
                                          fontSize: 48,
                                          fontWeight: FontWeight.bold,
                                          color: _isOn ? Colors.orange : Colors.grey,
                                        ),
                                      ),
                                      const Text(
                                        '°C',
                                        style: TextStyle(fontSize: 16, color: Colors.white70),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Установка',
                                        style: TextStyle(fontSize: 12, color: Colors.white54),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  
                  // Панель управления
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.brown.shade900,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    child: Column(
                      children: [
                        _CompactControlButton(
                          title: 'Баня',
                          icon: Icons.power_settings_new,
                          isOn: _isOn,
                          onToggle: _togglePower,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _CompactControlButton(
                                title: 'Пар',
                                icon: Icons.cloud_queue,
                                isOn: _steamGen,
                                onToggle: _toggleSteamGen,
                                color: Colors.cyan,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactControlButton(
                                title: 'Вент',
                                icon: Icons.air,
                                isOn: _fan,
                                onToggle: _toggleFan,
                                color: Colors.lightBlue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactControlButton(
                                title: 'Свет',
                                icon: Icons.lightbulb,
                                isOn: _light,
                                onToggle: _toggleLight,
                                color: Colors.yellow,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactControlButton(
                                title: 'Камень',
                                icon: Icons.whatshot,
                                isOn: _heater,
                                onToggle: _toggleHeater,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SteamCloud {
  double left;
  double top;
  double size;
  double opacity;
  double speed;
  
  _SteamCloud({
    required this.left,
    required this.top,
    required this.size,
    required this.opacity,
    required this.speed,
  });
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  
  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}

class _CircularSliderPainter extends CustomPainter {
  final double angleDeg;
  final double startAngleDeg;
  final double sweepAngleDeg;
  final bool isOn;
  
  _CircularSliderPainter({
    required this.angleDeg,
    required this.startAngleDeg,
    required this.sweepAngleDeg,
    required this.isOn,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;
    
    final startAngleRad = startAngleDeg * pi / 180;
    final sweepAngleRad = sweepAngleDeg * pi / 180;
    
    // Фоновая дуга
    final backgroundPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngleRad,
      sweepAngleRad,
      false,
      backgroundPaint,
    );
    
    if (isOn) {
      // Активная дуга с градиентом
      final colors = [
        Colors.blue,
        Colors.green,
        Colors.yellow,
        Colors.orange,
        Colors.red,
      ];
      
      final shader = SweepGradient(
        center: Alignment.center,
        colors: colors,
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
      
      final activePaint = Paint()
        ..shader = shader
        ..strokeWidth = 14
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      
      final activeSweepRad = (angleDeg - startAngleDeg) * pi / 180;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngleRad,
        activeSweepRad,
        false,
        activePaint,
      );
      
      // Ручка
      final handleAngleRad = angleDeg * pi / 180;
      final handleOffset = Offset(
        center.dx + radius * cos(handleAngleRad),
        center.dy + radius * sin(handleAngleRad),
      );
      
      canvas.drawCircle(handleOffset, 14, Paint()..color = Colors.black26);
      canvas.drawCircle(handleOffset, 12, Paint()..color = Colors.white);
      canvas.drawCircle(handleOffset, 8, Paint()..color = Colors.orange);
    }
  }
  
  @override
  bool shouldRepaint(covariant _CircularSliderPainter oldDelegate) {
    return oldDelegate.angleDeg != angleDeg || oldDelegate.isOn != isOn;
  }
}

class _CompactControlButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isOn;
  final VoidCallback onToggle;
  final Color color;
  
  const _CompactControlButton({
    required this.title,
    required this.icon,
    required this.isOn,
    required this.onToggle,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isOn ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isOn ? color : Colors.white24, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: isOn ? color : Colors.white54),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 11, color: isOn ? Colors.white : Colors.white54)),
            const SizedBox(height: 2),
            Container(
              width: 30,
              height: 16,
              decoration: BoxDecoration(
                color: isOn ? color : Colors.white24,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  isOn ? 'ON' : 'OFF',
                  style: TextStyle(fontSize: 8, color: isOn ? Colors.white : Colors.white70),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}