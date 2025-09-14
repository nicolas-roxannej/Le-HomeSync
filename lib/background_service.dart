import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:homesync/firebase_options.dart';
import 'package:homesync/features/usage_data/show_usage_service.dart';
import 'package:homesync/usage.dart' show UsageService;

/// Android + iOS background entry point
@pragma('vm:entry-point')
Future<bool> onBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  return true;
}

class ServiceInstance {
  Future<void> setAsForegroundService() async {}
  Future<void> setAsBackgroundService() async {}
  
  on(String s) {}
  
  Future<void> stopSelf() async {}
}

/// Android + iOS background entry point
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final UsageService usageService = UsageService();

  // Handle when switching to foreground service
  service.on('setAsForeground').listen((event) async {
    await service.setAsForegroundService();
  });

  // Handle when switching to background service
  service.on('setAsBackground').listen((event) async {
    await service.setAsBackgroundService();
  });

  // Handle when stopping the service
  service.on('stopService').listen((event) async {
    await service.stopSelf();
  });

  // Example: call your usage service logic here
  usageService.run(auth: auth, firestore: firestore);
}
