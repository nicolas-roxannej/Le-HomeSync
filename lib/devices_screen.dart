import 'package:flutter/material.dart';
import 'package:homesync/adddevices.dart';
import 'package:homesync/helpscreen.dart';
import 'package:homesync/notification_screen.dart';
import 'package:weather/weather.dart';
import 'package:homesync/welcome_screen.dart';
import 'package:homesync/relay_state.dart';
import 'package:homesync/databaseservice.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/notification_manager.dart';
import 'package:homesync/notification_service.dart';
import 'package:homesync/usage.dart';
import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:homesync/services/relay_state_service.dart';
import 'package:homesync/about.dart';

const String _apiKey = 'd542f2e03ea5728e77e367f19c0fb675';
const String _cityName = 'Manila';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => DevicesScreenState();
}

class DevicesScreenState extends State<DevicesScreen> {
  Weather? _currentWeather;
  int _selectedIndex = 1;
  final DatabaseService _dbService = DatabaseService();

  // Stream subscriptions for proper cleanup
  StreamSubscription<QuerySnapshot>? _appliancesSubscription;
  StreamSubscription<QuerySnapshot>? _allRelaysSubscription;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _devices = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredDevices = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Master power is APP ONLY
  bool _masterPowerButtonState = true;

  UsageService? _usageService;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String> getCurrentUsername() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();

