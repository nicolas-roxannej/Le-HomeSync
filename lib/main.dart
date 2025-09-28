import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

// Firebase config
import 'firebase_options.dart';

// Screens
import 'package:homesync/welcome_screen.dart';
import 'package:homesync/signup_screen.dart';
import 'package:homesync/login_screen.dart';
import 'package:homesync/devices_screen.dart';
import 'package:homesync/forgot_password_screen.dart';
import 'package:homesync/homepage_screen.dart';
import 'package:homesync/rooms.dart';
import 'package:homesync/adddevices.dart';
import 'package:homesync/notification_screen.dart';
import 'package:homesync/notification_settings.dart';
import 'package:homesync/System_notif.dart';
import 'package:homesync/device_notif.dart';
import 'package:homesync/roomsinfo.dart';
import 'package:homesync/schedule.dart';
import 'package:homesync/deviceinfo.dart';
import 'package:homesync/editdevice.dart';
import 'package:homesync/profile_screen.dart';
import 'package:homesync/device_usage.dart';
import 'package:homesync/notification_manager.dart';
import 'package:homesync/notification_test_screen.dart';
import 'package:homesync/history.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Corrected spelling: Firebase.initializeApp()
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize notification system
  final notificationManager = NotificationManager();
  await notificationManager.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeSync',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => WelcomeScreen(),
        '/signup': (context) => SignUpScreen(),
        '/login': (context) => LoginScreen(),
        '/history': (context) => DeviceHistoryScreen(),
        '/forgot-password': (context) => ForgotPasswordScreen(),
        '/homepage': (context) => HomepageScreen(),
        '/devices': (context) => DevicesScreen(),
        '/rooms': (context) => Rooms(),
        '/adddevice': (context) => AddDeviceScreen(),
        '/notification': (context) => NotificationScreen(),
        '/notificationsettings': (context) => NotificationSettings(),
        '/systemnotif': (context) => SystemNotif(),
        '/devicenotif': (context) => DeviceNotif(),
        '/notificationtest': (context) => NotificationTestScreen(),
        '/roominfo': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as String;
          return Roomsinfo(roomItem: args);
        },
        '/schedule': (context) => Schedule(),
        '/deviceinfo': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return DeviceInfoScreen(
            applianceId: args['applianceId'] as String,
            initialDeviceName: args['deviceName'] as String,
          );
        },
        '/editdevice': (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return EditDeviceScreen(
            applianceId: args['applianceId'] as String,
          );
        },
        '/profile': (context) => ProfileScreen(),
        '/deviceusage': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, dynamic>?;

          final String userId =
              args?['userId'] as String? ?? "DEFAULT_USER_ID";
          final String applianceId =
              args?['applianceId'] as String? ?? "DEFAULT_APPLIANCE_ID";

          if (userId == "DEFAULT_USER_ID" ||
              applianceId == "DEFAULT_APPLIANCE_ID") {
            debugPrint(
                "⚠️ Warning: Navigating to /deviceusage without proper userId or applianceId arguments.");
          }

          return DeviceUsage(
            userId: userId,
            applianceId: applianceId,
          );
        },
      },
    );
  }
}
