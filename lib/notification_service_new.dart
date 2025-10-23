import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Notification types
enum NotificationType { device, system, energy, alert }

class NotificationServiceNew {
  static final NotificationServiceNew _instance = NotificationServiceNew._internal();
  factory NotificationServiceNew() => _instance;
  NotificationServiceNew._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // Channel ids
  static const String _deviceChannelId = 'device_notifications';
  static const String _systemChannelId = 'system_notifications';
  static const String _energyChannelId = 'energy_notifications';
  static const String _alertChannelId = 'alert_notifications';

  Future<void> initialize() async {
    await _initializeLocalNotifications(); // Initialize local notification plugin and channels
    await _initializeFirebaseMessaging(); // Request FCM permissions and set up handlers
    // Only run user-scoped migration/cleanup when there is a signed-in user.
    // Background isolates (FCM background handler) do not have an authenticated
    // Firebase user and running these queries there causes permission-denied errors
    // (Firestore rules require request.auth.uid == userId). Skip them when not signed in.
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await _cleanupStaleLocalEntries(); // Ensure local cache does not point to deleted docs
        // Migrate and archive old malformed notifications so UI doesn't show useless records
        await _migrateAndArchiveOldNotifications(); // Archive bad/legacy records
        // Archive notifications that are older than 24 hours (best-effort client-side cleanup)
        await _archiveOldNotifications(); // Archive old/expired notifications so they won't surface
      } else {
        if (kDebugMode) print('NotificationServiceNew: No signed-in user; skipping notification migration/cleanup.');
      }
    } catch (e) {
      // Non-fatal: ensure initialization continues even if maintenance tasks fail
      print('NotificationServiceNew: Skipping migration/cleanup due to error or missing auth: $e');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    if (kIsWeb) return;

    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings, onDidReceiveNotificationResponse: _onNotificationTapped);
    await _createNotificationChannels();
  }

  Future<void> _createNotificationChannels() async {
    if (kIsWeb) return;
    final channels = [
      AndroidNotificationChannel(_deviceChannelId, 'Device Notifications', description: 'Device updates', importance: Importance.high),
      AndroidNotificationChannel(_energyChannelId, 'Energy Notifications', description: 'Energy alerts', importance: Importance.high),
      AndroidNotificationChannel(_systemChannelId, 'System Notifications', description: 'System messages', importance: Importance.defaultImportance),
      AndroidNotificationChannel(_alertChannelId, 'Alert Notifications', description: 'Critical alerts', importance: Importance.max),
    ];

    for (var c in channels) {
      await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(c);
    }
  }

  Future<void> _initializeFirebaseMessaging() async {
    final settings = await _firebaseMessaging.requestPermission(alert: true, badge: true, sound: true);
    print('FCM permission: ${settings.authorizationStatus}');

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedAppFromMessage);

    final token = await _firebaseMessaging.getToken();
    print('FCM token: $token');
  }

  // Foreground: show local notification and persist once.
  void _onForegroundMessage(RemoteMessage msg) {
    final notif = msg.notification;
    if (notif == null) return;
    final type = _getTypeFromData(msg.data);
    // Show + persist once
    showNotification(title: notif.title ?? 'HomeSync', body: notif.body ?? '', type: type, payload: jsonEncode(msg.data));
  }

  void _onOpenedAppFromMessage(RemoteMessage msg) {
    // Handle navigation if necessary
    print('User opened app from notification: ${msg.messageId}');
  }

  Future<void> showNotification({required String title, required String body, NotificationType type = NotificationType.system, String? payload}) async {
    // Respect preferences (quick check)
    final prefs = await SharedPreferences.getInstance();
    if (!_prefAllows(type, prefs)) return;

    if (kIsWeb) {
      // Web: just store locally
      await _storeLocalNotification(title, body, type, docId: null);
      return;
    }

    final channelId = _channelFor(type);
    final androidDetails = AndroidNotificationDetails(channelId, channelId, importance: Importance.high, priority: Priority.high);
    final details = NotificationDetails(android: androidDetails);

    // Persist to Firestore and get docId
    final docId = await _persistNotificationToFirestore(title, body, type, payload != null ? {'payload': payload} : null);

    // Store locally with docId so UI can delete
    await _storeLocalNotification(title, body, type, docId: docId);

    // Use stable numeric id per channel so notifications replace previous ones
    final nid = _numericIdFor(type);

    // Compose payload to include the firestore doc id so tap events can map
    final payloadMap = <String, dynamic>{};
    if (payload != null) {
      try {
        payloadMap.addAll(jsonDecode(payload));
      } catch (_) {
        payloadMap['payload_raw'] = payload;
      }
    }
    if (docId != null) payloadMap['docId'] = docId;

    await _localNotifications.show(nid, title, body, details, payload: jsonEncode(payloadMap));
  }

  // Persist and return docId
  Future<String?> _persistNotificationToFirestore(String title, String body, NotificationType type, [Map<String, dynamic>? data]) async {
    try {
      final f = FirebaseFirestore.instance;
      final user = FirebaseAuth.instance.currentUser;
  // Normalize and enrich notification document so UI and archiving have stable fields
  final Map<String, dynamic> doc = {
    'title': title, // notification title
    'body': body, // notification body
    'type': type.toString().split('.').last, // friendly type string
    'data': data ?? {}, // raw payload data if provided
    'createdAt': FieldValue.serverTimestamp(), // server timestamp when created
    'isRead': false, // default unread state
    'archived': false, // default archived flag
    // compute an expiresAt client-side (approximate) so client cleanup can use it
    'expiresAt': Timestamp.fromDate(DateTime.now().toUtc().add(Duration(hours: 24))),
  };

  // If caller supplied a structured payload inside `data['payload']`, try to extract
  // common fields so the notifications collection has top-level device/action fields
  try {
    if (data != null && data.containsKey('payload') && data['payload'] is String) {
      final payloadStr = data['payload'] as String;
      final parsed = jsonDecode(payloadStr);
        if (parsed is Map<String, dynamic>) {
          if (parsed.containsKey('deviceName')) doc['deviceName'] = parsed['deviceName']; // top-level device name
          if (parsed.containsKey('status')) doc['action'] = parsed['status']; // top-level action/status
          if (parsed.containsKey('applianceId')) doc['applianceId'] = parsed['applianceId']; // top-level appliance id
          if (parsed.containsKey('room')) doc['room'] = parsed['room']; // top-level room
          if (parsed.containsKey('triggerType')) doc['triggerType'] = parsed['triggerType']; // trigger origin (manual/scheduled/remote)
        }
    } else if (data != null && data.isNotEmpty) {
      // Some callers pass structured data directly
      if (data.containsKey('deviceName')) doc['deviceName'] = data['deviceName']; // surface deviceName top-level
      if (data.containsKey('action')) doc['action'] = data['action']; // surface action top-level
      if (data.containsKey('applianceId')) doc['applianceId'] = data['applianceId']; // surface applianceId top-level
      if (data.containsKey('room')) doc['room'] = data['room']; // surface room top-level
      if (data.containsKey('triggerType')) doc['triggerType'] = data['triggerType']; // surface triggerType top-level
    }
  } catch (e) {
    // Non-fatal: parsing payload failed, but we still persist the basic doc
    print('NotificationService: Warning: failed to parse payload for enrichment: $e');
  }
      if (user != null) {
        final ref = f.collection('users').doc(user.uid).collection('notifications').doc(); // user-scoped notifications
        await ref.set(doc); // persist enriched notification
        return ref.id; // return Firestore doc id for OS payload mapping
      } else {
        final ref = f.collection('notifications').doc(); // fallback top-level collection
        await ref.set(doc); // persist fallback notification
        return ref.id; // return fallback doc id
      }
    } catch (e) {
      print('Failed to persist notification: $e');
      return null;
    }
  }

  // Archive notifications older than 24 hours (client-side best-effort). This helps
  // keep the user's notifications collection tidy when Cloud Functions are not available.
  Future<void> _archiveOldNotifications() async {
    try {
      final user = FirebaseAuth.instance.currentUser; // get current signed-in user
      if (user == null) return; // nothing to do if no user
      final f = FirebaseFirestore.instance; // firestore instance
      final cutoff = Timestamp.fromDate(DateTime.now().toUtc().subtract(Duration(hours: 24))); // cutoff timestamp
      final q = await f.collection('users').doc(user.uid).collection('notifications')
          .where('createdAt', isLessThan: cutoff) // find old docs
          .where('archived', isEqualTo: false) // only those not archived
          .get(); // execute query
      for (var d in q.docs) {
        try {
          await d.reference.set({'archived': true}, SetOptions(merge: true)); // mark archived
        } catch (e) {
          print('NotificationServiceNew: Failed to archive old notification ${d.id}: $e');
        }
      }
    } catch (e) {
      print('NotificationServiceNew: _archiveOldNotifications failed: $e');
    }
  }

  Future<void> _storeLocalNotification(String title, String body, NotificationType type, {String? docId}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('local_notifications') ?? [];
    final entry = jsonEncode({'id': DateTime.now().millisecondsSinceEpoch.toString(), 'title': title, 'body': body, 'time': DateTime.now().toIso8601String(), 'type': type.toString(), 'docId': docId ?? ''});
    list.insert(0, entry);
    if (list.length > 50) list.removeRange(50, list.length);
    await prefs.setStringList('local_notifications', list);
  }

  bool _prefAllows(NotificationType type, SharedPreferences prefs) {
    switch (type) {
      case NotificationType.device:
        return prefs.getBool('device_notifications_enabled') ?? true;
      case NotificationType.energy:
        return prefs.getBool('energy_notifications_enabled') ?? true;
      case NotificationType.alert:
        return prefs.getBool('alert_notifications_enabled') ?? true;
      default:
        return prefs.getBool('system_notifications_enabled') ?? true;
    }
  }

  NotificationType _getTypeFromData(Map<String, dynamic> data) {
    final t = (data['type'] ?? 'system').toString().toLowerCase();
    switch (t) {
      case 'device':
        return NotificationType.device;
      case 'energy':
        return NotificationType.energy;
      case 'alert':
        return NotificationType.alert;
      default:
        return NotificationType.system;
    }
  }

  String _channelFor(NotificationType t) {
    switch (t) {
      case NotificationType.device:
        return _deviceChannelId;
      case NotificationType.energy:
        return _energyChannelId;
      case NotificationType.alert:
        return _alertChannelId;
      default:
        return _systemChannelId;
    }
  }

  int _numericIdFor(NotificationType t) {
    switch (t) {
      case NotificationType.device:
        return 1000;
      case NotificationType.energy:
        return 2000;
      case NotificationType.alert:
        return 4000;
      default:
        return 3000;
    }
  }

  void _onNotificationTapped(NotificationResponse resp) {
    print('Notification tapped: ${resp.payload}');
    try {
      if (resp.payload != null && resp.payload!.isNotEmpty) {
        final m = jsonDecode(resp.payload!);
        final docId = (m is Map && m['docId'] != null) ? m['docId'].toString() : null;
        if (docId != null && docId.isNotEmpty) {
          // Store last tapped doc id for quick UI navigation/highlighting
          SharedPreferences.getInstance().then((prefs) => prefs.setString('last_tapped_notification_docid', docId));
        }
      }
    } catch (e) {
      print('Error handling tap payload: $e');
    }
  }

  Future<void> _cleanupStaleLocalEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('local_notifications') ?? [];
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final f = FirebaseFirestore.instance;
      final remaining = <String>[];
      for (var s in list) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          final docId = (m['docId'] as String?) ?? '';
          if (docId.isEmpty) {
            remaining.add(s);
            continue;
          }
          final doc = await f.collection('users').doc(user.uid).collection('notifications').doc(docId).get();
          if (doc.exists) remaining.add(s);
        } catch (e) {
          remaining.add(s);
        }
      }
      await prefs.setStringList('local_notifications', remaining);
    } catch (e) {
      print('Cleanup error: $e');
    }
  }

  // Migration: archive old notifications that do not contain a deviceName or have empty body/data
  // This is safe to run repeatedly and will only mark items as archived. It preserves existing records while
  // preventing the UI from showing malformed, untappable notifications.
  Future<void> _migrateAndArchiveOldNotifications() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final f = FirebaseFirestore.instance;
      final snap = await f.collection('users').doc(user.uid).collection('notifications').get();
      for (var d in snap.docs) {
        try {
          final data = d.data();
          final body = (data['body'] as String?) ?? '';
          final mapData = (data['data'] as Map<String, dynamic>?) ?? {};
          final containsDeviceName = (mapData['deviceName'] != null) || body.contains('Device');
          // Archive notifications missing deviceName and with empty body
          if ((body.trim().isEmpty || !containsDeviceName) && (data['archived'] != true)) {
            await d.reference.set({'archived': true}, SetOptions(merge: true));
          }
        } catch (e) {
          print('NotificationServiceNew: Failed to process notification doc ${d.id}: $e');
        }
      }
    } catch (e) {
      print('NotificationServiceNew: Migration failed: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  try {
    // Compose normalized notification document for background FCM messages
    final title = message.notification?.title ?? message.data['title'] ?? 'HomeSync'; // title fallback
    final body = message.notification?.body ?? message.data['body'] ?? ''; // body fallback
    final typeStr = (message.data['type'] ?? 'system').toString(); // type string
    final userId = message.data['userId'] as String?; // optional user id provided by server
    final triggerType = message.data['triggerType'] as String?; // optional triggerType from server
    final applianceId = message.data['applianceId'] as String?; // optional appliance id
    final f = FirebaseFirestore.instance; // firestore instance

    final doc = {
      'title': title,
      'body': body,
      'type': typeStr,
      'data': message.data, // keep raw payload
      'createdAt': FieldValue.serverTimestamp(), // use new createdAt field
      'isRead': false, // unread by default
      'archived': false, // default not archived
    };

    // Include optional fields for better indexing and UI
    if (applianceId != null && applianceId.isNotEmpty) doc['applianceId'] = applianceId;
    if (triggerType != null && triggerType.isNotEmpty) doc['triggerType'] = triggerType;

    // Persist under user-scoped collection if we have userId, otherwise fallback to top-level
    if (userId != null && userId.isNotEmpty) {
      await f.collection('users').doc(userId).collection('notifications').add(doc);
    } else {
      await f.collection('notifications').add(doc);
    }
  } catch (e) {
    print('Background persist error: $e');
  }
}
