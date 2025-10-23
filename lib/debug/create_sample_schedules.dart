import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Developer helper to create sample schedules for quick testing.
/// This file does not run automatically. Call these functions from a debug route
/// or from a temporary `main()` when testing.

Future<void> createSamplePerApplianceSchedule({
  required String applianceId,
  required String relayKey,
  required double wattage,
  required String startTime, // e.g. "14:00"
  required String endTime, // e.g. "15:00"
  required List<String> days, // e.g. ["Mon","Tue","Wed"]
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not signed in');

  final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('appliances').doc(applianceId);

  await docRef.set({
    'relay': relayKey,
    'wattage': wattage,
    'startTime': startTime,
    'endTime': endTime,
    'days': days,
    'applianceStatus': 'OFF',
  }, SetOptions(merge: true));
}

Future<void> createSampleGroupSchedule({
  required String scheduleId,
  required String name,
  required List<String> applianceIds,
  required String startTime,
  required String endTime,
  required List<String> days,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not signed in');

  final groupRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('schedules').doc(scheduleId);
  await groupRef.set({
    'name': name,
    'applianceIds': applianceIds,
    'startTime': startTime,
    'endTime': endTime,
    'days': days,
    'enabled': true,
  }, SetOptions(merge: true));
}

Future<void> clearSampleGroupSchedule({
  required String scheduleId,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not signed in');
  final groupRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('schedules').doc(scheduleId);
  await groupRef.delete();
}
