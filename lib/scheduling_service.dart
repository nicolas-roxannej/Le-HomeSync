import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart'; // For TimeOfDay
import 'package:flutter/foundation.dart';
import 'package:homesync/usage.dart'; // Assuming UsageService is here
import 'package:intl/intl.dart'; // For date formatting (day of week)
import 'models/schedule_model.dart';
import 'package:homesync/notification_manager.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:homesync/services/relay_state_service.dart';
import 'package:homesync/databaseservice.dart';

class ApplianceSchedulingService {
  // NOTE (ESP32 integration):
  // The ESP32 firmware listens to documents at `users/{uid}/relay_states/{relayKey}`.
  // Each relay document is expected to contain at least the following fields:
  //   - state: int (1 = ON, 0 = OFF)
  //   - lastUpdated: Firestore timestamp
  //   - irControlled: bool (if true, the relay is controlled via IR and may be ignored by direct toggle logic)
  //   - wattage: double (optional, used for usage calculations)
  // Optional helpful metadata we write from the scheduler to aid debugging and routing:
  //   - source: string (e.g., 'scheduler', 'ui', 'manual')
  //   - applianceId: string (the appliance document id that this relay corresponds to)
  // The ESP32 should act on changes to `state` and may use `source` or `applianceId` for logging or filtering.
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UsageService _usageService;
  final DatabaseService _dbService = DatabaseService();

  Timer? _periodicTimer;
  List<Map<String, dynamic>> _activeSchedules = [];
  List<ScheduleModel> _groupSchedules = [];
  final Map<String, DateTime> _manualOffOverrides = {}; // applianceId -> overrideExpiryTime
  final Map<String, DateTime> _manualOnOverrides = {}; // applianceId -> overrideExpiryTime for manual ON

  // To store appliance data including wattage and relay for handleApplianceToggle
  final Map<String, Map<String, dynamic>> _applianceDetailsCache = {};
  StreamSubscription<QuerySnapshot>? _appliancesSub;
  StreamSubscription<QuerySnapshot>? _groupSchedulesSub;
  StreamSubscription<DocumentSnapshot>? _masterPowerSub;

  bool _masterPowerEnabled = true;

  static ApplianceSchedulingService? _instance;

  // Private constructor
  ApplianceSchedulingService._({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required UsageService usageService,
  })  : _auth = auth,
        _firestore = firestore,
        _usageService = usageService;

  // Static getter for the instance
  static ApplianceSchedulingService get instance {
    if (_instance == null) {
      throw Exception("ApplianceSchedulingService not initialized. Call initService() first.");
    }
    return _instance!;
  }

  // Static method to initialize the service
  static Future<void> initService({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required UsageService usageService,
  }) async {
    if (_instance == null) {
      _instance = ApplianceSchedulingService._(
        auth: auth,
        firestore: firestore,
        usageService: usageService,
      );
      await _instance!.initialize();
    } else {
      // Optionally, re-initialize or just ensure it's running if already created
      // For now, we assume it's initialized once.
      print("SchedulingService: Already initialized.");
    }
  }

