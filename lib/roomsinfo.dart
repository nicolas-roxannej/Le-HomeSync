import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/adddevices.dart';
// Import EditDeviceScreen
import 'package:homesync/relay_state.dart'; // Re-adding for relay state management
import 'package:homesync/databaseservice.dart';
import 'package:homesync/room_data_manager.dart'; // Re-adding for room data management
import 'package:homesync/devices_screen.dart'; // Import DeviceCard from devices_screen.dart
import 'package:homesync/usage.dart'; // Import UsageTracker
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart'; // For QueryDocumentSnapshot
import 'package:firebase_auth/firebase_auth.dart'; // For user authentication

class Roomsinfo extends StatefulWidget {
  final String roomItem; // Renamed for clarity (original: RoomItem)

  const Roomsinfo({super.key, required this.roomItem});

  @override
  State<Roomsinfo> createState() => RoomsinfoState();
}

class RoomsinfoState extends State<Roomsinfo> {
  final RoomDataManager _roomDataManager = RoomDataManager(); // room data manager
  StreamSubscription? _relayStateSubscription; // Add stream subscription
  final DatabaseService _dbService = DatabaseService();
  StreamSubscription? _appliancesSubscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _roomDevices = [];
  String _roomType = 'Unknown Type'; // State variable for room type
  UsageService? _usageService;

  @override
  void initState() {
    super.initState();
    _usageService = UsageService(); // Initialize UsageService
    _listenForRelayStateChanges(); // Start listening for relay changes
    _listenToRoomAppliances();
    _fetchRoomType(); // Fetch room type
  }

  @override
  void dispose() {
    _relayStateSubscription?.cancel(); // Cancel the relay subscription
    _appliancesSubscription?.cancel();
    super.dispose();
  }

  void _fetchRoomType() async {
    final roomDetails = await _roomDataManager.fetchRoomDetails(widget.roomItem);
    if (mounted && roomDetails != null) {
      setState(() {
        _roomType = roomDetails['roomType'] as String? ?? 'Unknown Type';
      });
    }
  }

  void _listenToRoomAppliances() {
    _appliancesSubscription?.cancel();
    
    // First check if the user is authenticated
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User not authenticated. Cannot fetch appliances.");
      setState(() {
        _roomDevices = [];
      });
      return;
    }
    
    print("Authenticated user: ${user.email}");
    print("Fetching devices for room: ${widget.roomItem}"); // Log the room name being filtered
    
