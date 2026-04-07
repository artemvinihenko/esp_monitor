import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  static const String _channelId = 'mqtt_notifications';
  static const String _channelName = 'MQTT Уведомления';
  static const String _channelDescription = 'Уведомления от MQTT устройств';

  static Future<void> init() async {
    // Настройки для Android
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // Настройки для iOS
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(settings);
    
    // Создаем канал для уведомлений (Android 8+)
    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.low,
      enableLights: false,
      enableVibration: false,
      playSound: false,
      showBadge: false,
    );
    
    await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }
  
  // Показать постоянное уведомление (ongoing)
  static Future<void> showOngoingNotification({
    required String title,
    required String content,
    int? value,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true, // Постоянное уведомление
      autoCancel: false, // Не удаляется при нажатии
      showWhen: true,
      usesChronometer: false,
      category: AndroidNotificationCategory.status,
    );
    
    const iosDetails = DarwinNotificationDetails();
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _notifications.show(
      0, // ID 0 - постоянное уведомление
      title,
      content,
      details,
    );
  }
  
  // Обновить уведомление с данными датчика
  static Future<void> updateNotification({
    required String deviceName,
    required String value,
    required String unit,
    required DateTime timestamp,
  }) async {
    final timeStr = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    
    await showOngoingNotification(
      title: '📊 IOT мониторинг',
      content: '$deviceName: $value$unit (обн: $timeStr)',
    );
  }
  
  // Удалить уведомление
  static Future<void> cancelNotification() async {
    await _notifications.cancel(0);
  }
}