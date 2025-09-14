import 'package:flutter/material.dart';
import 'package:homesync/adddevices.dart';
import 'package:homesync/notification_screen.dart';
import 'package:weather/weather.dart'; // Added weather import
import 'package:homesync/welcome_screen.dart';
import 'package:homesync/relay_state.dart'; // Re-adding for relay state management
import 'package:homesync/databaseservice.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/usage.dart'; // Import UsageTracker
import 'dart:async';
import 'dart:math'; // For min function
import 'package:firebase_auth/firebase_auth.dart'; // Added import for FirebaseAuth
import 'package:cloud_firestore/cloud_firestore.dart'; // For QueryDocumentSnapshot

// TODO: Replace 'YOUR_API_KEY' with your actual OpenWeatherMap API key
const String _apiKey = 'YOUR_API_KEY'; // Placeholder for Weather API Key
const String _cityName = 'Manila'; // Default city for weather

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => DevicesScreenState();
}

class DevicesScreenState extends State<DevicesScreen> {
  Weather? _currentWeather; // Added weather state variable
  int _selectedIndex = 1;
  final DatabaseService _dbService = DatabaseService();
  StreamSubscription? _appliancesSubscription;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _devices = []; // To store appliance documents
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredDevices = []; // To store filtered devices
  final TextEditingController _searchController = TextEditingController(); // Search controller
  String _searchQuery = ''; // Current search query

  // Local state for master power button visual, true if it's in "ON" commanding mode
  bool _masterPowerButtonState = false;

  // UsageService instance
  UsageService? _usageService;

