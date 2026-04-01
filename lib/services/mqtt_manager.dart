import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/device_model.dart';

typedef OnDataReceived = void Function(String mac, String type, double value);
typedef OnConnectionStateChanged = void Function(bool connected);

class MqttManager {
  static const String broker = 'iot-mqtt.ru';
  static const int port = 1883;

  MqttServerClient? _client;
  final OnDataReceived onDataReceived;
  final OnConnectionStateChanged? onConnectionStateChanged;
  bool _isConnected = false;

  // Храним активные подписки
  final Set<String> _activeSubscriptions = {};
  String? _currentLogin;

  // Таймер для периодического опроса
  Timer? _pollingTimer;
  // Список устройств для опроса
  List<DeviceModel> _currentDevices = [];

  MqttManager({
    required this.onDataReceived,
    this.onConnectionStateChanged,
  });

  bool get isConnected => _isConnected;

  Future<bool> connect(String login, String password, List<DeviceModel> devices) async {
    // Сохраняем список устройств
    _currentDevices = devices;

    // Если уже подключены с тем же логином, просто обновляем подписки
    if (_isConnected && _currentLogin == login && _client != null) {
      print('Already connected with same login, updating subscriptions');
      await updateSubscriptions(devices, login);
      return true;
    }

    // Если подключены с другим логином, отключаемся
    if (_isConnected) {
      await disconnect();
    }

    _currentLogin = login;
    _client = MqttServerClient(broker, 'flutter_app_${DateTime.now().millisecondsSinceEpoch}');
    _client!.port = port;
    _client!.keepAlivePeriod = 60;
    _client!.onDisconnected = _onDisconnected;
    _client!.onSubscribed = _onSubscribed;
    _client!.onUnsubscribed = _onUnsubscribed;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(_client!.clientIdentifier)
        .withWillTopic('will')
        .withWillMessage('Disconnected')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    _client!.connectionMessage = connMessage;

    try {
      print('Connecting to MQTT broker: $broker:$port');
      await _client!.connect(login, password);
      _isConnected = true;
      print('MQTT connected successfully');
      onConnectionStateChanged?.call(true);

      _client!.updates!.listen(_onMessage);

      // Подписываемся на устройства
      await subscribeToDevices(devices, login);

      // Запускаем периодический опрос
      _startPolling(devices, login);

      return true;
    } catch (e) {
      print('MQTT connection failed: $e');
      _isConnected = false;
      onConnectionStateChanged?.call(false);
      return false;
    }
  }

