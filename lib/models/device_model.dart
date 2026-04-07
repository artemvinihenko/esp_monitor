enum DeviceType {
  dat,    // Датчик температуры и влажности
  lamp,   // Освещение (вкл/выкл)
  roz,    // Розетка (вкл/выкл)
  rele,   // Реле (вкл/выкл)
  termo1, // Термостат (температура + управление)
  led,    // LED лампа с регулировкой яркости
  none,    // нераспознано
  sauna,  // Баня (сложное устройство)
}

extension DeviceTypeExtension on DeviceType {
  String get displayName {
    switch (this) {
      case DeviceType.dat:
        return 'Датчик (темп./влаж.)';
      case DeviceType.lamp:
        return 'Освещение';
      case DeviceType.roz:
        return 'Розетка';
      case DeviceType.rele:
        return 'Реле';
      case DeviceType.termo1:
        return 'Термостат';
      case DeviceType.led:
        return 'LED лампа';
      case DeviceType.none:
        return 'Неизвестное';
      case DeviceType.sauna:
        return 'Баня';
    }
  }

  String get icon {
    switch (this) {
      case DeviceType.dat:
        return '🌡️';
      case DeviceType.lamp:
        return '💡';
      case DeviceType.roz:
        return '🔌';
      case DeviceType.rele:
        return '⚡';
      case DeviceType.termo1:
        return '🌡️';
      case DeviceType.led:
        return '💡';
      case DeviceType.none:
        return 'X';
      case DeviceType.sauna:
        return '🧖';
    }
  }

  String get stateTopic {
    switch (this) {
      case DeviceType.dat:
        return 'temperature1';
      case DeviceType.lamp:
      case DeviceType.roz:
      case DeviceType.rele:
        return 'set';
      case DeviceType.termo1:
        return 'set';
      case DeviceType.led:
        return 'set';
     case DeviceType.none:
        return 'set';
     case DeviceType.sauna:
        return 'state';  
    }
  }

  String get controlTopic {
    switch (this) {
      case DeviceType.dat:
        return '';
      case DeviceType.lamp:
        return '/lamp/set';
      case DeviceType.roz:
        return '/socket/set';
      case DeviceType.rele:
        return '/rele/set';
      case DeviceType.termo1:
        return '/temper/set';
      case DeviceType.led:
        return '/lamp/set';
      case DeviceType.none:
        return '';
      case DeviceType.sauna:
        return '/set';
    }
  }

  bool get hasBrightness {
    return this == DeviceType.led;
  }

  bool get hasTargetTemperature {
    return this == DeviceType.termo1 || this == DeviceType.sauna;
  }

  bool get hasStateOnly {
    return this == DeviceType.lamp || this == DeviceType.roz || this == DeviceType.rele || 
           this == DeviceType.sauna;
  }

    bool get hasMeasurement {
    return  this == DeviceType.sauna;
  }
  
  bool get hasControl {
    return this == DeviceType.lamp || 
           this == DeviceType.roz || this == DeviceType.rele || 
           this == DeviceType.led || this == DeviceType.termo1 || 
           this == DeviceType.sauna;
  }

}

class DeviceModel {
  final String id;
  final String name;
  final String mac;
  final DeviceType type;
  final String ip;
  final String login;

  // Данные для датчиков
  double? temperature;
  double? humidity;

  // Данные для управляемых устройств
  bool? isOn;

  // Для LED лампы
  int? brightness; // 0-100

  // Для термостата
  double? targetTemperature;

  // Для бани (сауны)
  bool? steamGen;    // Парогенератор
  bool? fan;         // Вентилятор
  bool? light;       // Свет
  bool? heater;      // Каменка

  // Для розеток с измерением
  double? voltage;   // Напряжение (V)
  double? current;   // Ток (A)
  double? power;     // Мощность (W)

  int lastUpdate;
  bool isOnline;