  Future<void> initialize() async {
    tz.initializeTimeZones();
    // This is now an instance method called by initService
    final user = _auth.currentUser;
    if (user == null) {
      print("SchedulingService: No authenticated user. Instance cannot complete initialization.");
      return;
    }
    // Setup realtime listener for appliances to maintain a local cache and keep schedule decisions fast
    try {
      final appliancesColl = _firestore.collection('users').doc(user.uid).collection('appliances');
      // Cancel existing subscription if any
      await _appliancesSub?.cancel();
      _appliancesSub = appliancesColl.snapshots().listen((snap) {
        try {
          for (var doc in snap.docs) {
            final data = doc.data();
            // Coerce relay to string to handle numeric or string relay identifiers
            _applianceDetailsCache[doc.id] = {
              'wattage': (data['wattage'] as num?)?.toDouble() ?? 0.0,
              'relay': data['relay'] != null ? data['relay'].toString() : '',
              'applianceName': data['applianceName'] as String? ?? 'Unknown Device',
              'applianceStatus': data['applianceStatus'] as String? ?? 'OFF',
            };

            // Persist manual override expiries in memory if present
            DateTime? manualOffExpiry;
            if (data.containsKey('manualOffOverrideUntil') && data['manualOffOverrideUntil'] != null) {
              final ts = data['manualOffOverrideUntil'];
              if (ts is Timestamp) manualOffExpiry = ts.toDate();
            }
            if (manualOffExpiry != null && manualOffExpiry.isAfter(DateTime.now())) {
              _manualOffOverrides[doc.id] = manualOffExpiry;
            } else {
              _manualOffOverrides.remove(doc.id);
            }

            DateTime? manualOnExpiry;
            if (data.containsKey('manualOnOverrideUntil') && data['manualOnOverrideUntil'] != null) {
              final ts = data['manualOnOverrideUntil'];
              if (ts is Timestamp) manualOnExpiry = ts.toDate();
            }
            if (manualOnExpiry != null && manualOnExpiry.isAfter(DateTime.now())) {
              _manualOnOverrides[doc.id] = manualOnExpiry;
            } else {
              _manualOnOverrides.remove(doc.id);
            }
          }
        } catch (e) {
          print('SchedulingService: Error processing appliances snapshot: $e');
        }
      });
    } catch (e) {
      print('SchedulingService: Failed to listen to appliances: $e');
    }
    // Listen for master power setting so we can pause/resume scheduled toggles
    try {
      final masterDocRef = _firestore.collection('users').doc(user.uid).collection('settings').doc('master_power');
      _masterPowerSub?.cancel();
      _masterPowerSub = masterDocRef.snapshots().listen((doc) {
        try {
          if (!doc.exists || doc.data() == null) {
            _masterPowerEnabled = true;
            return;
          }
          final data = doc.data() as Map<String, dynamic>;
          _masterPowerEnabled = (data['enabled'] as bool?) ?? true;
          print('SchedulingService: masterPowerEnabled=$_masterPowerEnabled');
        } catch (e) {
          print('SchedulingService: error reading master power doc: $e');
        }
      });
    } catch (e) {
      print('SchedulingService: Failed to listen to master power: $e');
    }
    print("SchedulingService: Initializing for user ${user.uid}...");
    await _loadSchedules(user.uid);

    // Keep schedules in sync when appliance docs change (also updates cache via appliances listener above)
    _firestore
        .collection('users')
        .doc(user.uid)
        .collection('appliances')
        .snapshots()
        .listen((snapshot) {
      print("SchedulingService: Appliance data changed, reloading schedules.");
      _loadSchedules(user.uid);
    });

    // Clean up legacy stray relay9 which some UIs accidentally created. This prevents
    // the UI/hardware from seeing non-existent relays and ensures relay list remains 1..8.
    try {
      final relay9Ref = _firestore.collection('users').doc(user.uid).collection('relay_states').doc('relay9');
      final relay9Snap = await relay9Ref.get();
      if (relay9Snap.exists) {
        print('SchedulingService: Removing legacy relay9 document for user ${user.uid}');
        await relay9Ref.delete();
      }
    } catch (e) {
      print('SchedulingService: Failed to cleanup legacy relay9: $e');
    }

  _periodicTimer?.cancel();
  // Run every 10 seconds to balance responsiveness and performance.
  _periodicTimer = Timer.periodic(const Duration(seconds: 10), _checkSchedules);
    print("SchedulingService: Periodic schedule check started.");
  }

