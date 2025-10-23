import 'package:cloud_firestore/cloud_firestore.dart';

class ScheduleModel {
  final String id;
  final String name;
  final List<String> applianceIds; // appliances this schedule controls
  final List<String> days; // e.g. ['Mon','Tue']
  final String startTime; // 'HH:mm'
  final String endTime; // 'HH:mm'
  final bool enabled;

  ScheduleModel({
    required this.id,
    required this.name,
    required this.applianceIds,
    required this.days,
    required this.startTime,
    required this.endTime,
    required this.enabled,
  });

  factory ScheduleModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ScheduleModel(
      id: doc.id,
      name: data['name'] as String? ?? 'group_schedule',
      applianceIds: List<String>.from(data['applianceIds'] ?? []),
      days: List<String>.from(data['days'] ?? []),
      startTime: data['startTime'] as String? ?? '',
      endTime: data['endTime'] as String? ?? '',
      enabled: data['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'applianceIds': applianceIds,
      'days': days,
      'startTime': startTime,
      'endTime': endTime,
      'enabled': enabled,
    };
  }
}
