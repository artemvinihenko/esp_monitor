enum DeviceType {
  dat,    // Датчик температуры и влажности
  lamp,   // Освещение (вкл/выкл)
  roz,    // Розетка (вкл/выкл)
  rele,   // Реле (вкл/выкл)
  termo1, // Термостат (температура + управление)
  led,    // LED лампа с регулировкой яркости
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
        return 'temperature';
      case DeviceType.led:
        return 'set';
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
        return '/termo1/set';
      case DeviceType.led:
        return '/lamp/set';
    }
  }

  bool get hasBrightness {
    return this == DeviceType.led;
  }

  bool get hasTargetTemperature {
    return this == DeviceType.termo1;
  }

  bool get hasStateOnly {
    return this == DeviceType.lamp || this == DeviceType.roz || this == DeviceType.rele;
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
        return 'datESP/$login/$mac/termo1';
      case DeviceType.led:
        return 'datESP/$login/$mac/led/set';
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
        return 'termo1/set';
      case DeviceType.led:
        return 'lamp/set';
    }
  }

}