  Future<void> _loadSchedules(String userId) async {
    try {
      // Load per-appliance schedule fields from appliances collection
      final snapshot = await _firestore.collection('users').doc(userId).collection('appliances').get();

      _activeSchedules = snapshot.docs.map((doc) {
        final data = doc.data();
        // Load manualOffOverride and manualOnOverride if present on the appliance doc so overrides persist across restarts
        DateTime? manualOverrideExpiry;
        if (data.containsKey('manualOffOverrideUntil') && data['manualOffOverrideUntil'] != null) {
          try {
            final ts = data['manualOffOverrideUntil'];
            if (ts is Timestamp) {
              manualOverrideExpiry = ts.toDate();
            } else if (ts is String) {
              manualOverrideExpiry = DateTime.tryParse(ts);
            }
          } catch (e) {
            print('SchedulingService: Failed to parse manualOffOverrideUntil for ${doc.id}: $e');
          }
        }

        DateTime? manualOnExpiry;
        if (data.containsKey('manualOnOverrideUntil') && data['manualOnOverrideUntil'] != null) {
          try {
            final ts = data['manualOnOverrideUntil'];
            if (ts is Timestamp) {
              manualOnExpiry = ts.toDate();
            } else if (ts is String) {
              manualOnExpiry = DateTime.tryParse(ts);
            }
          } catch (e) {
            print('SchedulingService: Failed to parse manualOnOverrideUntil for ${doc.id}: $e');
          }
        }

        _applianceDetailsCache[doc.id] = {
          'wattage': (data['wattage'] as num?)?.toDouble() ?? 0.0,
          'relay': data['relay'] as String?,
          'applianceName': data['applianceName'] as String? ?? 'Unknown Device',
          'applianceStatus': data['applianceStatus'] as String? ?? 'OFF',
        };

        if (manualOverrideExpiry != null) {
          // Only keep overrides that are still in the future
          if (manualOverrideExpiry.isAfter(DateTime.now())) {
            _manualOffOverrides[doc.id] = manualOverrideExpiry;
          }
        }
        if (manualOnExpiry != null) {
          if (manualOnExpiry.isAfter(DateTime.now())) {
            _manualOnOverrides[doc.id] = manualOnExpiry;
          }
        }
        return {
          'id': doc.id,
          ...data,
        };
      }).where((schedule) {
        final days = schedule['days'] as List?;
        final startTime = schedule['startTime'] as String?;
        final endTime = schedule['endTime'] as String?;
        return days != null && days.isNotEmpty && startTime != null && endTime != null;
      }).toList();

      // Load group schedules from a separate collection: users/{uid}/schedules
        try {
          final groupColl = _firestore.collection('users').doc(userId).collection('schedules');
          final groupSnap = await groupColl.get();
          _groupSchedules = groupSnap.docs.map((d) => ScheduleModel.fromDoc(d)).where((s) => s.enabled && s.days.isNotEmpty && s.startTime.isNotEmpty && s.endTime.isNotEmpty).toList();
          print('SchedulingService: Loaded ${_groupSchedules.length} group schedules.');

          // Realtime listener for group schedules so updates take effect immediately
          groupColl.snapshots().listen((snap) {
            try {
              final updated = snap.docs.map((d) => ScheduleModel.fromDoc(d)).where((s) => s.enabled && s.days.isNotEmpty && s.startTime.isNotEmpty && s.endTime.isNotEmpty).toList();
              _groupSchedules = updated;
              print('SchedulingService: Group schedules updated from Firestore, ${_groupSchedules.length} active.');
            } catch (e) {
              print('SchedulingService: Error parsing updated group schedules: $e');
            }
          });
        } catch (e) {
          print('SchedulingService: Error loading group schedules: $e');
          _groupSchedules = [];
        }

      print("SchedulingService: Loaded ${_activeSchedules.length} active appliance schedules.");
    } catch (e) {
      print("SchedulingService: Error loading schedules: $e");
      _activeSchedules = [];
      _groupSchedules = [];
    }
  }

