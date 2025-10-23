import 'package:flutter/material.dart';
import 'package:homesync/adddevices.dart';
// import 'package:homesync/notification_screen.dart';
import 'package:weather/weather.dart';
import 'package:homesync/welcome_screen.dart';
import 'package:homesync/relay_state.dart';
// import 'package:homesync/databaseservice.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/notification_manager.dart'; // Import notification manager to trigger persisted + local notifications
import 'package:homesync/notification_service.dart';
import 'package:homesync/usage.dart';
import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:homesync/services/relay_state_service.dart';

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
  // DatabaseService instance removed as it was unused in this screen.

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
        "Weather fetched: ${w.temperature?.celsius?.toStringAsFixed(1)}°C - ${w.weatherDescription}",
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
      print("⚠️ User not authenticated. Cannot fetch appliances.");
      if (mounted) {
        setState(() {
          _devices = [];
          _filteredDevices = [];
        });
      }
      return;
    }

    print("🔊 Setting up appliances listener...");

    _appliancesSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('appliances')
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            setState(() {
              _devices = snapshot.docs;
              _filterDevices();

              print(
                "📡 Received appliances update: ${_devices.length} devices",
              );

              for (int i = 0; i < min(_devices.length, 3); i++) {
                final data = _devices[i].data();
                print(
                  "Device ${i + 1}: ${data['applianceName']} (${data['roomName']}) - ${data['applianceStatus']}",
                );
              }
            });
          },
          onError: (error) {
            print("❌ Error listening to appliances: $error");
            if (mounted) {
              setState(() {
                _devices = [];
                _filteredDevices = [];
              });
            }
          },
        );
  }

  @override
  void dispose() {
    print("🧹 Disposing DevicesScreen - cancelling listeners...");
    _appliancesSubscription?.cancel();
    _allRelaysSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // Master power toggle (APP ONLY)
  void _toggleMasterPower() async {
    bool newMasterState = !_masterPowerButtonState;

    setState(() {
      _masterPowerButtonState = newMasterState;
      RelayState.masterPowerOn = newMasterState;
    });

    try {
      final userUid = FirebaseAuth.instance.currentUser!.uid;

      if (!newMasterState) {
        print("🔴 Master power OFF - turning off all devices...");

        List<Future<void>> updateFutures = [];

        // Turn off all 5 hardware relays
  for (String relayKey in [
          'relay1',
          'relay3',
          'relay4',
          'relay7',
          'relay8',
        ]) {
          RelayState.relayStates[relayKey] = 0;
          // Try centralized service first; if it fails, fallback to direct write.
          updateFutures.add(Future(() async {
            try {
              // We don't have an applianceId here; setApplianceState requires one.
              // Use a direct write via service by writing relay doc directly through Firestore instance.
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
              print('DevicesScreen: Failed to set relay $relayKey via service fallback: $e');
            }
          }));
        }

        // Turn off all appliances (will be synced automatically by listener)
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

        // Persist a system notification summarizing the master power toggle
        try {
          await NotificationService().showSystemNotification(
            title: 'Master Power',
            message: 'Master power has been turned OFF. All devices were turned off.',
          );
        } catch (e) {
          print('DevicesScreen: Failed to show master power system notification: $e');
        }

        // Persist an individual device notification for each appliance (so they appear in the notifications feed)
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
          // Run persist operations in parallel but don't block UI too long
          await Future.wait(notifFutures);
        } catch (e) {
          print('DevicesScreen: Failed to persist per-appliance notifications for master power OFF: $e');
        }
      } else {
        print("🟢 Master power ON - devices can be controlled");
        try {
          await NotificationService().showSystemNotification(
            title: 'Master Power',
            message: 'Master power has been turned ON. Devices can now be controlled.',
          );
        } catch (e) {
          print('DevicesScreen: Failed to show master power ON system notification: $e');
        }
      }
    } catch (e) {
      print("❌ Error during master power toggle: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Error toggling master power: ${e.toString()}",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleIndividualDevice(
    String applianceName,
    String currentStatus,
  ) async {
    if (!_masterPowerButtonState) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Cannot toggle device when master power is OFF",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    try {
      final deviceDoc = _devices.firstWhere(
        (doc) => doc.data()['applianceName'] == applianceName,
      );
      final deviceData = deviceDoc.data();
      final String relayKey = deviceData['relay'] as String? ?? '';

      // Check if IR controlled
      if (RelayState.irControlledStates[relayKey] == true &&
          currentStatus == 'ON') {
        bool? confirmTurnOff = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text("Confirm Turn Off"),
              content: Text(
                "This device is currently controlled by IR sensor. Do you want to force it OFF?",
              ),
              actions: <Widget>[
                TextButton(
                  child: Text("Cancel"),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  child: Text("Turn Off"),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        );

        if (confirmTurnOff != true) return;
      }

      // Check if LDR controlled
      if (RelayState.ldrControlledStates[relayKey] == true &&
          currentStatus == 'ON') {
        bool? confirmTurnOff = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text("Confirm Turn Off"),
              content: Text(
                "This device is currently controlled by wall switch (LDR). Do you want to force it OFF?",
              ),
              actions: <Widget>[
                TextButton(
                  child: Text("Cancel"),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  child: Text("Turn Off"),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            );
          },
        );

        if (confirmTurnOff != true) return;
      }

      final newStatus = currentStatus == 'ON' ? 'OFF' : 'ON';
      print(
        "🔄 Toggling device $applianceName from $currentStatus to $newStatus",
      );

      if (relayKey.isNotEmpty) {
        int newRelayState = newStatus == 'ON' ? 1 : 0;

        try {
          final relayService = RelayStateService(firestore: FirebaseFirestore.instance);
          // Use the centralized method which resolves appliance -> relay mapping and writes logs
          await relayService.setApplianceStateForCurrentUser(applianceId: deviceDoc.id, turnOn: newStatus == 'ON', source: 'manual');
          print("✅ Updated $relayKey via RelayStateService to state=$newRelayState");
        } catch (e) {
          print('DevicesScreen: RelayStateService failed, falling back to direct write for $relayKey: $e');
          final userUid = FirebaseAuth.instance.currentUser!.uid;
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userUid)
              .collection('relay_states')
              .doc(relayKey)
              .set({
                'state': newRelayState,
                'irControlled': false,
                'ldrControlled': false,
                'source': 'manual',
                'applianceId': deviceDoc.id,
              }, SetOptions(merge: true));
        }
      }

      // Update appliance status
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('appliances')
          .doc(deviceDoc.id)
          .update({'applianceStatus': newStatus});

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
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddDeviceScreen()),
          );
        },
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _showFlyout(context),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(0, 20),
                          child: CircleAvatar(
                            backgroundColor: Colors.grey,
                            radius: 25,
                            child: Icon(
                              Icons.home,
                              color: Colors.black,
                              size: 35,
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Transform.translate(
                          offset: Offset(0, 20),
                          child: SizedBox(
                            width: 110,
                            child: FutureBuilder<String>(
                              future: getCurrentUsername(),
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.data ?? " ",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Transform.translate(
                    offset: Offset(0, 20),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 31,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.cloud_circle_sharp,
                                size: 35,
                                color: Colors.lightBlue,
                              ),
                              SizedBox(width: 4),
                              Transform.translate(
                                offset: Offset(0, -5),
                                child:
                                    _currentWeather == null
                                        ? Text(
                                          'Loading...',
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                          ),
                                        )
                                        : Text(
                                          '${_currentWeather?.temperature?.celsius?.toStringAsFixed(0) ?? '--'}°C',
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                          ),
                                        ),
                              ),
                            ],
                          ),
                          Transform.translate(
                            offset: Offset(40, -15),
                            child: Text(
                              _currentWeather?.weatherDescription ??
                                  'Loading weather...',
                              style: GoogleFonts.inter(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavButton('Electricity', _selectedIndex == 0, 0),
                  _buildNavButton('Appliance', _selectedIndex == 1, 1),
                  _buildNavButton('Rooms', _selectedIndex == 2, 2),
                ],
              ),

              SizedBox(
                width: double.infinity,
                child: Divider(height: 1, thickness: 1, color: Colors.black38),
              ),

              Expanded(
                child: GestureDetector(
                  onTap: () {
                    FocusScope.of(context).unfocus();
                  },
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 20),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 47,
                                child: TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    hintText: 'Search appliance...',
                                    hintStyle: TextStyle(fontSize: 16),
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon:
                                        _searchQuery.isNotEmpty
                                            ? IconButton(
                                              icon: Icon(Icons.clear),
                                              onPressed: () {
                                                _searchController.clear();
                                              },
                                            )
                                            : null,
                                    filled: true,
                                    fillColor: Color(0xFFD9D9D9),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(30),
                                      borderSide: BorderSide(
                                        color: Colors.grey,
                                        width: 1.5,
                                      ),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 20,
                                    ),
                                  ),
                                  style: TextStyle(fontSize: 16),
                                  onChanged: (value) {},
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color:
                                      _masterPowerButtonState
                                          ? Colors.black
                                          : Colors.grey,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.power_settings_new,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  onPressed: _toggleMasterPower,
                                  tooltip: 'Master Power',
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 25),

                        _filteredDevices.isEmpty
                            ? SizedBox(
                              height: 200,
                              child: Center(
                                child: Text(
                                  _searchQuery.isNotEmpty
                                      ? "No devices found matching '$_searchQuery'"
                                      : "No devices found.",
                                  style: GoogleFonts.inter(),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                            : GridView.builder(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 70),
                              itemCount: _filteredDevices.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                  ),
                              itemBuilder: (context, index) {
                                final deviceDoc = _filteredDevices[index];
                                final deviceData = deviceDoc.data();
                                final String applianceName =
                                    deviceData['applianceName'] as String? ??
                                    'Unknown Device';
                                final String roomName =
                                    deviceData['roomName'] as String? ??
                                    'Unknown Room';
                                final String deviceType =
                                    deviceData['deviceType'] as String? ??
                                    'Unknown Type';
                                final String applianceStatus =
                                    deviceData['applianceStatus'] as String? ??
                                    'OFF';
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
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "Turn on master power first",
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          backgroundColor: Colors.red,
                                          duration: const Duration(seconds: 3),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                                  onLongPress: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/editdevice',
                                      arguments: {'applianceId': deviceDoc.id},
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          _masterPowerButtonState && isOn
                                              ? Colors.black
                                              : Color(0xFFD9D9D9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: DeviceCard(
                                      applianceName: applianceName,
                                      roomName: roomName,
                                      deviceType: deviceType,
                                      isOn: isOn,
                                      icon: _getIconFromCodePoint(
                                        iconCodePoint,
                                      ),
                                      applianceStatus: applianceStatus,
                                      masterSwitchIsOn: _masterPowerButtonState,
                                      applianceId: deviceDoc.id,
                                    ),
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

  void _showFlyout(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Dismiss",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerLeft,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: Material(
              color: Colors.white,
              elevation: 8,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.7,
                height: MediaQuery.of(context).size.height,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey,
                      child: Icon(Icons.home, size: 50, color: Colors.black),
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<String>(
                      future: getCurrentUsername(),
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data ?? "Loading...",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                    const Divider(height: 32, thickness: 1),
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: const Text("Profile"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/profile');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.notifications),
                      title: const Text("Notifications"),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/notification');
                      },
                    ),
                   
                    const Spacer(),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text(
                        "Log Out",
                        style: TextStyle(color: Colors.red),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        await _auth.signOut();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (context) => WelcomeScreen(),
                          ),
                          (Route<dynamic> route) => false,
                        );
                      },
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

  Widget _buildNavButton(String title, bool isSelected, int index) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: () {
            setState(() => _selectedIndex = index);
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
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size(80, 36),
          ),
          child: Text(
            title,
            style: GoogleFonts.inter(
              color: isSelected ? Colors.black : Colors.grey[600],
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 16,
            ),
          ),
        ),
        if (isSelected)
          Transform.translate(
            offset: const Offset(0, -10),
            child: Container(
              height: 2,
              width: 70,
              color: Colors.brown[600],
              margin: const EdgeInsets.only(top: 1),
            ),
          ),
      ],
    );
  }
}

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

    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: effectiveIsOn ? Colors.white : Colors.black,
              width: 4,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: effectiveIsOn ? Colors.white : Colors.black,
                size: 35,
              ),
              const SizedBox(height: 1),

              Text(
                applianceName,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: effectiveIsOn ? Colors.white : Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              Text(
                roomName,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: effectiveIsOn ? Colors.white : Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              Text(
                deviceType,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: effectiveIsOn ? Colors.white : Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 1),
              Text(
                effectiveIsOn ? 'ON' : 'OFF',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: effectiveIsOn ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
        ),

        Positioned(
          top: 10,
          right: 9,
          child: InkWell(
            onTap: () {
              if (applianceStatus == 'ON') {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "Turn off the appliance before editing.",
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                    behavior: SnackBarBehavior.floating,
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
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color:
                    effectiveIsOn
                        ? Colors.white30
                        : Colors.grey.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.edit,
                size: 16,
                color: effectiveIsOn ? Colors.white : Colors.black,
              ),
            ),
          ),
        ),
      ],
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