  // Запуск периодического опроса устройств (раз в минуту)
  void _startPolling(List<DeviceModel> devices, String login) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (_isConnected && _client != null) {
        print('=== POLLING DEVICES (every 60 sec) ===');
        for (final device in devices) {
          _sendGetRequest(login, device.mac);
        }
      }
    });
  }

  // Отправка запроса на получение данных
  void _sendGetRequest(String login, String mac) {
    if (!_isConnected || _client == null) return;

    final topic = 'datESP/$login/$mac/get';
    final payload = '{"get":"1"}';

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      print('Sent GET request to $topic');
    } catch (e) {
      print('Failed to send GET request: $e');
    }
  }

  // Публичный метод для ручного опроса конкретного устройства
  void pollDevice(String login, String mac) {
    if (!_isConnected || _client == null) {
      print('Cannot poll device - not connected');
      return;
    }
    _sendGetRequest(login, mac);
  }

  // Публичный метод для обновления подписок
  Future<void> updateSubscriptions(List<DeviceModel> devices, String login) async {
    if (!_isConnected || _client == null) {
      print('Cannot update subscriptions - not connected');
      return;
    }
    // Обновляем список устройств
    _currentDevices = devices;
    // Получаем все нужные топики для подписки
    final requiredTopics = <String>{};
    for (final device in devices)
    {
      switch (device.type) {
        case DeviceType.dat:
          requiredTopics.add('datESP/$login/${device.mac}/temperature1');
          requiredTopics.add('datESP/$login/${device.mac}/hum1');
            break;
        case DeviceType.lamp:
          requiredTopics.add('datESP/$login/${device.mac}/lamp/set');
           break;
        case DeviceType.roz:
          requiredTopics.add('datESP/$login/${device.mac}/socket/set');
           break;
        case DeviceType.rele:
          requiredTopics.add('datESP/$login/${device.mac}/rele/set');
           break;
        case DeviceType.termo1:
          requiredTopics.add('datESP/$login/${device.mac}/temper/set');
          requiredTopics.add('datESP/$login/${device.mac}/temperature1');
          requiredTopics.add('datESP/$login/${device.mac}/temperature');
          requiredTopics.add('datESP/$login/${device.mac}/hum1');
           break;
        case DeviceType.led:
          requiredTopics.add('datESP/$login/${device.mac}/led/set');
           break;
      }

    }

    // Находим топики, которые нужно добавить
    final topicsToAdd = requiredTopics.difference(_activeSubscriptions);

    // Находим топики, которые нужно удалить
    final topicsToRemove = _activeSubscriptions.difference(requiredTopics);

    // Отписываемся от ненужных топиков
    for (final topic in topicsToRemove) {
      if (_client != null && _isConnected) {
        print('Unsubscribing from: $topic');
         _client!.unsubscribe(topic);
        _activeSubscriptions.remove(topic);
      }
    }

    // Подписываемся на новые топики
    for (final topic in topicsToAdd) {
      if (_client != null && _isConnected) {
        print('Subscribing to: $topic');
        await _client!.subscribe(topic, MqttQos.atLeastOnce);
        _activeSubscriptions.add(topic);
      }
    }

    print('Subscriptions updated: ${_activeSubscriptions.length} active');

    // Перезапускаем опрос с новыми устройствами
    _pollingTimer?.cancel();
    _startPolling(devices, login);
  }

  // Приватный метод для первоначальной подписки
  Future<void> subscribeToDevices(List<DeviceModel> devices, String login) async {
    if (!_isConnected || _client == null) {
      print('Cannot subscribe - not connected');
      return;
    }

    // Очищаем старые подписки
    if (_activeSubscriptions.isNotEmpty) {
      for (final topic in _activeSubscriptions.toList()) {
        if (_client != null && _isConnected) {
          print('Unsubscribing from old topic: $topic');
           _client!.unsubscribe(topic);
        }
      }
      _activeSubscriptions.clear();
    }

    // Подписываемся на новые
    for (final device in devices)
    {
      final topics;
      switch (device.type) {
        case DeviceType.dat:
           topics = [
            'datESP/$login/${device.mac}/temperature1',
            'datESP/$login/${device.mac}/hum1',
          ]; break;
        case DeviceType.lamp:
           topics = [
            'datESP/$login/${device.mac}/lamp/set',
          ];break;
        case DeviceType.roz:
           topics = [
            'datESP/$login/${device.mac}/socket/set',
          ];break;
        case DeviceType.rele:
           topics = [
            'datESP/$login/${device.mac}/rele/set',
          ];break;
        case DeviceType.termo1:
           topics = [
            'datESP/$login/${device.mac}/temperature',
             'datESP/$login/${device.mac}/temperature1',
            'datESP/$login/${device.mac}/hum1',
            'datESP/$login/${device.mac}/temper/set',
          ];break;
        case DeviceType.led:
           topics = [
            'datESP/$login/${device.mac}/led/set',
          ];break;
      }

      for (final topic in topics)
      {
        if (!_activeSubscriptions.contains(topic))
        {
          print('Subscribing to: $topic');
           _client!.subscribe(topic, MqttQos.atLeastOnce);
          _activeSubscriptions.add(topic);
        }
      }

    }

    print('Subscribed to ${_activeSubscriptions.length} topics');
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final message in messages) {
      final topic = message.topic;
      final payload = message.payload as MqttPublishMessage;
      final data = MqttPublishPayload.bytesToStringAsString(payload.payload.message);

      print('MQTT message received: $topic -> $data');

      final parts = topic.split('/');
      if (parts.length >= 4) {
        final mac = parts[2];
        final sensorType = parts[3];

        try {
          final jsonData = jsonDecode(data);

          // Обработка датчиков температуры/влажности
          if (sensorType == 'temperature1' && jsonData.containsKey('TDS')) {
            final value = jsonData['TDS'].toDouble();
            onDataReceived(mac, 'temperature', value);
          }
          else if (sensorType == 'temperature1' && jsonData.containsKey('temperature')) {
            final value = jsonData['temperature'].toDouble();
            onDataReceived(mac, 'temperature', value);
          }
          else if (sensorType == 'hum1' && jsonData.containsKey('humidity')) {
            final value = jsonData['humidity'].toDouble();
            onDataReceived(mac, 'humidity', value);
          }
          else if (sensorType == 'hum1' && jsonData.containsKey('hum')) {
            final value = jsonData['hum'].toDouble();
            onDataReceived(mac, 'humidity', value);
          }
          // Обработка термостата (текущая температура)
          else if (sensorType == 'temperature' && jsonData.containsKey('temperature')) {
            final value = jsonData['temperature'].toDouble();
            onDataReceived(mac, 'temperature', value);
          }
          // Обработка состояния (вкл/выкл) для ламп, розеток, реле, LED
          else if ((sensorType == 'rele' || sensorType == 'socket' || sensorType == 'lamp' || sensorType == 'led') && jsonData.containsKey('state'))
          {
            final state = jsonData['state'] as String;
            final isOn = state.toUpperCase() == 'ON';
            onDataReceived(mac, 'state', isOn ? 1.0 : 0.0);

            // Если есть яркость для LED
            if (jsonData.containsKey('value') && jsonData['value'] is num) {
              final brightness = (jsonData['value'] as num).toInt();
              onDataReceived(mac, 'brightness', brightness.toDouble());
            }

            // Если есть яркость для LED
            if (jsonData.containsKey('temperature') && jsonData['temperature'] is num) {
              final targetTemp = (jsonData['temperature'] as num).toDouble();
              onDataReceived(mac, 'target_temperature', targetTemp);
            }

          }

        } catch (e) {
          print('Failed to parse JSON: $data, error: $e');
        }
      }
    }
  }

  void _onDisconnected() {
    print('MQTT disconnected');
    _isConnected = false;
    _activeSubscriptions.clear();
    _pollingTimer?.cancel();
    onConnectionStateChanged?.call(false);
  }

  void _onSubscribed(String topic) {
    print('Subscribed to: $topic');
  }

  void _onUnsubscribed(String? topic) {
    print('Unsubscribed from: $topic');
    if (topic != null) {
      _activeSubscriptions.remove(topic);
    }
  }

  void ping() {
    if (_client != null && _isConnected) {
      try {
        _client!.pingCallback;
        print('Ping sent');
      } catch (e) {
        print('Ping failed: $e');
      }
    }
  }

  void publish(String topic, String payload) {
    if (!_isConnected || _client == null) {
      print('Cannot publish - not connected');
      return;
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      print('Published to $topic: $payload');
    } catch (e) {
      print('Publish failed: $e');
    }
  }

  Future<void> disconnect() async {
    _pollingTimer?.cancel();
    if (_client != null) {
      try {
        // Отписываемся от всех топиков перед отключением
        for (final topic in _activeSubscriptions.toList()) {
          if (_client != null && _isConnected) {
             _client!.unsubscribe(topic);
          }
        }
        _activeSubscriptions.clear();

         _client!.disconnect();
        print('MQTT disconnected manually');
      } catch (e) {
        print('Error disconnecting: $e');
      }
    }
    _isConnected = false;
    _currentLogin = null;
    _currentDevices = [];
    onConnectionStateChanged?.call(false);
  }
}