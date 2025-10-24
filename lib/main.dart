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
import 'package:homesync/OptimizedDeviceHistoryScreen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:homesync/usage.dart' show UsageService;
import 'package:homesync/scheduling_service.dart';
import 'package:homesync/about.dart';
import 'package:homesync/helpscreen.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase.initializeApp()
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize notification system
  final notificationManager = NotificationManager();
  // Don't block app startup on potentially slow platform initialization.
  // Initialize in background and log failures — this keeps the UI responsive.
  Future(() async {
    try {
      await notificationManager.initialize();
    } catch (e, st) {
      debugPrint('Warning: notification init failed: $e');
      debugPrint('$st');
    }
  });

  // Initialize scheduling service for foreground runs if user is already signed in
  // Start scheduling service in background if a user is already signed in.
  Future(() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await ApplianceSchedulingService.initService(
          auth: FirebaseAuth.instance,
          firestore: FirebaseFirestore.instance,
          usageService: UsageService(),
        );
      }
    } catch (e, st) {
      // Non-fatal: log for debugging, do not block app start
      debugPrint('Warning: scheduling service init failed: $e');
      debugPrint('$st');
    }
  });

  // Also respond to auth state changes so that if the user signs in after app start
  // we initialize the scheduling service and listeners. This handles cases where
  // the app launched before authentication completed.
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user != null) {
      try {
        await ApplianceSchedulingService.initService(
          auth: FirebaseAuth.instance,
          firestore: FirebaseFirestore.instance,
          usageService: UsageService(),
        );
        debugPrint('Main: Scheduling service initialized after auth state change for ${user.uid}');
      } catch (e, st) {
        debugPrint('Main: scheduling init after auth change failed: $e');
        debugPrint('$st');
      }
    }
  });

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
        '/history': (context) => OptimizedDeviceHistoryScreen(),
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
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return Roomsinfo(roomItem: args ?? '');
        },
        '/schedule': (context) => Schedule(),
        '/deviceinfo': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          final applianceId = args?['applianceId'] as String? ?? '';
          final deviceName = args?['deviceName'] as String? ?? '';
          return DeviceInfoScreen(
            applianceId: applianceId,
            initialDeviceName: deviceName,
          );
        },
        '/editdevice': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          final applianceId = args?['applianceId'] as String? ?? '';
          return EditDeviceScreen(
            applianceId: applianceId,
          );
        },
        '/profile': (context) => ProfileScreen(),
        '/about': (context) => AboutScreen(),
        '/help': (context) => HelpScreen(),
         /* '/deviceusage': (context) {
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
          } */

          /* return DeviceUsage(
            userId: userId,
            applianceId: applianceId, */
      
      }
          );
  }
}
        /* },
      }, */
    /* );
  }
} */