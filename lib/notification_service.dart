// Forwarding shim to the new implementation
export 'package:homesync/notification_service_new.dart';
import 'dart:convert';
import 'package:homesync/notification_service_new.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final NotificationServiceNew _impl = NotificationServiceNew();

  Future<void> initialize() => _impl.initialize();
  // extraData allows callers to include additional structured fields (e.g., applianceId)
  Future<void> showDeviceNotification({required String deviceName, required String status, required String room, Map<String, dynamic>? extraData}) {
    final Map<String, dynamic> payloadMap = {
      'deviceName': deviceName,
      'status': status,
      'room': room,
    };
    if (extraData != null) payloadMap.addAll(extraData);
    return _impl.showNotification(title: 'Device Update', body: '$deviceName in $room is now $status', type: NotificationType.device, payload: jsonEncode(payloadMap));
  }
  Future<void> showEnergyNotification({required String message, required double usage}) => _impl.showNotification(title: 'Energy Alert', body: '$message (${usage.toStringAsFixed(1)} kWh)', type: NotificationType.energy);
  Future<void> showSystemNotification({required String title, required String message}) => _impl.showNotification(title: title, body: message, type: NotificationType.system);
  Future<void> showAlertNotification({required String title, required String message}) => _impl.showNotification(title: title, body: message, type: NotificationType.alert);
}