    // Access the user-specific 'appliances' subcollection and filter by room name
    _appliancesSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid) // Use the current user's UID
        .collection('appliances')
        .where('roomName', isEqualTo: widget.roomItem) // Filter by room name
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _roomDevices = snapshot.docs;
          
          print("Found ${_roomDevices.length} devices for room ${widget.roomItem}");
          print("Device fields: applianceName, applianceStatus, deviceType, icon, roomName");
          
          // Log the devices for debugging, including their roomName
          for (var doc in _roomDevices) {
            final data = doc.data();
            print("Fetched Device: ${data['applianceName']} - Room: ${data['roomName']} - Status: ${data['applianceStatus']}");
          }
        });
      }
    }, onError: (error) {
      print("Error listening to room appliances for ${widget.roomItem}: $error");
      if (mounted) {
        setState(() {
          _roomDevices = [];
        });
      }
    });
  }

  void _listenForRelayStateChanges() {
    // Use Firestore to listen for relay state changes
    for (String relay in RelayState.relayStates.keys) {
      _relayStateSubscription = FirebaseFirestore.instance
          .collection('relay_states')
          .doc(relay)
          .snapshots()
          .listen((snapshot) {
            if (snapshot.exists && snapshot.data() != null) {
              final data = snapshot.data()!;
              if (data['state'] != null) {
                setState(() {
                  RelayState.relayStates[relay] = data['state'] as int;
                  print("Updated relay state: $relay = ${data['state']}");
                });
              }
            } else {
              // If document doesn't exist, create it with default state (0 = OFF)
              FirebaseFirestore.instance
                  .collection('relay_states')
                  .doc(relay)
                  .set({'state': 0});
            }
          }, onError: (error) {
            print("Error listening to relay state for $relay: $error");
          });
    }
  }

  Future<void> _toggleDeviceStatus(String applianceId, String currentStatus) async {
    // Check if master switch is ON
    if (RelayState.relayStates['relay8'] == 0) {
      // If master switch is OFF, do nothing and show a message
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Cannot toggle device when master power is OFF")),
        );
      }
      return;
    }

    final newStatus = currentStatus == 'ON' ? 'OFF' : 'ON';
    try {
      print("Toggling device $applianceId from $currentStatus to $newStatus in room ${widget.roomItem}");
      
      // Get the relay associated with this appliance
      final deviceDoc = _roomDevices.firstWhere((doc) => doc.id == applianceId);
      final deviceData = deviceDoc.data();
      final String relayKey = deviceData['relay'] as String? ?? '';
      
      if (relayKey.isNotEmpty) {
        // Update relay state in Firestore
        int newRelayState = newStatus == 'ON' ? 1 : 0;
        RelayState.relayStates[relayKey] = newRelayState;
        
        print("Updating relay state: $relayKey to $newRelayState");
        await FirebaseFirestore.instance
            .collection('relay_states')
            .doc(relayKey)
            .set({'state': newRelayState});
      }
      
      // Update appliance status in Firestore directly in the user's subcollection
      print("Updating appliance status in Firestore");
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid) // Use the current user's UID
          .collection('appliances')
          .doc(applianceId)
          .update({'applianceStatus': newStatus});

      // Call UsageService to handle the toggle
      final userUid = FirebaseAuth.instance.currentUser!.uid;
      final double wattage = (deviceData['wattage'] is num) ? (deviceData['wattage'] as num).toDouble() : 0.0;

      // Fetch user's kWh rate
      DocumentSnapshot userSnap = await FirebaseFirestore.instance.collection('users').doc(userUid).get();
      double kwhrRate = DEFAULT_KWHR_RATE; // Use default from usage.dart
      if (userSnap.exists && userSnap.data() != null) {
          kwhrRate = ((userSnap.data() as Map<String,dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
      }

      await _usageService?.handleApplianceToggle(
        userId: userUid,
        applianceId: applianceId,
        isOn: newStatus == 'ON',
        wattage: wattage,
        kwhrRate: kwhrRate,
      );
          
      print("Device $applianceId toggled successfully");
    } catch (e) {
      print("Error toggling device $applianceId in room ${widget.roomItem}: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update $applianceId: ${e.toString()}")),
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
          // When adding a device from a room screen, you might pre-fill the roomName
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddDeviceScreen(initialRoomName: widget.roomItem)),
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
              Container(
                padding: const EdgeInsets.only(top: 30),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 50, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      widget.roomItem,
                      style: GoogleFonts.jaldi(
                        textStyle: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _roomDevices.isEmpty
                    ? Center(child: Text("No devices found in ${widget.roomItem}.",
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: Colors.grey[700],
                        ),
                      ))
                    : GridView.builder(
                        padding: const EdgeInsets.only(top: 20, bottom: 70),
                        itemCount: _roomDevices.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemBuilder: (context, index) {
                          final deviceDoc = _roomDevices[index];
                          final deviceData = deviceDoc.data();
                          final String applianceId = deviceDoc.id;
                          final String relayKey = deviceData['relay'] as String? ?? '';

                          // Extract all required fields from Firestore
                          final String applianceName = deviceData['applianceName'] as String? ?? 'Unknown Device';
                          final String roomName = deviceData['roomName'] as String? ?? 'Unknown Room';
                          final String deviceType = deviceData['deviceType'] as String? ?? 'Unknown Type';
                          final String applianceStatus = deviceData['applianceStatus'] as String? ?? 'OFF';
                          final bool isOn = applianceStatus == 'ON';
                          final int iconCodePoint = (deviceData['icon'] is int) ? deviceData['icon'] as int : Icons.devices.codePoint;

                          // Get the master switch state from RelayState
                          final bool masterSwitchIsOn = RelayState.relayStates['relay8'] == 1;

                          return GestureDetector(
                            onTap: () {
                              _toggleDeviceStatus(applianceId, applianceStatus);
                            },
                            onLongPress: () {
                              Navigator.pushNamed(
                                context,
                                '/deviceinfo',
                                arguments: {
                                  'applianceId': applianceId,
                                  'deviceName': applianceName,
                                },
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                // Use the same color logic as in devices_screen.dart
                                color: masterSwitchIsOn && isOn ? Colors.black : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.3),
                                    spreadRadius: 1,
                                    blurRadius: 3,
                                    offset: Offset(0, 2),
                                  )
                                ]
                              ),
                              child: DeviceCard( // Use the DeviceCard from devices_screen.dart
                                applianceId: applianceId,
                                applianceName: applianceName,
                                roomName: roomName,
                                deviceType: deviceType,
                                isOn: isOn, // Pass individual device state
                                icon: _getIconFromCodePoint(iconCodePoint),
                                applianceStatus: applianceStatus, // Pass applianceStatus
                                masterSwitchIsOn: masterSwitchIsOn, // Pass master switch state
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
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