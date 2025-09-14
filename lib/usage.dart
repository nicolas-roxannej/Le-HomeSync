import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Default cost per kWh. This should ideally be configurable.
const double DEFAULT_KWHR_RATE = 0.15; // Example rate

class UsageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Timer? _liveUpdateTimer;

  // --- Helper Functions for Path Generation and Date Logic (internal) ---

  String _getMonthName(int month) {
    const monthNames = [
      '', 'january', 'february', 'march', 'april', 'may', 'june',
      'july', 'august', 'september', 'october', 'november', 'december'
    ];
    return monthNames[month].toLowerCase();
  }

  int _getWeekOfMonth(DateTime date) {
    if (date.day <= 7) return 1;
    if (date.day <= 14) return 2;
    if (date.day <= 21) return 3;
    if (date.day <= 28) return 4;
    return 5; 
  }

  // --- Path Helpers for Per-Appliance Usage Data ---

  String _getApplianceDailyPath(String userId, String applianceId, DateTime date) {
    String year = date.year.toString();
    String monthName = _getMonthName(date.month);
    int weekOfMonth = _getWeekOfMonth(date);
    String dayStr = DateFormat('yyyy-MM-dd').format(date);
    return 'users/$userId/appliances/$applianceId/yearly_usage/$year/monthly_usage/${monthName}_usage/week_usage/week${weekOfMonth}_usage/day_usage/$dayStr';
  }

  String _getApplianceWeeklyPath(String userId, String applianceId, DateTime date) {
    String year = date.year.toString();
    String monthName = _getMonthName(date.month);
    int weekOfMonth = _getWeekOfMonth(date);
    return 'users/$userId/appliances/$applianceId/yearly_usage/$year/monthly_usage/${monthName}_usage/week_usage/week${weekOfMonth}_usage';
  }

  String _getApplianceMonthlyPath(String userId, String applianceId, DateTime date) {
    String year = date.year.toString();
    String monthName = _getMonthName(date.month);
    return 'users/$userId/appliances/$applianceId/yearly_usage/$year/monthly_usage/${monthName}_usage';
  }

  String _getApplianceYearlyPath(String userId, String applianceId, DateTime date) {
    String year = date.year.toString();
    return 'users/$userId/appliances/$applianceId/yearly_usage/$year';
  }

  // --- Path Helpers for Overall Aggregated Usage (New Structure: /users/{uid}/yearly_usage/) ---

  String getOverallYearlyDocPath(String userId, int year) {
    return 'users/$userId/yearly_usage/$year';
  }

  String getOverallMonthlyDocPath(String userId, int year, int month) {
    String monthName = _getMonthName(month);
    return 'users/$userId/yearly_usage/$year/monthly_usage/${monthName}_usage';
  }

  String getOverallWeeklyDocPath(String userId, int year, int month, int weekOfMonth) {
    String monthName = _getMonthName(month);
    return 'users/$userId/yearly_usage/$year/monthly_usage/${monthName}_usage/week_usage/week${weekOfMonth}_usage';
  }

  String getOverallDailyDocPath(String userId, DateTime date) {
    String yearStr = date.year.toString();
    String monthName = _getMonthName(date.month);
    int weekOfMonth = _getWeekOfMonth(date);
    String dayFormatted = DateFormat('yyyy-MM-dd').format(date);
    return 'users/$userId/yearly_usage/$yearStr/monthly_usage/${monthName}_usage/week_usage/week${weekOfMonth}_usage/day_usage/$dayFormatted';
  }

  // --- Public API ---

  Future<void> handleApplianceToggle({
    required String userId,
    required String applianceId,
    required bool isOn,
    required double wattage,
    double kwhrRate = DEFAULT_KWHR_RATE,
  }) async {
    DateTime now = DateTime.now();
    String timeStr = DateFormat('HH:mm:ss').format(now);
    String dailyPathForEvent = _getApplianceDailyPath(userId, applianceId, now);
    DocumentReference currentActionDailyDocRef = _firestore.doc(dailyPathForEvent);

    if (isOn) {
      await currentActionDailyDocRef.set({
        'usagetimeon': FieldValue.arrayUnion([timeStr]),
        'last_event_timestamp': FieldValue.serverTimestamp(),
        'wattage': wattage,
        'kwhr_rate': kwhrRate,
      }, SetOptions(merge: true));
      print('Appliance $applianceId (User: $userId) turned ON. Updated doc: $dailyPathForEvent. Attempted to add ON time: $timeStr');
    } else {
      await currentActionDailyDocRef.set({
        'usagetimeoff': FieldValue.arrayUnion([timeStr]),
        'last_event_timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('Appliance $applianceId (User: $userId) turned OFF. Updated doc: $dailyPathForEvent');

      await _calculateAndRecordUsageForCompletedSession(
        userId: userId,
        applianceId: applianceId,
        wattage: wattage,
        kwhrRate: kwhrRate,
        offTime: now,
      );
    }
    await _triggerAggregationsForAppliance(userId, applianceId, kwhrRate, now);
    await updateAllAppliancesTotalUsage(userId: userId, kwhrRate: kwhrRate, referenceDate: now);
  }

  Future<void> _calculateAndRecordUsageForCompletedSession({
    required String userId,
    required String applianceId,
    required double wattage,
    required double kwhrRate,
    required DateTime offTime,
  }) async {
    DocumentReference? onDayDocRef;
    String? onDateStr;
    String? correspondingOnTimeStr; // Renamed for clarity

    print("Attempting to find ON time for $applianceId, OFF event at $offTime");

    // Iterate back up to 7 days to find the matching ON event's document
    for (int i = 0; i < 7; i++) {
        DateTime dateToQuery = offTime.subtract(Duration(days: i));
        String dailyPath = _getApplianceDailyPath(userId, applianceId, dateToQuery);
        DocumentSnapshot dailyDoc = await _firestore.doc(dailyPath).get();

        if (dailyDoc.exists) {
            Map<String, dynamic> data = dailyDoc.data() as Map<String, dynamic>;
            List<String> usageTimeOn = List<String>.from(data['usagetimeon'] ?? []);
            // usageTimeOff includes the current offTime if i == 0, as it's read after the OFF event is written
            List<String> usageTimeOff = List<String>.from(data['usagetimeoff'] ?? []); 

            if (usageTimeOn.isNotEmpty) {
                bool foundMatch = false;
                if (i == 0) { // Current day of the OFF event
                    // MODIFIED: If there's any ON event recorded for today,
                    // attempt to pair the current OFF event with the LATEST recorded ON event for today.
                    if (usageTimeOn.isNotEmpty) {
                       correspondingOnTimeStr = usageTimeOn.last; // Pair with the latest ON from that day.
                       foundMatch = true;
                    }
                } else { // Previous day (for sessions spanning midnight)
                    // The previous day must have more ONs than OFFs for an open session.
                    // This logic remains suitable for sessions spanning midnight.
                    if (usageTimeOn.length > usageTimeOff.length) {
                        correspondingOnTimeStr = usageTimeOn.last; // The last ON from the previous day
                        foundMatch = true;
                    }
                }

                if (foundMatch && correspondingOnTimeStr != null) {
                    onDayDocRef = dailyDoc.reference;
                    onDateStr = DateFormat('yyyy-MM-dd').format(dateToQuery);
                    print("Found corresponding ON time: $correspondingOnTimeStr on $onDateStr for OFF event at $offTime");
                    break; 
                }
            }
        }
        // If onDayDocRef is set, it means we found the doc and time, so break outer loop.
        if (onDayDocRef != null) break; 
    }

    if (onDayDocRef != null && onDateStr != null && correspondingOnTimeStr != null) {
      DateTime onDateTime = DateFormat('yyyy-MM-dd HH:mm:ss').parse('$onDateStr $correspondingOnTimeStr');
      if (offTime.isAfter(onDateTime)) {
        Duration duration = offTime.difference(onDateTime);
        double hours = duration.inSeconds / 3600.0;
        double kwh = (wattage * hours) / 1000.0;
        double kwhCost = kwh * kwhrRate;

        await onDayDocRef.set({
          'kwh': FieldValue.increment(kwh),
          'kwhrcost': FieldValue.increment(kwhCost),
          // Ensure wattage and kwhr_rate are also present if this is the first kwh/kwhrcost entry
          'wattage': wattage, 
          'kwhr_rate': kwhrRate,
        }, SetOptions(merge: true));
        print('Session for $applianceId: $kwh kWh, Cost: $kwhCost. Updated doc: ${onDayDocRef.path}');
        
        await _triggerAggregationsForAppliance(userId, applianceId, kwhrRate, onDateTime);
        // If the session spanned across midnight from a previous day to the offTime day
        if (onDateStr != DateFormat('yyyy-MM-dd').format(offTime)) {
            await _triggerAggregationsForAppliance(userId, applianceId, kwhrRate, offTime);
        }
      } else {
         print("Warning: Calculated OFF time ($offTime) is not after ON time ($onDateTime) for $applianceId. This might indicate a data mismatch or clock issue.");
      }
    } else {
      print("Could not find a corresponding ON time for $applianceId (OFF event at $offTime).");
    }
  }

  void startLiveUsageUpdates({required String userId, required double kwhrRate}) {
    _liveUpdateTimer?.cancel();
    _liveUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      DateTime now = DateTime.now();
      await _updateLiveUsageForAllAppliances(userId: userId, kwhrRate: kwhrRate, currentTime: now);
    });
    print("UsageService: Live usage updates started for user $userId.");
  }

  void stopLiveUsageUpdates() {
    _liveUpdateTimer?.cancel();
    print("UsageService: Live usage updates stopped.");
  }

  Future<void> _updateLiveUsageForAllAppliances({
    required String userId,
    required double kwhrRate,
    required DateTime currentTime,
  }) async {
    QuerySnapshot appliancesSnap = await _firestore.collection('users').doc(userId).collection('appliances').get();

    for (QueryDocumentSnapshot applianceDoc in appliancesSnap.docs) {
      String applianceId = applianceDoc.id;
      Map<String, dynamic> applianceData = applianceDoc.data() as Map<String, dynamic>;
      double? wattage = (applianceData['wattage'] as num?)?.toDouble();
      String? status = applianceData['applianceStatus'] as String?;

      if (wattage == null || status != 'ON') continue;

      DocumentReference? liveUpdateDocRef;
      String? onDateStrForLiveUpdate;
      String? lastOnTimeStrForLiveUpdate;

      for (int i = 0; i < 2; i++) { 
          DateTime dateToQuery = currentTime.subtract(Duration(days: i));
          String dailyPath = _getApplianceDailyPath(userId, applianceId, dateToQuery);
          DocumentSnapshot dailyDocSnap = await _firestore.doc(dailyPath).get();

          if (dailyDocSnap.exists) {
              Map<String, dynamic> data = dailyDocSnap.data() as Map<String, dynamic>;
              List<String> usageTimeOn = List<String>.from(data['usagetimeon'] ?? []);
              List<String> usageTimeOff = List<String>.from(data['usagetimeoff'] ?? []);

              if (usageTimeOn.isNotEmpty && usageTimeOff.length < usageTimeOn.length) {
                  liveUpdateDocRef = dailyDocSnap.reference;
                  onDateStrForLiveUpdate = DateFormat('yyyy-MM-dd').format(dateToQuery);
                  lastOnTimeStrForLiveUpdate = usageTimeOn.last;
                  break;
              }
          }
      }
      
      if (liveUpdateDocRef != null && onDateStrForLiveUpdate != null && lastOnTimeStrForLiveUpdate != null) {
        DateTime onDateTime = DateFormat('yyyy-MM-dd HH:mm:ss').parse('$onDateStrForLiveUpdate $lastOnTimeStrForLiveUpdate');
        DateTime lastCalculationPoint = (applianceData['last_live_calc_timestamp'] as Timestamp?)?.toDate() ?? onDateTime;
        DateTime calculationWindowStart = lastCalculationPoint.isAfter(onDateTime) ? lastCalculationPoint : onDateTime;

        if (currentTime.isAfter(calculationWindowStart)) {
          Duration activeDurationSinceLastCalc = currentTime.difference(calculationWindowStart);
          if (activeDurationSinceLastCalc.isNegative) continue;

          double minuteHours = activeDurationSinceLastCalc.inSeconds / 3600.0;
          double minuteKwh = (wattage * minuteHours) / 1000.0;
          double minuteKwhCost = minuteKwh * kwhrRate;

          if (minuteKwh > 0) {
            WriteBatch batch = _firestore.batch();
            batch.set(liveUpdateDocRef, {
              'kwh': FieldValue.increment(minuteKwh),
              'kwhrcost': FieldValue.increment(minuteKwhCost),
              'last_live_update': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            
            DocumentReference mainApplianceDocRef = _firestore.collection('users').doc(userId).collection('appliances').doc(applianceId);
            batch.update(mainApplianceDocRef, {'last_live_calc_timestamp': FieldValue.serverTimestamp()});
            
            await batch.commit();
            print('Live update for $applianceId on doc ${liveUpdateDocRef.path}: Added $minuteKwh kWh');
            
            DateTime usageDay = DateFormat('yyyy-MM-dd').parse(onDateStrForLiveUpdate);
            await _triggerAggregationsForAppliance(userId, applianceId, kwhrRate, usageDay);
            await updateAllAppliancesTotalUsage(userId: userId, kwhrRate: kwhrRate, referenceDate: usageDay);
          }
        }
      }
    }
  }

  Future<void> _triggerAggregationsForAppliance(String userId, String applianceId, double kwhrRate, DateTime referenceDate) async {
    print("UsageService: Triggering aggregations for $applianceId on $referenceDate");
    await _aggregateDailyToWeekly(userId, applianceId, kwhrRate, referenceDate);
    await _aggregateWeeklyToMonthly(userId, applianceId, kwhrRate, referenceDate);
    await _aggregateMonthlyToYearly(userId, applianceId, kwhrRate, referenceDate);
  }

  Future<void> _aggregateDailyToWeekly(String userId, String applianceId, double kwhrRate, DateTime referenceDate) async {
    String weeklyPath = _getApplianceWeeklyPath(userId, applianceId, referenceDate);
    String year = referenceDate.year.toString();
    String monthName = _getMonthName(referenceDate.month);
    int weekOfMonth = _getWeekOfMonth(referenceDate);
    
    String dailyDocsCollectionPath = 'users/$userId/appliances/$applianceId/yearly_usage/$year/monthly_usage/${monthName}_usage/week_usage/week${weekOfMonth}_usage/day_usage';
    QuerySnapshot dailyDocsSnap = await _firestore.collection(dailyDocsCollectionPath).get();

    double totalKwh = 0;
    double totalKwhCost = 0; // Initialize sum for kwhrcost
    for (var doc in dailyDocsSnap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      totalKwh += (data['kwh'] as num?)?.toDouble() ?? 0.0;
      totalKwhCost += (data['kwhrcost'] as num?)?.toDouble() ?? 0.0; // Sum kwhrcost
    }
    // kwhrRate is no longer used to recalculate totalKwhCost here

    await _firestore.doc(weeklyPath).set({
      'kwh': totalKwh, 'kwhrcost': totalKwhCost, 'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    print('Per-Appliance Weekly aggregation for $applianceId ($weeklyPath): $totalKwh kWh');
  }

  Future<void> _aggregateWeeklyToMonthly(String userId, String applianceId, double kwhrRate, DateTime referenceDate) async {
    String monthlyPath = _getApplianceMonthlyPath(userId, applianceId, referenceDate);
    String year = referenceDate.year.toString();
    String monthName = _getMonthName(referenceDate.month);

    String weeklyDocsCollectionPath = 'users/$userId/appliances/$applianceId/yearly_usage/$year/monthly_usage/${monthName}_usage/week_usage';
    QuerySnapshot weeklyDocsSnap = await _firestore.collection(weeklyDocsCollectionPath).get();
    
    double totalKwh = 0;
    double totalKwhCost = 0; // Initialize sum for kwhrcost
    for (var doc in weeklyDocsSnap.docs) {
       final data = doc.data() as Map<String, dynamic>;
       totalKwh += (data['kwh'] as num?)?.toDouble() ?? 0.0;
       totalKwhCost += (data['kwhrcost'] as num?)?.toDouble() ?? 0.0; // Sum kwhrcost
    }
    // kwhrRate is no longer used to recalculate totalKwhCost here

    await _firestore.doc(monthlyPath).set({
      'kwh': totalKwh, 'kwhrcost': totalKwhCost, 'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    print('Per-Appliance Monthly aggregation for $applianceId ($monthlyPath): $totalKwh kWh');
  }

  Future<void> _aggregateMonthlyToYearly(String userId, String applianceId, double kwhrRate, DateTime referenceDate) async {
    String yearlyPath = _getApplianceYearlyPath(userId, applianceId, referenceDate);
    String year = referenceDate.year.toString();

    String monthlyDocsCollectionPath = 'users/$userId/appliances/$applianceId/yearly_usage/$year/monthly_usage';
    QuerySnapshot monthlyDocsSnap = await _firestore.collection(monthlyDocsCollectionPath).get();

    double totalKwh = 0;
    double totalKwhCost = 0; // Initialize sum for kwhrcost
    for (var doc in monthlyDocsSnap.docs) {
       final data = doc.data() as Map<String, dynamic>;
       totalKwh += (data['kwh'] as num?)?.toDouble() ?? 0.0;
       totalKwhCost += (data['kwhrcost'] as num?)?.toDouble() ?? 0.0; // Sum kwhrcost
    }
    // kwhrRate is no longer used to recalculate totalKwhCost here

    await _firestore.doc(yearlyPath).set({
      'kwh': totalKwh, 'kwhrcost': totalKwhCost, 'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    print('Per-Appliance Yearly aggregation for $applianceId ($yearlyPath): $totalKwh kWh');
  }

  // --- Overall User Aggregation (New Structure: /users/{uid}/yearly_usage/) ---

  /// Refreshes all per-appliance aggregations for a given date and then updates the overall user totals.
  Future<void> refreshAllUsageDataForDate({
    required String userId,
    required double kwhrRate,
    required DateTime referenceDate,
  }) async {
    print("UsageService: Starting full refresh for user $userId on $referenceDate.");
    QuerySnapshot appliancesSnap = await _firestore.collection('users').doc(userId).collection('appliances').get();
    for (var applianceDoc in appliancesSnap.docs) {
      String applianceId = applianceDoc.id;
      // Trigger aggregations for each appliance for the reference date
      await _triggerAggregationsForAppliance(userId, applianceId, kwhrRate, referenceDate);
    }
    // After all individual appliances are updated, update the overall totals
    await updateAllAppliancesTotalUsage(userId: userId, kwhrRate: kwhrRate, referenceDate: referenceDate);
    print("UsageService: Full refresh completed for user $userId on $referenceDate.");
  }
  
  /// Specifically recalculates and stores overall usage totals for the user for a given reference date.
  /// This assumes per-appliance data is already up-to-date for that date.
  Future<void> updateAllAppliancesTotalUsage({required String userId, required double kwhrRate, required DateTime referenceDate}) async {
    print("UsageService: Updating all overall appliance total usage for user $userId, reference date: $referenceDate");
    // Daily Total for Overall
    await _calculateAndStoreOverallTotalForPeriod(
        userId: userId, kwhrRate: kwhrRate, referenceDate: referenceDate,
        targetDocPath: getOverallDailyDocPath(userId, referenceDate), periodType: 'daily'
    );
    // Weekly Total for Overall
    await _calculateAndStoreOverallTotalForPeriod(
        userId: userId, kwhrRate: kwhrRate, referenceDate: referenceDate,
        targetDocPath: getOverallWeeklyDocPath(userId, referenceDate.year, referenceDate.month, _getWeekOfMonth(referenceDate)), periodType: 'weekly'
    );
    // Monthly Total for Overall
    await _calculateAndStoreOverallTotalForPeriod(
        userId: userId, kwhrRate: kwhrRate, referenceDate: referenceDate,
        targetDocPath: getOverallMonthlyDocPath(userId, referenceDate.year, referenceDate.month), periodType: 'monthly'
    );
    // Yearly Total for Overall
    await _calculateAndStoreOverallTotalForPeriod(
        userId: userId, kwhrRate: kwhrRate, referenceDate: referenceDate,
        targetDocPath: getOverallYearlyDocPath(userId, referenceDate.year), periodType: 'yearly'
    );
  }

  Future<void> _calculateAndStoreOverallTotalForPeriod({
    required String userId,
    required double kwhrRate,
    required DateTime referenceDate,
    required String targetDocPath, 
    required String periodType 
  }) async {
    QuerySnapshot appliancesSnap = await _firestore.collection('users').doc(userId).collection('appliances').get();
    double totalKwhForAllAppliances = 0;
    double totalKwhCostForAllAppliances = 0; // Initialize sum for kwhrcost

    for (var applianceDoc in appliancesSnap.docs) {
      String applianceId = applianceDoc.id;
      String applianceDetailedPeriodPath;

      switch (periodType) {
        case 'daily':
          applianceDetailedPeriodPath = _getApplianceDailyPath(userId, applianceId, referenceDate);
          break;
        case 'weekly':
          applianceDetailedPeriodPath = _getApplianceWeeklyPath(userId, applianceId, referenceDate);
          break;
        case 'monthly':
          applianceDetailedPeriodPath = _getApplianceMonthlyPath(userId, applianceId, referenceDate);
          break;
        case 'yearly':
          applianceDetailedPeriodPath = _getApplianceYearlyPath(userId, applianceId, referenceDate);
          break;
        default:
          print("Error: Unknown periodType '$periodType' in _calculateAndStoreOverallTotalForPeriod.");
          return;
      }

      DocumentSnapshot appliancePeriodDoc = await _firestore.doc(applianceDetailedPeriodPath).get();
      if (appliancePeriodDoc.exists && appliancePeriodDoc.data() != null) {
        final data = appliancePeriodDoc.data() as Map<String, dynamic>;
        totalKwhForAllAppliances += (data['kwh'] as num?)?.toDouble() ?? 0.0;
        totalKwhCostForAllAppliances += (data['kwhrcost'] as num?)?.toDouble() ?? 0.0; // Sum kwhrcost
      }
    }
    // kwhrRate is no longer used to recalculate totalKwhCostForAllAppliances here

    Map<String, dynamic> dataToWrite = {
      'totalKwh': totalKwhForAllAppliances,
      'totalKwhrCost': totalKwhCostForAllAppliances, // Use the summed cost
      'last_updated': FieldValue.serverTimestamp(),
    };

    await _firestore.doc(targetDocPath).set(dataToWrite, SetOptions(merge: true));
    print('Overall $periodType usage for user $userId (Doc: $targetDocPath): $totalKwhForAllAppliances kWh');
  }

  // Ensures the basic yearly_usage structure for the given date exists.
  Future<void> ensureUserYearlyUsageStructureExists(String userId, DateTime date) async {
    if (userId.isEmpty) {
      print('UsageService Error: Cannot ensure yearly_usage structure for empty userId.');
      return;
    }
    print('UsageService: Ensuring yearly_usage structure for user $userId for date ${DateFormat('yyyy-MM-dd').format(date)}.');

    final Map<String, dynamic> defaultData = {
      'totalKwh': 0.0,
      'totalKwhrCost': 0.0,
      'last_initialized': FieldValue.serverTimestamp()
    };

    try {
      // Ensure Year Document
      String yearPath = getOverallYearlyDocPath(userId, date.year);
      DocumentReference yearDocRef = _firestore.doc(yearPath);
      DocumentSnapshot yearDocSnap = await yearDocRef.get();
      if (!yearDocSnap.exists) {
        await yearDocRef.set(defaultData, SetOptions(merge: true));
        print('Created year document: $yearPath');
      }

      // Ensure Month Document
      String monthPath = getOverallMonthlyDocPath(userId, date.year, date.month);
      DocumentReference monthDocRef = _firestore.doc(monthPath);
      DocumentSnapshot monthDocSnap = await monthDocRef.get();
      if (!monthDocSnap.exists) {
        await monthDocRef.set(defaultData, SetOptions(merge: true));
        print('Created month document: $monthPath');
      }

      // Ensure Week Document
      String weekPath = getOverallWeeklyDocPath(userId, date.year, date.month, _getWeekOfMonth(date));
      DocumentReference weekDocRef = _firestore.doc(weekPath);
      DocumentSnapshot weekDocSnap = await weekDocRef.get();
      if (!weekDocSnap.exists) {
        await weekDocRef.set(defaultData, SetOptions(merge: true));
        print('Created week document: $weekPath');
      }

      // Ensure Day Document
      String dayPath = getOverallDailyDocPath(userId, date);
      DocumentReference dayDocRef = _firestore.doc(dayPath);
      DocumentSnapshot dayDocSnap = await dayDocRef.get();
      if (!dayDocSnap.exists) {
        await dayDocRef.set(defaultData, SetOptions(merge: true));
        print('Created day document: $dayPath');
      }
      print('UsageService: yearly_usage structure check complete for user $userId for date ${DateFormat('yyyy-MM-dd').format(date)}.');

    } catch (e) {
      print('UsageService: CRITICAL ERROR ensuring yearly_usage structure for user $userId: $e');
    }
  }

  // This function can be kept if HomepageScreen still needs to create a specific missing doc on the fly.
  Future<void> createMissingSummaryDocumentWithDefaults(String docPath) async {
    print('UsageService: Document reported missing at $docPath. Attempting to create with default zero values.');
    try {
      await _firestore.doc(docPath).set({
        'totalKwh': 0.0,
        'totalKwhrCost': 0.0,
        'last_updated': FieldValue.serverTimestamp(),
        'isInitializedByListener': true 
      }, SetOptions(merge: true));
    print('UsageService: Successfully created summary document with defaults at $docPath via listener request.');
    } catch (e) {
      print('UsageService: CRITICAL ERROR creating summary document with defaults at $docPath via listener request: $e');
    }
  }

  /// Public method to manually refresh a specific appliance's aggregated usage data for a given date.
  Future<void> refreshApplianceUsage({
    required String userId,
    required String applianceId,
    required double kwhrRate,
    required double wattage, // Added wattage parameter
    required DateTime referenceDate,
  }) async {
    print("UsageService: Manual refresh requested for appliance $applianceId, user $userId, date $referenceDate, wattage $wattage.");
    // Ensure the basic structure exists for the appliance for that day,
    // as aggregations read from daily documents.
    // This step might be redundant if handleApplianceToggle always creates the daily doc,
    // but it's a good safeguard.
    String dailyPath = _getApplianceDailyPath(userId, applianceId, referenceDate);
    DocumentSnapshot dailyDoc = await _firestore.doc(dailyPath).get();
    if (!dailyDoc.exists) {
      await _firestore.doc(dailyPath).set({
        'kwh': 0.0, // Initialize with 0 if it doesn't exist
        'kwhrcost': 0.0,
        'wattage': wattage, // Use provided wattage
        'kwhr_rate': kwhrRate,
        'last_initialized_by_refresh': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print("UsageService: Initialized missing daily doc $dailyPath during refresh with wattage $wattage.");
    }
    
    await _triggerAggregationsForAppliance(userId, applianceId, kwhrRate, referenceDate);
    // After refreshing a specific appliance, also update the overall user totals for that reference date.
    await updateAllAppliancesTotalUsage(userId: userId, kwhrRate: kwhrRate, referenceDate: referenceDate);
    print("UsageService: Manual refresh completed for appliance $applianceId and overall totals updated.");
  }

  void run({required FirebaseAuth auth, required FirebaseFirestore firestore}) {}
}