  String _getCurrentDayName(DateTime now) {
    return DateFormat('E').format(now); // E.g., "Mon", "Tue"
  }

  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == "0") {
      return null;
    }
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    } catch (e) {
      print("SchedulingService: Error parsing time string '$timeStr': $e");
    }
    return null;
  }

  int _timeOfDayToMinutes(TimeOfDay tod) {
    return tod.hour * 60 + tod.minute;
  }

  void _checkSchedules(Timer timer) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final relayService = RelayStateService(firestore: _firestore);

    final location = tz.getLocation('Asia/Manila');
    final now = tz.TZDateTime.now(location);
    String currentDayName = _getCurrentDayName(now);
    TimeOfDay currentTime = TimeOfDay.fromDateTime(now);

    // Clean up expired overrides
    // Find expired overrides to also clear persisted field
    final expired = _manualOffOverrides.entries.where((e) => now.isAfter(e.value)).toList();
    for (var e in expired) {
      final aid = e.key;
      _manualOffOverrides.remove(aid);
      try {
        final userId = _auth.currentUser?.uid;
        if (userId != null) {
          await _dbService.setDocument(
            collectionPath: 'users/${userId}/appliances',
            docId: aid,
            data: {'manualOffOverrideUntil': FieldValue.delete()},
            merge: true,
          );
        }
      } catch (ex) {
        print('SchedulingService: Failed to clear persisted manualOffOverrideUntil for $aid: $ex');
      }
    }

    // Also clear expired manual ON overrides so scheduled auto-OFF can occur
    final expiredOn = _manualOnOverrides.entries.where((e) => now.isAfter(e.value)).toList();
    for (var e in expiredOn) {
      final aid = e.key;
      _manualOnOverrides.remove(aid);
      try {
        final userId = _auth.currentUser?.uid;
        if (userId != null) {
          await _dbService.setDocument(
            collectionPath: 'users/${userId}/appliances',
            docId: aid,
            data: {'manualOnOverrideUntil': FieldValue.delete()},
            merge: true,
          );
        }
      } catch (ex) {
        print('SchedulingService: Failed to clear persisted manualOnOverrideUntil for $aid: $ex');
      }
    }

    print("SchedulingService: Checking schedules at $now ($currentDayName $currentTime)");

    // Fetch user's kWh rate once for this check cycle (use DatabaseService wrapper)
    double kwhrRate = DEFAULT_KWHR_RATE; // Default if not found
    try {
      final userDocSnap = await _dbService.getDocument(collectionPath: 'users', docId: user.uid);
      if (userDocSnap != null && userDocSnap.exists && userDocSnap.data() != null) {
        kwhrRate = ((userDocSnap.data() as Map<String,dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
      }
    } catch (e) {
      print('SchedulingService: Failed to read user doc for kWh rate: $e');
    }

    // Build a set of appliance IDs to evaluate:
    // - appliances that have per-appliance schedule fields (from _activeSchedules)
    // - appliances that are referenced by any group schedule (group.applianceIds)
    // This ensures group schedules can control appliances even if the appliance doc does not have its own schedule fields.
    final Set<String> applianceIdsToEvaluate = {};
    for (var s in _activeSchedules) {
      applianceIdsToEvaluate.add(s['id'] as String);
    }
    for (var g in _groupSchedules) {
      for (var aid in g.applianceIds) {
        applianceIdsToEvaluate.add(aid);
      }
    }

  // Collect pending intents so we can commit multiple relay/appliance writes in one batch
  final List<Map<String, dynamic>> pendingIntents = [];

  for (var applianceId in List<String>.from(applianceIdsToEvaluate)) {
      // Try to find per-appliance schedule data if available
      final scheduleData = _activeSchedules.firstWhere(
        (s) => s['id'] == applianceId,
        orElse: () => {},
      );

      List<String> scheduledDays = [];
      String? startTimeStr;
      String? endTimeStr;
      if (scheduleData.isNotEmpty) {
        List<dynamic> scheduledDaysRaw = scheduleData['days'] as List<dynamic>? ?? [];
        scheduledDays = scheduledDaysRaw.map((day) => day.toString()).toList();
        startTimeStr = scheduleData['startTime'] as String?;
        endTimeStr = scheduleData['endTime'] as String?;
      }
      
      // Use the in-memory cache for appliance details and status to keep checks fast.
      Map<String, dynamic>? applianceDetails = _applianceDetailsCache[applianceId];
      String currentApplianceStatus = 'OFF';
      if (applianceDetails != null) {
        currentApplianceStatus = (applianceDetails['applianceStatus'] as String?) ?? 'OFF';
      } else {
        // Fallback: fetch doc once if missing in cache
        try {
          final applianceSnap = await _firestore.collection('users').doc(user.uid).collection('appliances').doc(applianceId).get();
          if (!applianceSnap.exists || applianceSnap.data() == null) {
            print("SchedulingService: Appliance $applianceId not found. Skipping.");
            continue;
          }
          final data = applianceSnap.data() as Map<String, dynamic>;
          currentApplianceStatus = data['applianceStatus'] as String? ?? 'OFF';
          applianceDetails = {
            'wattage': (data['wattage'] as num?)?.toDouble() ?? 0.0,
            // Coerce relay id to string to support numeric relay ids
            'relay': data['relay'] != null ? data['relay'].toString() : '',
            'applianceName': data['applianceName'] as String? ?? 'Unknown Device',
            'applianceStatus': data['applianceStatus'] as String? ?? 'OFF',
          };
          _applianceDetailsCache[applianceId] = applianceDetails;
        } catch (e) {
          print("SchedulingService: Error fetching appliance $applianceId status: $e");
          continue; // Skip this appliance if status fetch fails
        }
      }


      TimeOfDay? scheduledStartTime = _parseTime(startTimeStr);
      TimeOfDay? scheduledEndTime = _parseTime(endTimeStr);

      bool isScheduledDay = scheduledDays.contains(currentDayName);

      // If this appliance has no per-appliance schedule today (or invalid times), we don't skip outright
      // because group schedules may still control it. The 'shouldBeOn' flag below will take group schedules into account.

  int nowInMinutes = _timeOfDayToMinutes(currentTime);
  int? startInMinutes = scheduledStartTime != null ? _timeOfDayToMinutes(scheduledStartTime) : null;
  int? endInMinutes = scheduledEndTime != null ? _timeOfDayToMinutes(scheduledEndTime) : null;

      bool shouldBeOn = false;
      // Evaluate per-appliance schedule only if both times are available and it's a scheduled day
      if (isScheduledDay && startInMinutes != null && endInMinutes != null) {
        if (startInMinutes <= endInMinutes) {
          // Schedule is on the same day (e.g., 08:00 to 17:00)
          shouldBeOn = nowInMinutes >= startInMinutes && nowInMinutes < endInMinutes;
        } else {
          // Schedule spans midnight (e.g., 22:00 to 02:00)
          shouldBeOn = nowInMinutes >= startInMinutes || nowInMinutes < endInMinutes;
        }
      }

  // Check group schedules: if any group schedule applies to this appliance and should be ON, honor it.
      try {
        for (final group in _groupSchedules) {
          if (!group.applianceIds.contains(applianceId)) continue;
          if (!group.days.contains(currentDayName)) continue;
          final gStart = _parseTime(group.startTime);
          final gEnd = _parseTime(group.endTime);
          if (gStart == null || gEnd == null) continue;
          int gStartMin = _timeOfDayToMinutes(gStart);
          int gEndMin = _timeOfDayToMinutes(gEnd);
          bool groupShouldBeOn;
          if (gStartMin <= gEndMin) {
            groupShouldBeOn = nowInMinutes >= gStartMin && nowInMinutes < gEndMin;
          } else {
            groupShouldBeOn = nowInMinutes >= gStartMin || nowInMinutes < gEndMin;
          }
          if (groupShouldBeOn) {
            shouldBeOn = true;
            break;
          }
        }
      } catch (e) {
        print('SchedulingService: Error evaluating group schedules for $applianceId: $e');
      }

      // Debug: print computed schedule values for this appliance to help diagnose ON/OFF edge cases
      if (kDebugMode) {
        final applianceName = applianceDetails['applianceName'] ?? applianceId;
        print('SchedulingService[DEBUG]: Appliance=${applianceName} (${applianceId}) nowMin=${nowInMinutes} startMin=${startInMinutes ?? 'null'} endMin=${endInMinutes ?? 'null'} startStr=${startTimeStr ?? 'null'} endStr=${endTimeStr ?? 'null'} scheduledDay=${isScheduledDay} shouldBeOn=${shouldBeOn}');
      }

      // --- State-based ON/OFF Logic ---
  if (shouldBeOn && currentApplianceStatus == 'OFF') {
        // Condition to turn ON
        // Respect persisted manual OFF overrides loaded at init or recorded at runtime.
        if (_manualOffOverrides.containsKey(applianceId)) {
          print("SchedulingService: Auto-ON for $applianceId skipped due to active manual OFF override.");
        } else {
          // Respect master power setting: do not auto-ON if master power disabled
          if (!_masterPowerEnabled) {
            print("SchedulingService: Auto-ON for $applianceId suppressed because master power is disabled.");
          } else {
            print("SchedulingService: Scheduling TURN ON for $applianceId as per schedule.");
            // Queue the intent for batch commit
            pendingIntents.add({'applianceId': applianceId, 'isOn': true, 'applianceDetails': applianceDetails, 'kwhrRate': kwhrRate});
          }
        }
      } else if (!shouldBeOn && currentApplianceStatus == 'ON') {
        // Condition to turn OFF
        // If the device was manually turned ON (manualOn override), do not auto-OFF until override expires
        if (_manualOnOverrides.containsKey(applianceId)) {
          print('SchedulingService: Auto-OFF for $applianceId skipped due to manual ON override.');
        } else {
          print("SchedulingService: Scheduling TURN OFF for $applianceId as per schedule.");
          // Queue the intent for batch commit
          pendingIntents.add({'applianceId': applianceId, 'isOn': false, 'applianceDetails': applianceDetails, 'kwhrRate': kwhrRate});
        }
        // Clear any override when schedule ends (in-memory and persisted)
        _manualOffOverrides.remove(applianceId);
        try {
          await _dbService.setDocument(
            collectionPath: 'users/${user.uid}/appliances',
            docId: applianceId,
            data: {'manualOffOverrideUntil': FieldValue.delete()},
            merge: true,
          );
        } catch (e) {
          print('SchedulingService: Failed to clear persisted manualOffOverrideUntil for $applianceId: $e');
        }
      }
    }

    // If there are pending intents, commit them in a single WriteBatch for this cycle
    if (pendingIntents.isNotEmpty) {
      final WriteBatch batch = _firestore.batch();
      final List<Map<String, dynamic>> postCommitWork = [];
      try {
        for (var intent in pendingIntents) {
          final aid = intent['applianceId'] as String;
          final bool turnOn = intent['isOn'] as bool;
          final details = intent['applianceDetails'] as Map<String, dynamic>? ?? {};
          final relayKey = details['relay'] != null ? details['relay'].toString() : '';
          final statusStr = turnOn ? 'ON' : 'OFF';

          if (relayKey.isNotEmpty) {
            try {
              // Centralize relay writes via RelayStateService so all writes go through
              // one code path (adds logs and uses transactions).
              await relayService.setApplianceState(userId: user.uid, applianceId: aid, turnOn: turnOn, source: 'scheduler');
            } catch (e) {
              print('SchedulingService: RelayStateService failed for $aid relay=$relayKey: $e');
              // Fallback: still attempt to write directly in the batch so operation proceeds
              final relayRef = _firestore.collection('users').doc(user.uid).collection('relay_states').doc(relayKey);
              final bool irControlled = details['irControlled'] as bool? ?? false;
              final double watt = (details['wattage'] as num?)?.toDouble() ?? 0.0;
              batch.set(relayRef, {
                'state': turnOn ? 1 : 0,
                'lastUpdated': FieldValue.serverTimestamp(),
                'irControlled': irControlled,
                'wattage': watt,
                'source': 'scheduler',
                'applianceId': aid,
              }, SetOptions(merge: true));
            }
          }

          final applianceRef = _firestore.collection('users').doc(user.uid).collection('appliances').doc(aid);
          batch.set(applianceRef, {'applianceStatus': statusStr}, SetOptions(merge: true));

          postCommitWork.add({'applianceId': aid, 'isOn': turnOn, 'details': details, 'kwhrRate': intent['kwhrRate']});
        }

        await batch.commit();
        print('SchedulingService: Batch commit succeeded for ${pendingIntents.length} intents');

        // Post-commit: handle usage and notifications
        for (var w in postCommitWork) {
          try {
            await _usageService.handleApplianceToggle(
              userId: user.uid,
              applianceId: w['applianceId'] as String,
              isOn: w['isOn'] as bool,
              wattage: ((w['details'] as Map<String,dynamic>)['wattage'] as num?)?.toDouble() ?? 0.0,
              kwhrRate: (w['kwhrRate'] as double?) ?? kwhrRate,
            );
          } catch (e) {
            print('SchedulingService: Usage handling failed for ${w['applianceId']}: $e');
          }

          try {
            final deviceName = (w['details'] as Map<String,dynamic>)['applianceName'] ?? w['applianceId'];
            await NotificationManager().notifyAutomationTriggered(
              automationName: 'Scheduler',
              action: (w['isOn'] as bool) ? 'turned on' : 'turned off',
              deviceName: deviceName,
              applianceId: w['applianceId'] as String,
            );
          } catch (e) {
            print('SchedulingService: Failed to persist notification for ${w['applianceId']}: $e');
          }
        }
      } catch (e) {
        print('SchedulingService: Batch commit failed: $e');
        // Fallback: run individual updates to ensure at least attempts are made
        for (var intent in pendingIntents) {
          try {
            await _setApplianceState(user.uid, intent['applianceId'] as String, intent['isOn'] as bool, intent['applianceDetails'] as Map<String,dynamic>, intent['kwhrRate'] as double);
          } catch (e2) {
            print('SchedulingService: Fallback failed for ${intent['applianceId']}: $e2');
          }
        }
      }
    }
  }

  Future<void> _setApplianceState(String userId, String applianceId, bool isOn, Map<String, dynamic> applianceDetails, double kwhrRate) async {
    String status = isOn ? 'ON' : 'OFF';
    int relayState = isOn ? 1 : 0;
    // Re-fetch appliance doc to ensure we have the latest relay mapping and details
    String? relayKey;
    Map<String, dynamic> latestAppliance = {};
    try {
      final snap = await _firestore.collection('users').doc(userId).collection('appliances').doc(applianceId).get();
      if (snap.exists && snap.data() != null) {
        latestAppliance = snap.data() as Map<String, dynamic>;
        relayKey = latestAppliance['relay'] != null ? latestAppliance['relay'].toString() : (applianceDetails['relay'] != null ? applianceDetails['relay'].toString() : null);
        // Ensure wattage uses freshest value
        applianceDetails['wattage'] = (latestAppliance['wattage'] as num?)?.toDouble() ?? (applianceDetails['wattage'] as num?)?.toDouble() ?? 0.0;
      } else {
        relayKey = applianceDetails['relay'] != null ? applianceDetails['relay'].toString() : '';
      }
    } catch (e) {
      print('SchedulingService: Failed to refetch appliance doc $applianceId: $e');
      relayKey = applianceDetails['relay'] != null ? applianceDetails['relay'].toString() : '';
    }

    // Use a batch so relay state and applianceStatus are written together atomically for this appliance
    final WriteBatch batch = _firestore.batch();
    DocumentReference? relayDocRef;
    bool irControlled = false;
    double wattage = (applianceDetails['wattage'] as num?)?.toDouble() ?? 0.0;

    if (relayKey != null && relayKey.isNotEmpty) {
      relayDocRef = _firestore.collection('users').doc(userId).collection('relay_states').doc(relayKey);
      try {
        final relaySnapshot = await relayDocRef.get();
        if (relaySnapshot.exists && relaySnapshot.data() != null) {
          final rd = relaySnapshot.data() as Map<String, dynamic>;
          irControlled = rd['irControlled'] as bool? ?? false;
          final num? rdWatt = rd['wattage'] as num?;
          if (rdWatt != null && (wattage == 0.0 || wattage.isNaN)) {
            wattage = rdWatt.toDouble();
          }
        }
      } catch (e) {
        print('SchedulingService: Warning: failed to read relay doc for $relayKey before batch write: $e');
      }

      // Prepare relay write in batch (use set with merge semantics by writing fields only)
      batch.set(relayDocRef, {
        'state': relayState,
        'lastUpdated': FieldValue.serverTimestamp(),
        'irControlled': irControlled,
        'wattage': wattage,
        'source': 'scheduler',
        'applianceId': applianceId,
      }, SetOptions(merge: true));
      print("SchedulingService: Prepared batch write for relay $relayKey -> state=$relayState for $applianceId");
    } else {
      print("SchedulingService: No relayKey for $applianceId — will still persist applianceStatus");
    }

    // Always persist applianceStatus in same batch to keep DB consistent
    final applianceDocRef = _firestore.collection('users').doc(userId).collection('appliances').doc(applianceId);
    batch.set(applianceDocRef, {'applianceStatus': status}, SetOptions(merge: true));

    // Commit the batch
    try {
      await batch.commit();
      // Update in-memory cache so next schedule evaluation sees latest status
      _applianceDetailsCache[applianceId] = {
        ...?_applianceDetailsCache[applianceId],
        'applianceStatus': status,
        'wattage': wattage,
        'relay': relayKey ?? (_applianceDetailsCache[applianceId]?['relay'] ?? ''),
      };
      // Trigger hardware relay helper
      if (relayKey != null && relayKey.isNotEmpty) {
        await _triggerHardwareRelay(userId, relayKey, relayState, irControlled);
      }
      print('SchedulingService: Batch commit succeeded for $applianceId; relay=$relayKey status=$status');
    } catch (e) {
      print('SchedulingService: Batch commit failed for $applianceId: $e');
      // If batch commit fails, still attempt to persist applianceStatus individually to avoid leaving the appliance with stale status
      try {
        await applianceDocRef.set({'applianceStatus': status}, SetOptions(merge: true));
        _applianceDetailsCache[applianceId]?['applianceStatus'] = status;
        print('SchedulingService: Fallback applianceStatus set succeeded for $applianceId');
      } catch (e2) {
        print('SchedulingService: Fallback applianceStatus set also failed for $applianceId: $e2');
      }
    }

    // Now handle usage accounting and persist a scheduler notification (do not block batch success)
    try {
      await _usageService.handleApplianceToggle(
        userId: userId,
        applianceId: applianceId,
        isOn: isOn,
        wattage: wattage,
        kwhrRate: kwhrRate,
      );
    } catch (e) {
      print('SchedulingService: Usage handling failed for $applianceId: $e');
    }

    try {
      final deviceName = applianceDetails['applianceName'] ?? applianceId;
      await NotificationManager().notifyAutomationTriggered(
        automationName: 'Scheduler',
        action: isOn ? 'turned on' : 'turned off',
        deviceName: deviceName,
        applianceId: applianceId,
      );
    } catch (e) {
      print('SchedulingService: Failed to persist scheduler notification for $applianceId: $e');
    }
  }

  // Called from UI when user confirms manual OFF during a scheduled ON period
  Future<void> recordManualOffOverride(String applianceId, TimeOfDay scheduleEndTimeForToday) async {
    final now = DateTime.now();
    // Override lasts until the end of the current day's scheduled ON period
    DateTime overrideExpiryTime = DateTime(
        now.year, now.month, now.day, 
        scheduleEndTimeForToday.hour, scheduleEndTimeForToday.minute
    );
    // If scheduleEndTime is next day (e.g. 23:00 to 02:00), adjust expiry.
    // For simplicity, current logic assumes endTime is on the same day as startTime.
    // Complex overnight schedules would need more sophisticated expiry calculation.

        if (overrideExpiryTime.isAfter(now)) {
        _manualOffOverrides[applianceId] = overrideExpiryTime;
        print("SchedulingService: Manual OFF override recorded for $applianceId until $overrideExpiryTime");
        // Persist override expiry to Firestore so it survives restarts (via DatabaseService)
        try {
          final userId = _auth.currentUser?.uid;
          if (userId != null) {
            await _dbService.setDocument(
              collectionPath: 'users/${userId}/appliances',
              docId: applianceId,
              data: {'manualOffOverrideUntil': Timestamp.fromDate(overrideExpiryTime)},
              merge: true,
            );
          }
        } catch (e) {
          print('SchedulingService: Failed to persist manualOffOverrideUntil for $applianceId: $e');
        }
    } else {
        print("SchedulingService: Manual OFF override for $applianceId not recorded as schedule end time is in the past.");
    }
  }
  
  /// Helper to trigger the physical hardware for a relay change.
  ///
  /// Purpose: provide a single place to invoke any cloud/function/command routing
  /// necessary to cause physical relays to toggle in response to scheduler changes.
  /// Current implementation: logs and returns. For on-prem hardware (ESP32), the
  /// recommended pattern is that the ESP32 device listens to the Firestore
  /// document at `users/{uid}/relay_states/{relayKey}` and acts when `state` changes.
  /// The example ESP32 code provided in the repository shows how to
  /// connect the device to Firebase and subscribe to document changes. If you later
  /// want to route commands through a separate collection (e.g., `device_commands`),
  /// implement that logic here.
  Future<void> _triggerHardwareRelay(String userId, String relayKey, int relayState, bool irControlled) async {
    // No-op in-app: we update the Firestore document above and the device should
    // observe the change and perform the physical toggle. Keep this method so we
    // can extend it later (call cloud functions, push to MQTT broker, etc.).
    print('SchedulingService: _triggerHardwareRelay called for $relayKey (state=$relayState, irControlled=$irControlled)');
    return;
  }

  void dispose() {
    _periodicTimer?.cancel();
    // Cancel any Firestore listeners if they were set up directly here
    _appliancesSub?.cancel();
    _groupSchedulesSub?.cancel();
    _masterPowerSub?.cancel();
    print("SchedulingService: Disposed.");
  }

  /// Toggle the master power setting for the current user. When disabling master power
  /// we set all relay_states to 0 so hardware will switch off. When enabling, we only
  /// set the setting flag (do not turn relays on automatically).
  Future<void> toggleMasterPower(bool enabled) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('users').doc(user.uid).collection('settings').doc('master_power').set({'enabled': enabled}, SetOptions(merge: true));
      _masterPowerEnabled = enabled;
      if (!enabled) {
        // Force all relay states to 0 for this user
        final relaysSnap = await _firestore.collection('users').doc(user.uid).collection('relay_states').get();
        for (var r in relaysSnap.docs) {
          try {
            await _firestore.collection('users').doc(user.uid).collection('relay_states').doc(r.id).set({'state': 0, 'lastUpdated': FieldValue.serverTimestamp()}, SetOptions(merge: true));
          } catch (e) {
            print('SchedulingService: Failed to set relay ${r.id} to 0 during master power off: $e');
          }
        }
      }
    } catch (e) {
      print('SchedulingService: Failed to toggle master power: $e');
    }
  }
}