  // Method to get username from Firestore
  Future<String> getCurrentUsername() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
          return userData['username'] ?? ' ';
        }
      }
      return ' ';
    } catch (e) {
      print('Error fetching username: $e');
      return ' ';
    }
  }

  // Added weather fetching method
  Future<void> _fetchWeather() async {
    if (_apiKey == 'YOUR_API_KEY') {
      print("Weather API key is a placeholder. Please replace it.");
      if (mounted) {
        setState(() {
          // Keep _currentWeather as null to show placeholder
        });
      }
      return;
    }
    WeatherFactory wf = WeatherFactory(_apiKey);
    try {
      Weather w = await wf.currentWeatherByCityName(_cityName);
      if (mounted) {
        setState(() {
          _currentWeather = w;
        });
      }
    } catch (e) {
      print("Failed to fetch weather: $e");
      if (mounted) {
        // Handle weather fetch error, e.g., show a default or error message
      }
    }
  }

  // Search filtering method
  void _filterDevices() {
    setState(() {
      if (_searchQuery.isEmpty) {
        _filteredDevices = List.from(_devices);
      } else {
        _filteredDevices = _devices.where((deviceDoc) {
          final deviceData = deviceDoc.data();
          final String applianceName = (deviceData['applianceName'] as String? ?? '').toLowerCase();
          final String roomName = (deviceData['roomName'] as String? ?? '').toLowerCase();
          final String deviceType = (deviceData['deviceType'] as String? ?? '').toLowerCase();
          final String searchLower = _searchQuery.toLowerCase();
          
          return applianceName.contains(searchLower) ||
                 roomName.contains(searchLower) ||
                 deviceType.contains(searchLower);
        }).toList();
      }
    });
  }

  // Search query update method
  void _updateSearchQuery(String query) {
    _searchQuery = query;
    _filterDevices();
  }

  @override
  void initState() {
    super.initState();
    _usageService = UsageService(); // Initialize UsageService
    _fetchWeather(); // Fetch weather data
    _listenToAppliances();
    _listenForRelayStateChanges();
    _updateMasterPowerButtonVisualState();

    // Initialize search controller listener
    _searchController.addListener(() {
      _updateSearchQuery(_searchController.text);
    });

    // User authentication check is handled within methods that need userId.
  }

  void _listenForRelayStateChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User not authenticated. Cannot listen to relay state changes.");
      return;
    }

    // Listen for individual relay state changes (relay1-relay9) in the subcollection
    for (int i = 1; i <= 9; i++) {
      String relay = 'relay$i';
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('relay_states')
          .doc(relay)
          .snapshots()
          .listen((snapshot) {
            if (snapshot.exists && snapshot.data() != null) {
              final data = snapshot.data()!;
              if (data['state'] != null) {
                setState(() {
                  RelayState.relayStates[relay] = data['state'] as int;
                  // Also read the irControlled flag
                  RelayState.irControlledStates[relay] = data['irControlled'] as bool? ?? false;
                });
              }
            }
          });
    }

    // Listen for master relay state change (relay10) directly under the user document
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final data = snapshot.data()!;
            if (data['relay10'] != null) {
              setState(() {
                // Convert string state ('ON'/'OFF') to integer (1/0)
                RelayState.relayStates['relay10'] = data['relay10'] == 'ON' ? 1 : 0;
                _masterPowerButtonState = RelayState.relayStates['relay10'] == 1;
              });
            }
          }
        });
  }

  void _listenToAppliances() {
    _appliancesSubscription?.cancel(); // Cancel any existing subscription

    // First check if the user is authenticated
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User not authenticated. Cannot fetch appliances.");
      setState(() {
        _devices = [];
        _filteredDevices = [];
      });
      return;
    }

    print("Authenticated user: ${user.email}");

    // Access the user-specific 'appliances' subcollection
    _appliancesSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid) // Use the current user's UID
        .collection('appliances')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          // Get all devices from Firestore
          _devices = snapshot.docs;
          // Apply current search filter
          _filterDevices();

          print("Found ${_devices.length} devices from Firestore");
          print("Device fields: applianceName, applianceStatus, deviceType, icon, roomName");

          // Log the first few devices for debugging
          for (int i = 0; i < min(_devices.length, 3); i++) {
            final data = _devices[i].data();
            print("Device ${i+1}: ${data['applianceName']} (${data['roomName']}) - ${data['applianceStatus']}");
          }
        });
        _updateMasterPowerButtonVisualState();
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

  void _updateMasterPowerButtonVisualState() {
    // Check if relay10 state is available
    int masterState = RelayState.relayStates['relay10'] ?? 0;

    // Master power button shows "ON" if relay10 is ON
    if (mounted) {
      setState(() {
        _masterPowerButtonState = masterState == 1;
      });
    }

    print("Master power button state: ${_masterPowerButtonState ? 'ON' : 'OFF'}");
  }


  @override
  void dispose() {
    _appliancesSubscription?.cancel();
    _searchController.dispose(); // Dispose search controller
    super.dispose();
  }

  void _toggleMasterPower() async {
    // Toggle the master relay (relay10)
    int currentMasterState = RelayState.relayStates['relay10'] ?? 0;
    int newMasterState = 1 - currentMasterState; // Toggle between 0 and 1

    // Update local state immediately for responsiveness
    setState(() {
      RelayState.relayStates['relay10'] = newMasterState;
      _masterPowerButtonState = newMasterState == 1;
    });

    // Update Firebase RTDB for relay10
    try {
      // Update relay10 field directly under user document with string state
      final userUid = FirebaseAuth.instance.currentUser!.uid;
      final newMasterStateString = newMasterState == 1 ? 'ON' : 'OFF';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userUid)
          .update({'relay10': newMasterStateString});

      // If turning OFF master switch, turn off all devices
      if (newMasterState == 0) {
        List<Future<void>> updateFutures = [];

        // Update all relays in RTDB (assuming still in subcollection for now)
        for (int i = 1; i <= 9; i++) {
          String relayKey = 'relay$i';
          RelayState.relayStates[relayKey] = 0;
          updateFutures.add(
            FirebaseFirestore.instance
                .collection('users')
                .doc(userUid)
                .collection('relay_states')
                .doc(relayKey)
                .update({'state': 0}) // Use update instead of set
          );
        }

        // Update all appliances in Firestore in the user's subcollection
        for (var deviceDoc in _devices) {
          updateFutures.add(
            FirebaseFirestore.instance
                .collection('users')
                .doc(userUid)
                .collection('appliances')
                .doc(deviceDoc.id)
                .update({'applianceStatus': 'OFF'})
          );
        }

        await Future.wait(updateFutures);
      }

      print("Master power toggled to ${newMasterState == 1 ? 'ON' : 'OFF'}");
    } catch (e) {
      print("Error during master power toggle: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error toggling master power: ${e.toString()}")),
        );
        // Revert visual state if error
        _listenToAppliances(); // Refresh states from DB
      }
    }
  }

  Future<void> _toggleIndividualDevice(String applianceName, String currentStatus) async {
    // Check if master switch is OFF
    if (RelayState.relayStates['relay10'] == 0) {
      // If master switch is OFF, do nothing
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cannot toggle device when master power is OFF")),
      );
      return;
    }

    // Get the relay associated with this appliance using applianceName
    final deviceDoc = _devices.firstWhere((doc) => doc.data()['applianceName'] == applianceName);
    final deviceData = deviceDoc.data();
    final String relayKey = deviceData['relay'] as String? ?? '';

    // Check if the relay is currently IR controlled AND the user is trying to turn it OFF
    if (RelayState.irControlledStates[relayKey] == true && currentStatus == 'ON') {
       // Show confirmation dialog
       bool confirmTurnOff = await showDialog(
         context: context,
         builder: (BuildContext context) {
           return AlertDialog(
             title: Text("Confirm Turn Off"),
             content: Text("This device is currently controlled by IR. Do you want to force it OFF?"),
             actions: <Widget>[
               TextButton(
                 child: Text("Cancel"),
                 onPressed: () {
                   Navigator.of(context).pop(false); // Return false on cancel
                 },
               ),
               TextButton(
                 child: Text("Turn Off"),
                 onPressed: () {
                   Navigator.of(context).pop(true); // Return true on confirm
                 },
               ),
             ],
           );
         },
       ) ?? false; // Default to false if dialog is dismissed

       if (!confirmTurnOff) {
         return; // If user cancels, do not proceed
       }
       // If user confirms, proceed to turn off
    } else if (RelayState.irControlledStates[relayKey] == true && currentStatus == 'OFF') {
        // If IR is controlling and the device is already OFF, allow toggling ON
        // No confirmation needed in this case based on the prompt
    }


    final newStatus = currentStatus == 'ON' ? 'OFF' : 'ON';
    try {
      print("Toggling device $applianceName from $currentStatus to $newStatus");

      // Get the relay associated with this appliance using applianceName
      final deviceDoc = _devices.firstWhere((doc) => doc.data()['applianceName'] == applianceName);
      final deviceData = deviceDoc.data();
      print("Device data: $deviceData");

      final String relayKey = deviceData['relay'] as String? ?? '';

      if (relayKey.isNotEmpty) {
        // Update relay state in Firestore (assuming still in subcollection for now)
        int newRelayState = newStatus == 'ON' ? 1 : 0;
        RelayState.relayStates[relayKey] = newRelayState;

        print("Updating relay state: $relayKey to $newRelayState");
        final userUid = FirebaseAuth.instance.currentUser!.uid;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userUid)
            .collection('relay_states')
            .doc(relayKey)
            .update({'state': newRelayState});
      }

      // Update appliance status in Firestore directly using the document ID
      print("Updating appliance status in Firestore");
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid) // Use the current user's UID
          .collection('appliances')
          .doc(deviceDoc.id) // Use the document ID
          .update({'applianceStatus': newStatus});

      print("Device $applianceName toggled successfully");

      // Record usage time after successful toggle
      final userUid = FirebaseAuth.instance.currentUser!.uid;
      final applianceId = deviceDoc.id;
      final double wattage = (deviceData['wattage'] is num) ? (deviceData['wattage'] as num).toDouble() : 0.0; // Fetch wattage

      // Fetch user's kWh rate
      DocumentSnapshot userSnap = await FirebaseFirestore.instance.collection('users').doc(userUid).get();
      double kwhrRate = DEFAULT_KWHR_RATE; // Use default from usage.dart
      if (userSnap.exists && userSnap.data() != null) {
          kwhrRate = ((userSnap.data() as Map<String,dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
      }

      // Call UsageService to handle the toggle
      await _usageService?.handleApplianceToggle(
        userId: userUid,
        applianceId: applianceId,
        isOn: newStatus == 'ON',
        wattage: wattage,
        kwhrRate: kwhrRate,
      );

    } catch (e) {
      print("Error toggling device $applianceName: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update $applianceName: ${e.toString()}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // final screenSize = MediaQuery.of(context).size; // Not used currently
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
              // Updated header section to match homepage design
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
                            child: Icon(Icons.home, color: Colors.black, size: 35),
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

                  // Updated weather section to match homepage
                  Transform.translate(
                    offset: Offset(0, 20),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.cloud_circle_sharp, size: 35, color: Colors.lightBlue),
                              SizedBox(width: 4),
                              Transform.translate(
                                offset: Offset(0, -5),
                                child: _currentWeather == null
                                    ? (_apiKey == 'YOUR_API_KEY'
                                        ? Text('Set API Key', style: GoogleFonts.inter(fontSize: 12))
                                        : Text('Loading...', style: GoogleFonts.inter(fontSize: 12)))
                                    : Text(
                                        '${_currentWeather?.temperature?.celsius?.toStringAsFixed(0) ?? '--'}°C',
                                        style: GoogleFonts.inter(fontSize: 16),
                                      ),
                              ),
                            ],
                          ),
                          Transform.translate(
                            offset: Offset(40, -15),
                            child: Text(
                              _currentWeather?.weatherDescription ?? (_apiKey == 'YOUR_API_KEY' ? 'Weather' : 'Fetching weather...'),
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

              // Navigation Tabs
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
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.black38,
                ),
              ),

              // UPDATED: Made the entire content area scrollable
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
                                  suffixIcon: _searchQuery.isNotEmpty
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
                                  contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                                ),
                                style: TextStyle(fontSize: 16),
                                onChanged: (value) {
                                 
                                },
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: RelayState.relayStates['relay10'] == 1 ? Colors.black : Colors.grey, // Use relay10 state
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
                      
                      // UPDATED: Device grid now uses filtered devices
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
                                )
                              ),
                            )
                          : GridView.builder(
                              shrinkWrap: true, 
                              physics: NeverScrollableScrollPhysics(), 
                              padding: const EdgeInsets.only(bottom: 70),
                              itemCount: _filteredDevices.length,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemBuilder: (context, index) {
                                final deviceDoc = _filteredDevices[index];
                                final deviceData = deviceDoc.data();
                                // Extract all required fields from Firestore
                                final String applianceName = deviceData['applianceName'] as String? ?? 'Unknown Device';
                                final String roomName = deviceData['roomName'] as String? ?? 'Unknown Room';
                                final String deviceType = deviceData['deviceType'] as String? ?? 'Unknown Type';
                                final String applianceStatus = deviceData['applianceStatus'] as String? ?? 'OFF';
                                final bool isOn = applianceStatus == 'ON';
                                final int iconCodePoint = (deviceData['icon'] is int) ? deviceData['icon'] as int : Icons.devices.codePoint;

                                return GestureDetector(
                                  onTap: () {
                                    // Only allow toggling if master switch is ON
                                    if (RelayState.relayStates['relay10'] == 1) {
                                      _toggleIndividualDevice(applianceName, applianceStatus); // Use applianceName as identifier
                                    } else {
                                       ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Turn on master power first")),
                                      );
                                    }
                                  },
                                  onLongPress: () { // Navigate to device info on long press
                                  Navigator.pushNamed(
                                    context,
                                    '/editdevice',
                                    arguments: {
                                      'applianceId': deviceDoc.id,
                                    },
                                  );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      // Change color based on individual state AND master switch state
                                      color: RelayState.relayStates['relay10'] == 1 && isOn ? Colors.black : Colors.white,
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
                                    child: DeviceCard(
                                      applianceName: applianceName,
                                      roomName: roomName,
                                      deviceType: deviceType,
                                      // Pass individual state, but consider master switch for visual
                                      isOn: RelayState.relayStates['relay10'] == 1 && isOn,
                                      icon: _getIconFromCodePoint(iconCodePoint),
                                      applianceStatus: applianceStatus, // Pass applianceStatus
                                      masterSwitchIsOn: RelayState.relayStates['relay10'] == 1, // Pass master switch state
                                      applianceId: deviceDoc.id, // Pass applianceId
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
    final screenSize = MediaQuery.of(context).size;
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Align(
          alignment: Alignment.centerRight,
          child: Transform.translate(
            offset: const Offset(-90, 0), // Adjust if necessary for your layout
            child: Container(
              width: screenSize.width * 0.75,
              height: screenSize.height,
              decoration: const BoxDecoration(
                color: Color(0xFF3D3D3D),
                // borderRadius: BorderRadius.only( // Full height, no specific radius needed
                //   topLeft: Radius.circular(0),
                //   bottomLeft: Radius.circular(0),
                // ),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 60),
                  Row(
                    children: [
                      const Icon(Icons.home, size: 50, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded( 
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Updated to use FutureBuilder for username
                            FutureBuilder<String>(
                              future: getCurrentUsername(),
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.data ?? "User", // Display username or "User" as fallback
                                  style: TextStyle(
                                    color: Colors.white, 
                                    fontSize: 20, 
                                    fontWeight: FontWeight.bold
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                );
                              },
                            ),
                            Text(
                              _auth.currentUser?.email ?? "email@example.com", // Display user email
                              style: GoogleFonts.inter(color: Colors.white70, fontSize: 14),
                              overflow: TextOverflow.ellipsis, 
                              maxLines: 1, 
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  ListTile(
                    leading: const Icon(Icons.person, color: Colors.white, size: 35),
                    title: Text('Profile', style: GoogleFonts.inter(color: Colors.white)),
                    onTap: () {
                    
                       Navigator.pushNamed(context, '/profile'); // Navigate to profile
                    }
                  ),
                  const SizedBox(height: 15),
                  ListTile(
                    leading: const Icon(Icons.notifications, color: Colors.white, size: 35),
                    title: Text('Notification', style: GoogleFonts.inter(color: Colors.white)),
                    onTap: () {
                      
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => NotificationScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  ListTile(
                    leading: const Padding(
                      padding: EdgeInsets.only(left: 5), // Align icon
                      child: Icon(Icons.logout, color: Colors.white, size: 35),
                    ),
                    title: Text('Logout', style: GoogleFonts.inter(color: Colors.white)),
                    onTap: () async {
                      await _auth.signOut();
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => WelcomeScreen()),
                        (Route<dynamic> route) => false,
                      );
                    },
                  ),
                ],
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
                Navigator.pushNamed(context, '/homepage'); // Assuming '/homepage' is your electricity screen route
                break;
              case 1:
                // Already on Devices screen, do nothing or refresh
                break;
              case 2:
                Navigator.pushNamed(context, '/rooms');
                break;
            }
          },
          style: TextButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal:12, vertical: 8),
            minimumSize: Size(80, 36) // Ensure buttons have a decent tap area
          ),
          child: Text(
            title,
            style: GoogleFonts.inter(
              color: isSelected ? Colors.black : Colors.grey[600],
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 16, // Slightly adjusted size
            ),
          ),
        ),
        if (isSelected)
        Transform.translate(
            offset: const Offset(0, -10),
          child:Container(
            height: 2, // Slightly thicker underline
            width: 70, // Width of underline
            color: Colors.brown[600], // Darker brown
            margin: const EdgeInsets.only(top: 1), // Closer to text
          ),
        ),
      ],
    );
  }
}

// DeviceCard widget with updated UI architecture
class DeviceCard extends StatelessWidget {
  final String applianceName;
  final String roomName;
  final String deviceType;
  final bool isOn;
  final IconData icon;
  final String applianceStatus; // Added applianceStatus
  final bool masterSwitchIsOn; // Added master switch state
  final String applianceId; // Added applianceId

  const DeviceCard({
    super.key,
    required this.applianceName,
    required this.roomName,
    required this.deviceType,
    required this.isOn,
    required this.icon,
    required this.applianceStatus, // Added applianceStatus
    required this.masterSwitchIsOn, // Added master switch state
    required this.applianceId, // Added applianceId
  });

  @override
  Widget build(BuildContext context) {
    // Determine the effective state for visual representation
    final bool effectiveIsOn = masterSwitchIsOn && isOn;

    return Stack(
      children: [     // box switch container
        Container(
          width: double.infinity, // Take full width of Grid cell
          height: double.infinity, // Take full height of Grid cell
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
            crossAxisAlignment: CrossAxisAlignment.center, // Align text to center
            children: [
              Icon(icon, color: effectiveIsOn ? Colors.white : Colors.black, size: 35,), // Adjusted size
              const SizedBox(height: 1),

              // Appliance Name
              Text(
                applianceName,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14, // Consistent font size
                  fontWeight: FontWeight.bold,
                  color: effectiveIsOn ? Colors.white : Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Room Name
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

              // Device Type
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
              Text(  // status
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

        // Edit btn in corner
        Positioned(
          top: 10,
          right: 9,
          child: InkWell(
            onTap: () {
              if (applianceStatus == 'ON') {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Turn off the appliance before editing.")),
                );
              } else {
                // Navigate to schedule or edit screen
                Navigator.pushNamed(
                  context,
                  '/editdevice',
                  arguments: {
                    'applianceId': applianceId,
                  },
                );
              }
            },
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: effectiveIsOn ? Colors.white30 : Colors.grey.withOpacity(0.3),
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

// Helper for FirebaseAuth instance, if not already available via _dbService
final FirebaseAuth _auth = FirebaseAuth.instance;

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