        if (userDoc.exists) {
          Map<String, dynamic> userData =
              userDoc.data() as Map<String, dynamic>;
          return userData['username'] ?? ' ';
        }
      }
      return ' ';
    } catch (e) {
      print('Error fetching username: $e');
      return ' ';
    }
  }

  Future<void> _fetchWeather() async {
    WeatherFactory wf = WeatherFactory(_apiKey);
    try {
      Weather w = await wf.currentWeatherByCityName(_cityName);
      if (mounted) {
        setState(() {
          _currentWeather = w;
        });
      }
      print(
        "Weather fetched successfully: ${w.temperature?.celsius?.toStringAsFixed(1)}°C - ${w.weatherDescription}",
      );
    } catch (e) {
      print("Failed to fetch weather: $e");
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _filterDevices() {
    setState(() {
      if (_searchQuery.isEmpty) {
        _filteredDevices = List.from(_devices);
      } else {
        _filteredDevices =
            _devices.where((deviceDoc) {
              final deviceData = deviceDoc.data();
              final String applianceName =
                  (deviceData['applianceName'] as String? ?? '').toLowerCase();
              final String roomName =
                  (deviceData['roomName'] as String? ?? '').toLowerCase();
              final String deviceType =
                  (deviceData['deviceType'] as String? ?? '').toLowerCase();
              final String searchLower = _searchQuery.toLowerCase();

              return applianceName.contains(searchLower) ||
                  roomName.contains(searchLower) ||
                  deviceType.contains(searchLower);
            }).toList();
      }
    });
  }

  void _updateSearchQuery(String query) {
    _searchQuery = query;
    _filterDevices();
  }

  @override
  void initState() {
    super.initState();
    _usageService = UsageService();
    _fetchWeather();
    _listenToAppliances();
    _listenForRelayStateChanges();

    _searchController.addListener(() {
      _updateSearchQuery(_searchController.text);
    });
  }

  // UPDATED: Sync relay states with appliance status
  void _listenForRelayStateChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("⚠️ User not authenticated. Cannot listen to relay state changes.");
      return;
    }

    // Cancel existing listener
    _allRelaysSubscription?.cancel();

    print("🔊 Setting up relay states listener with auto-sync...");

    // Listen to entire relay_states collection
    _allRelaysSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('relay_states')
        .snapshots()
        .listen(
          (snapshot) async {
            if (!mounted) return;

            print(
              "📡 Received relay states update: ${snapshot.docs.length} relays",
            );

            setState(() {
              for (var doc in snapshot.docs) {
                if (doc.exists) {
                  final data = doc.data();
                  final relayKey = doc.id;

                  int newState = data['state'] as int? ?? 0;
                  int oldState = RelayState.relayStates[relayKey] ?? 0;

                  RelayState.relayStates[relayKey] = newState;
                  RelayState.irControlledStates[relayKey] =
                      data['irControlled'] as bool? ?? false;
                  RelayState.ldrControlledStates[relayKey] =
                      data['ldrControlled'] as bool? ?? false;

                  print(
                    '✅ $relayKey: state=$newState, IR=${RelayState.irControlledStates[relayKey]}, LDR=${RelayState.ldrControlledStates[relayKey]}',
                  );

                  // CRITICAL: Sync appliance status with relay state
                  if (newState != oldState) {
                    _syncApplianceStatusWithRelayState(relayKey, newState);
                  }
                }
              }
            });
          },
          onError: (error) {
            print('❌ Error listening to relay states: $error');
          },
        );
  }

  // NEW: Sync appliance status with relay state (for real-time hardware updates)
  Future<void> _syncApplianceStatusWithRelayState(
    String relayKey,
    int newState,
  ) async {
    try {
      final userUid = FirebaseAuth.instance.currentUser?.uid;
      if (userUid == null) return;

      String newStatus = newState == 1 ? 'ON' : 'OFF';

      // Find all appliances with this relay
      final QuerySnapshot appliancesSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userUid)
              .collection('appliances')
              .where('relay', isEqualTo: relayKey)
              .get();

      // Update appliance status to match relay state
      for (var applianceDoc in appliancesSnapshot.docs) {
        final currentStatus = applianceDoc.data() as Map<String, dynamic>;
        final currentApplianceStatus =
            currentStatus['applianceStatus'] ?? 'OFF';

        // Only update if status is different
        if (currentApplianceStatus != newStatus) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userUid)
              .collection('appliances')
              .doc(applianceDoc.id)
              .update({'applianceStatus': newStatus});

          print(
            '🔄 Synced appliance ${currentStatus['applianceName']} to $newStatus (hardware change)',
          );
        }
      }
    } catch (e) {
      print('❌ Error syncing appliance status: $e');
    }
  }

  void _listenToAppliances() {
    _appliancesSubscription?.cancel();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User not authenticated. Cannot fetch appliances.");
      if (mounted) {
        setState(() {
          _devices = [];
          _filteredDevices = [];
        });
      }
      return;
    }

    _appliancesSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('appliances')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _devices = snapshot.docs;
          _filterDevices();
        });
      }
    }, onError: (error) {
      print("Error listening to appliances: $error");
      if (mounted) {
        setState(() {
          _devices = [];
          _filteredDevices = [];
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _appliancesSubscription?.cancel();
    _allRelaysSubscription?.cancel();
    super.dispose();
  }

  void _toggleMasterPower() async {
    if (!_masterPowerButtonState) {
      setState(() {
        _masterPowerButtonState = true;
      });
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("User not authenticated");
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );

      print("🔴 Master power OFF - turning off all devices...");

      List<Future<void>> updateFutures = [];
      final userUid = user.uid;

      // Turn off all 5 hardware relays
      for (String relayKey in [
        'relay1',
        'relay3',
        'relay4',
        'relay7',
        'relay8',
      ]) {
        RelayState.relayStates[relayKey] = 0;
        updateFutures.add(Future(() async {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userUid)
                .collection('relay_states')
                .doc(relayKey)
                .set({
              'state': 0,
              'irControlled': false,
              'ldrControlled': false,
              'source': 'master_power',
            }, SetOptions(merge: true));
          } catch (e) {
            print('DevicesScreen: Failed to set relay $relayKey: $e');
          }
        }));
      }

      // Turn off all appliances
      for (var deviceDoc in _devices) {
        updateFutures.add(
          FirebaseFirestore.instance
              .collection('users')
              .doc(userUid)
              .collection('appliances')
              .doc(deviceDoc.id)
              .update({'applianceStatus': 'OFF'}),
        );
      }

      await Future.wait(updateFutures);
      print("✅ Master power OFF - all devices turned off");

      // Send notifications
      try {
        await NotificationService().showSystemNotification(
          title: 'Master Power',
          message: 'Master power has been turned OFF. All devices were turned off.',
        );
      } catch (e) {
        print('DevicesScreen: Failed to show master power system notification: $e');
      }

      try {
        final List<Future<void>> notifFutures = [];
        for (var deviceDoc in _devices) {
          final deviceData = deviceDoc.data();
          final String name = deviceData['applianceName'] ?? '';
          final String room = deviceData['roomName'] ?? '';
          notifFutures.add(NotificationManager().notifyDeviceStatusChange(
            deviceName: name,
            room: room,
            isOn: false,
            applianceId: deviceDoc.id,
          ));
        }
        await Future.wait(notifFutures);
      } catch (e) {
        print('DevicesScreen: Failed to send device notifications: $e');
      }

      if (mounted) {
        Navigator.pop(context);
        setState(() {
          _masterPowerButtonState = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 12),
                Text('All devices turned off successfully'),
              ],
            ),
            backgroundColor: Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error turning off devices: ${e.toString()}"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _toggleIndividualDevice(
    String applianceName,
    String currentStatus,
  ) async {
    const double DEFAULT_KWHR_RATE = 0.15;
    
    try {
      print("🔄 Starting toggle for $applianceName...");

      final newStatus = (currentStatus == 'ON') ? 'OFF' : 'ON';

      final deviceDoc =
          _devices.firstWhere(
            (doc) => doc.data()['applianceName'] == applianceName,
          );
      final deviceData = deviceDoc.data();
      final String relay = deviceData['relay'] as String? ?? '';

      if (relay.isEmpty) {
        throw Exception("No relay assigned to this appliance");
      }

      bool isIrControlled =
          RelayState.irControlledStates[relay] ?? false;
      bool isLdrControlled =
          RelayState.ldrControlledStates[relay] ?? false;

      if (isIrControlled || isLdrControlled) {
        final controlType =
            isIrControlled ? 'IR sensor' : 'LDR sensor';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Cannot toggle $applianceName - controlled by $controlType",
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
        return;
      }

      int newRelayState = (newStatus == 'ON') ? 1 : 0;
      RelayState.relayStates[relay] = newRelayState;
      
      print("📤 Updating relay state: $relay to $newRelayState");
      try {
        final relayService = RelayStateService(firestore: FirebaseFirestore.instance);
        await relayService.setApplianceStateForCurrentUser(
          applianceId: deviceDoc.id,
          turnOn: newStatus == 'ON',
          source: 'manual'
        );
        print("✅ Updated $relay via RelayStateService to state=$newRelayState");
      } catch (e) {
        print('DevicesScreen: RelayStateService failed, falling back to direct write for $relay: $e');
        final userUid = FirebaseAuth.instance.currentUser!.uid;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userUid)
            .collection('relay_states')
            .doc(relay)
            .set({
          'state': newRelayState,
          'irControlled': false,
          'ldrControlled': false,
          'source': 'manual',
        }, SetOptions(merge: true));
      }

      Map<String, dynamic> updateData = {
        'applianceStatus': newStatus,
        'lastModified': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('appliances')
          .doc(deviceDoc.id)
          .update(updateData);

      print("✅ Device $applianceName toggled successfully");

      // Trigger a notification for this manual toggle and include applianceId
      try {
        await NotificationManager().notifyDeviceStatusChange(
          deviceName: applianceName,
          room: deviceData['roomName'] ?? '',
          isOn: newStatus == 'ON',
          applianceId: deviceDoc.id,
        );
      } catch (e) {
        print('DevicesScreen: Failed to send manual toggle notification: $e');
      }

      // Handle usage tracking
      final userUid = FirebaseAuth.instance.currentUser!.uid;
      final applianceId = deviceDoc.id;
      final double wattage =
          (deviceData['wattage'] is num)
              ? (deviceData['wattage'] as num).toDouble()
              : 0.0;

      DocumentSnapshot userSnap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userUid)
              .get();
      double kwhrRate = DEFAULT_KWHR_RATE;
      if (userSnap.exists && userSnap.data() != null) {
        kwhrRate =
            ((userSnap.data() as Map<String, dynamic>)['kwhr'] as num?)
                ?.toDouble() ??
            DEFAULT_KWHR_RATE;
      }

      await _usageService?.handleApplianceToggle(
        userId: userUid,
        applianceId: applianceId,
        isOn: newStatus == 'ON',
        wattage: wattage,
        kwhrRate: kwhrRate,
      );
    } catch (e) {
      print("❌ Error toggling device $applianceName: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Failed to update $applianceName: ${e.toString()}",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F8F8),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddDeviceScreen()),
          );
        },
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF8F8F8),
                Colors.white,
              ],
            ),
          ),
          child: Column(
            children: [
              // Enhanced Header with Gradient
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFD0DDD0),
                      Color(0xFFF8F8F8),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.09),
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // User Profile Section
                          GestureDetector(
                            onTap: () => _showFlyout(context),
                            child: Row(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [Colors.black, Colors.black],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: CircleAvatar(
                                    backgroundColor: Colors.transparent,
                                    radius: 28,
                                    child: Icon(Icons.home_rounded, color: Colors.white, size: 30),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome back',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    SizedBox(
                                      width: 110,
                                      child: FutureBuilder<String>(
                                        future: getCurrentUsername(),
                                        builder: (context, snapshot) {
                                          return Text(
                                            snapshot.data ?? " ",
                                            style: GoogleFonts.inter(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1A1A1A),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Weather Widget
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.wb_sunny_rounded, size: 24, color: Color(0xFFFFB84D)),
                                SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _currentWeather == null
                                        ? Text('--°C', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600))
                                        : Text(
                                            '${_currentWeather?.temperature?.celsius?.toStringAsFixed(0) ?? '--'}°C',
                                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                          ),
                                    Text(
                                      _currentWeather?.weatherDescription ?? 'Loading...',
                                      style: GoogleFonts.inter(
                                        color: Colors.grey[600],
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      // Navigation Tabs
                      Container(
                        decoration: BoxDecoration(
                          color: Color(0xFFF0F0F2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: EdgeInsets.all(4),
                        child: Row(
                          children: [
                            _buildModernNavButton('Electricity', _selectedIndex == 0, 0),
                            _buildModernNavButton('Appliance', _selectedIndex == 1, 1),
                            _buildModernNavButton('Rooms', _selectedIndex == 2, 2),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Main Content
              Expanded(
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search and Master Power Section
                        Row(
                          children: [
                            Flexible(
                              flex: 1,
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    hintText: 'Search appliances...',
                                    hintStyle: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: Colors.grey[500],
                                    ),
                                    prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[600]),
                                    suffixIcon: _searchQuery.isNotEmpty
                                        ? IconButton(
                                            icon: Icon(Icons.clear_rounded, color: Colors.grey[600]),
                                            onPressed: () {
                                              _searchController.clear();
                                            },
                                          )
                                        : null,
                                    filled: false,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 16,
                                    ),
                                  ),
                                  style: GoogleFonts.inter(fontSize: 14),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            GestureDetector(
                              onTap: _toggleMasterPower,
                              child: Container(
                                height: 50,
                                width: 50,
                                decoration: BoxDecoration(
                                  color: _masterPowerButtonState ? Colors.black : Colors.grey[400],
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_masterPowerButtonState ? Colors.black : Colors.grey)
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.power_settings_new_rounded,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 24),

                        // Devices Section Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Your Devices',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_filteredDevices.length} devices',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 20),

                        // Devices Grid
                        _filteredDevices.isEmpty
                            ? Container(
                                padding: EdgeInsets.all(60),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 20,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.devices_other_rounded,
                                        size: 64,
                                        color: Colors.grey[300],
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        _searchQuery.isNotEmpty
                                            ? "No devices found matching '$_searchQuery'"
                                            : 'No devices found',
                                        style: GoogleFonts.inter(
                                          color: Colors.grey[600],
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      if (_searchQuery.isEmpty) ...[
                                        SizedBox(height: 8),
                                        Text(
                                          'Tap + to add your first device',
                                          style: GoogleFonts.inter(
                                            color: Colors.grey[500],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              )
                            : GridView.builder(
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 20),
                                itemCount: _filteredDevices.length,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 0.9,
                                ),
                                itemBuilder: (context, index) {
                                  final deviceDoc = _filteredDevices[index];
                                  final deviceData = deviceDoc.data();
                                  final String applianceName =
                                      deviceData['applianceName'] as String? ?? 'Unknown Device';
                                  final String roomName =
                                      deviceData['roomName'] as String? ?? 'Unknown Room';
                                  final String deviceType =
                                      deviceData['deviceType'] as String? ?? 'Unknown Type';
                                  final String applianceStatus =
                                      deviceData['applianceStatus'] as String? ?? 'OFF';
                                  final bool isOn = applianceStatus == 'ON';
                                  final int iconCodePoint =
                                      (deviceData['icon'] is int)
                                          ? deviceData['icon'] as int
                                          : Icons.devices.codePoint;

                                  return GestureDetector(
                                    onTap: () {
                                      if (_masterPowerButtonState) {
                                        _toggleIndividualDevice(
                                          applianceName,
                                          applianceStatus,
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(Icons.warning_rounded, color: Colors.white),
                                                SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    "Turn on master power first",
                                                    style: GoogleFonts.inter(color: Colors.white),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor: Colors.orange[700],
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: DeviceCard(
                                      applianceName: applianceName,
                                      roomName: roomName,
                                      deviceType: deviceType,
                                      isOn: isOn,
                                      icon: _getIconFromCodePoint(iconCodePoint),
                                      applianceStatus: applianceStatus,
                                      masterSwitchIsOn: _masterPowerButtonState,
                                      applianceId: deviceDoc.id,
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernNavButton(String title, bool isSelected, int index) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });

          switch (index) {
            case 0:
              Navigator.pushNamed(context, '/homepage');
              break;
            case 1:
              break;
            case 2:
              Navigator.pushNamed(context, '/rooms');
              break;
          }
        },
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: isSelected ? Colors.black : Colors.grey[600],
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  void _showFlyout(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dismiss",
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerLeft,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: Material(
              color: Color(0xFFE9E7E6),
              elevation: 16,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.75,
                height: MediaQuery.of(context).size.height,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(30.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFE9EFEC), Colors.white],
                        ),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.black,
                              child: Icon(Icons.home_rounded, size: 45, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FutureBuilder<String>(
                            future: getCurrentUsername(),
                            builder: (context, snapshot) {
                              return Text(
                                snapshot.data ?? "Loading...",
                                style: GoogleFonts.inter(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        children: [
                          _buildMenuTile(
                            Icons.person_rounded,
                            "Profile",
                            () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/profile');
                            },
                          ),
                          _buildMenuTile(
                            Icons.notifications_rounded,
                            "Notifications",
                            () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => NotificationScreen(),
                                ),
                              );
                            },
                          ),
                          _buildMenuTile(
                            Icons.info_rounded,
                            "About",
                            () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => AboutScreen()),
                              );
                            },
                          ),
                           _buildMenuTile(
                            Icons.help_rounded,
                            "Help?",
                            () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => HelpScreen()),
                              );
                            },
                          ),
                        
                        ],
                        
                      ),
                    ),
                    
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey[400]!, width: 1),
                        ),
                      ),
                      child: _buildMenuTile(
                        Icons.logout_rounded,
                        "Log Out",
                        () async {
                          Navigator.pop(context);
                          await _auth.signOut();
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => WelcomeScreen(),
                            ),
                            (Route<dynamic> route) => false,
                          );
                        },
                        isDestructive: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap,
      {bool isDestructive = false}) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDestructive
              ? Colors.red.withOpacity(0.1)
              : Colors.black.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          size: 24,
          color: isDestructive ? Colors.red : Colors.black,
        ),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDestructive ? Colors.red : Color(0xFF1A1A1A),
        ),
      ),
      onTap: onTap,
    );
  }
}