  DeviceModel({
    required this.id,
    required this.name,
    required this.mac,
    required this.type,
    required this.ip,
    required this.login,
    this.temperature,
    this.humidity,
    this.isOn,
    this.brightness,
    this.targetTemperature,
    this.voltage,
    this.current,
    this.power,
    this.steamGen,
    this.fan,
    this.light,
    this.heater,
    this.lastUpdate = 0,
    this.isOnline = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'mac': mac,
      'type': type.name,
      'ip': ip,
      'login': login,
      'temperature': temperature,
      'humidity': humidity,
      'isOn': isOn,
      'brightness': brightness,
      'targetTemperature': targetTemperature,
      'voltage': voltage,
      'current': current,
      'power': power,
      'steamGen': steamGen,
      'fan': fan,
      'light': light,
      'heater': heater,
      'lastUpdate': lastUpdate,
      'isOnline': isOnline,
    };
  }

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] as String,
      name: json['name'] as String,
      mac: json['mac'] as String,
      type: DeviceType.values.firstWhere(
            (e) => e.name == json['type'],
        orElse: () => DeviceType.dat,
      ),
      ip: json['ip'] as String? ?? 'Неизвестно',
      login: json['login'] as String,
      temperature: json['temperature']?.toDouble(),
      humidity: json['humidity']?.toDouble(),
      isOn: json['isOn'] as bool?,
      brightness: json['brightness'] as int?,
      targetTemperature: json['targetTemperature']?.toDouble(),
      voltage: json['voltage']?.toDouble(),
      current: json['current']?.toDouble(),
      power: json['power']?.toDouble(),
      steamGen: json['steamGen'] as bool?,
      fan: json['fan'] as bool?,
      light: json['light'] as bool?,
      heater: json['heater'] as bool?,
      lastUpdate: json['lastUpdate'] as int? ?? 0,
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }

  DeviceModel copyWith({
    String? id,
    String? name,
    String? mac,
    DeviceType? type,
    String? ip,
    String? login,
    double? temperature,
    double? humidity,
    bool? isOn,
    int? brightness,
    double? targetTemperature,
    double? voltage,
    double? current,
    double? power,
    bool? steamGen,
    bool? fan,
    bool? light,
    bool? heater,
    int? lastUpdate,
    bool? isOnline,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      mac: mac ?? this.mac,
      type: type ?? this.type,
      ip: ip ?? this.ip,
      login: login ?? this.login,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      isOn: isOn ?? this.isOn,
      brightness: brightness ?? this.brightness,
      targetTemperature: targetTemperature ?? this.targetTemperature,
      voltage: voltage ?? this.voltage,
      current: current ?? this.current,
      power: power ?? this.power,
      steamGen: steamGen ?? this.steamGen,
      fan: fan ?? this.fan,
      light: light ?? this.light,
      heater: heater ?? this.heater,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  String getSubscribeTopic(String login) {
    switch (type) {
      case DeviceType.dat:
        return 'datESP/$login/$mac/temperature1';
      case DeviceType.lamp:
        return 'datESP/$login/$mac/lamp/set';
      case DeviceType.roz:
        return 'datESP/$login/$mac/socket/set';
      case DeviceType.rele:
        return 'datESP/$login/$mac/rele/set';
      case DeviceType.termo1:
        return 'datESP/$login/$mac/temper';
      case DeviceType.led:
        return 'datESP/$login/$mac/led/set';
      case DeviceType.none:
        return 'datESP/$login/$mac/temperature1';
      case DeviceType.sauna:
        return 'datESP/$login/$mac/state';

    }
  }

  String getHumidityTopic(String login) {
    if (type == DeviceType.dat) {
      return 'datESP/$login/$mac/hum1';
    }
    return '';
  }

  String? getControlTopic(String login) {
    if (controlTopic.isEmpty) return null;
    return 'datESP/$login/$mac/$controlTopic';
  }

  String get controlTopic {
    switch (type) {
      case DeviceType.dat:
        return '';
      case DeviceType.lamp:
        return 'lamp/set';
      case DeviceType.roz:
        return 'socket/set';
      case DeviceType.rele:
        return 'rele/set';
      case DeviceType.termo1:
        return 'temper/set';
      case DeviceType.led:
        return 'lamp/set';
      case DeviceType.none:
        return '';
      case DeviceType.sauna:
        return '/set';
    }
  }

}
//  новый класс для хранения точки данных
class DataPoint {
  final DateTime timestamp;
  final double value;

  DataPoint({
    required this.timestamp,
    required this.value,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'value': value,
    };
  }

  factory DataPoint.fromJson(Map<String, dynamic> json) {
    return DataPoint(
      timestamp: DateTime.parse(json['timestamp']),
      value: json['value'],
    );
  }
}