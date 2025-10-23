import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:homesync/firebase_options.dart';
// import 'package:homesync/features/usage_data/show_usage_service.dart'; // not used
import 'package:homesync/usage.dart' show UsageService;
import 'package:homesync/scheduling_service.dart';

/// Initialize the background service
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onBackground,
    ),
  );
  service.startService();
}

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

/// Android + iOS foreground entry point
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

  // Handle Android service instance specific configurations
  if (service is AndroidServiceInstance) {
    // Handle when switching to foreground service
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    // Handle when switching to background service
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  // Handle when stopping the service
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Initialize the scheduling service
  await ApplianceSchedulingService.initService(
    auth: auth,
    firestore: firestore,
    usageService: usageService,
  );

  // Run the usage service logic
  usageService.run(auth: auth, firestore: firestore);
}