// KEPT from first code - empty class
class ON {}

class DeviceCard extends StatelessWidget {
  final String applianceName;
  final String roomName;
  final String deviceType;
  final bool isOn;
  final IconData icon;
  final String applianceStatus;
  final bool masterSwitchIsOn;
  final String applianceId;

  const DeviceCard({
    super.key,
    required this.applianceName,
    required this.roomName,
    required this.deviceType,
    required this.isOn,
    required this.icon,
    required this.applianceStatus,
    required this.masterSwitchIsOn,
    required this.applianceId,
  });

  @override
  Widget build(BuildContext context) {
    final bool effectiveIsOn = masterSwitchIsOn && isOn;

    return Container(
      decoration: BoxDecoration(
        gradient: effectiveIsOn
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black,
                  Colors.grey[900]!,
                ],
              )
            : null,
        color: effectiveIsOn ? null : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: effectiveIsOn
                ? Colors.black.withOpacity(0.5)
                : Colors.black.withOpacity(0.5),
            blurRadius: effectiveIsOn ? 16 : 12,
            offset: Offset(0, effectiveIsOn ? 6 : 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: effectiveIsOn
                        ? Colors.white.withOpacity(0.2)
                        : Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: effectiveIsOn ? Colors.white : Colors.black,
                    size: 28,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  applianceName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: effectiveIsOn ? Colors.white : Color(0xFF1A1A1A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2),
                Text(
                  roomName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: effectiveIsOn ? Colors.white70 : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 1),
                Text(
                  deviceType,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: effectiveIsOn ? Colors.white60 : Colors.grey[500],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: effectiveIsOn
                        ? Color(0xFF4CAF50).withOpacity(0.3)
                        : Colors.grey.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: effectiveIsOn ? Color(0xFF4CAF50) : Colors.grey,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    effectiveIsOn ? 'ON' : 'OFF',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: effectiveIsOn ? Color(0xFF4CAF50) : Colors.grey[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: InkWell(
              onTap: () {
                if (applianceStatus == 'ON') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.warning_rounded, color: Colors.white),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Turn off the appliance before editing.",
                              style: GoogleFonts.inter(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.red[600],
                      duration: const Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                } else {
                  Navigator.pushNamed(
                    context,
                    '/editdevice',
                    arguments: {'applianceId': applianceId},
                  );
                }
              },
              child: Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: effectiveIsOn
                      ? Colors.white.withOpacity(0.2)
                      : Colors.black.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.edit_rounded,
                  size: 16,
                  color: effectiveIsOn ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _getIconFromCodePoint(int codePoint) {
  final Map<int, IconData> iconMap = {
    Icons.light.codePoint: Icons.light,
    Icons.tv.codePoint: Icons.tv,
    Icons.power.codePoint: Icons.power,
    Icons.kitchen.codePoint: Icons.kitchen,
    Icons.speaker.codePoint: Icons.speaker,
    Icons.laptop.codePoint: Icons.laptop,
    Icons.ac_unit.codePoint: Icons.ac_unit,
    Icons.microwave.codePoint: Icons.microwave,
    Icons.coffee_maker.codePoint: Icons.coffee_maker,
    Icons.radio_button_checked.codePoint: Icons.radio_button_checked,
    Icons.thermostat.codePoint: Icons.thermostat,
    Icons.doorbell.codePoint: Icons.doorbell,
    Icons.camera.codePoint: Icons.camera,
    Icons.sensor_door.codePoint: Icons.sensor_door,
    Icons.lock.codePoint: Icons.lock,
    Icons.door_sliding.codePoint: Icons.door_sliding,
    Icons.local_laundry_service.codePoint: Icons.local_laundry_service,
    Icons.dining.codePoint: Icons.dining,
    Icons.rice_bowl.codePoint: Icons.rice_bowl,
    Icons.wind_power.codePoint: Icons.wind_power,
    Icons.router.codePoint: Icons.router,
    Icons.outdoor_grill.codePoint: Icons.outdoor_grill,
    Icons.air.codePoint: Icons.air,
    Icons.alarm.codePoint: Icons.alarm,
    Icons.living.codePoint: Icons.living,
    Icons.bed.codePoint: Icons.bed,
    Icons.bathroom.codePoint: Icons.bathroom,
    Icons.meeting_room.codePoint: Icons.meeting_room,
    Icons.garage.codePoint: Icons.garage,
    Icons.local_library.codePoint: Icons.local_library,
    Icons.stairs.codePoint: Icons.stairs,
    Icons.devices.codePoint: Icons.devices,
    Icons.home.codePoint: Icons.home,
  };
  return iconMap[codePoint] ?? Icons.devices;
}