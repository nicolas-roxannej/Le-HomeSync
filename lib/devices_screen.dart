import 'package:flutter/material.dart';
import 'package:homesync/adddevices.dart';
import 'package:homesync/notification_screen.dart';
import 'package:weather/weather.dart';
import 'package:homesync/welcome_screen.dart';
import 'package:homesync/relay_state.dart';
import 'package:homesync/databaseservice.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/usage.dart';
import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  StreamSubscription? _appliancesSubscription;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _devices = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredDevices = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _masterPowerButtonState = false;

  UsageService? _usageService;

  final FirebaseAuth _auth = FirebaseAuth.instance;

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

  Future<void> _fetchWeather() async {
    WeatherFactory wf = WeatherFactory(_apiKey);
    try {
      Weather w = await wf.currentWeatherByCityName(_cityName);
      if (mounted) {
        setState(() {
          _currentWeather = w;
        });
      }
      print("Weather fetched successfully: ${w.temperature?.celsius?.toStringAsFixed(1)}°C - ${w.weatherDescription}");
    } catch (e) {
      print("Failed to fetch weather: $e");
      if (mounted) {
        setState(() {
        });
      }
    }
  }

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
    _updateMasterPowerButtonVisualState();

    _searchController.addListener(() {
      _updateSearchQuery(_searchController.text);
    });
  }

  void _listenForRelayStateChanges() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User not authenticated. Cannot listen to relay state changes.");
      return;
    }

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
                  RelayState.irControlledStates[relay] = data['irControlled'] as bool? ?? false;
                });
              }
            }
          });
    }

    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            final data = snapshot.data()!;
            if (data['relay8'] != null) {
              setState(() {
                RelayState.relayStates['relay8'] = data['relay8'] == 'ON' ? 1 : 0;
                _masterPowerButtonState = RelayState.relayStates['relay8'] == 1;
              });
            }
          }
        });
  }

  void _listenToAppliances() {
    _appliancesSubscription?.cancel();

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

          print("Found ${_devices.length} devices from Firestore");
          print("Device fields: applianceName, applianceStatus, deviceType, icon, roomName");

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
    int masterState = RelayState.relayStates['relay8'] ?? 0;

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
    _searchController.dispose();
    super.dispose();
  }

  void _toggleMasterPower() async {
    int currentMasterState = RelayState.relayStates['relay8'] ?? 0;
    int newMasterState = 1 - currentMasterState;

    setState(() {
      RelayState.relayStates['relay8'] = newMasterState;
      _masterPowerButtonState = newMasterState == 1;
    });

    try {
      final userUid = FirebaseAuth.instance.currentUser!.uid;
      final newMasterStateString = newMasterState == 1 ? 'ON' : 'OFF';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userUid)
          .update({'relay8': newMasterStateString});

      if (newMasterState == 0) {
        List<Future<void>> updateFutures = [];

        for (int i = 1; i <= 9; i++) {
          String relayKey = 'relay$i';
          RelayState.relayStates[relayKey] = 0;
          updateFutures.add(
            FirebaseFirestore.instance
                .collection('users')
                .doc(userUid)
                .collection('relay_states')
                .doc(relayKey)
                .update({'state': 0})
          );
        }

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
        _listenToAppliances();
      }
    }
  }

  Future<void> _toggleIndividualDevice(String applianceName, String currentStatus) async {
    if (RelayState.relayStates['relay8'] == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Cannot toggle device when master power is OFF",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final deviceDoc = _devices.firstWhere((doc) => doc.data()['applianceName'] == applianceName);
    final deviceData = deviceDoc.data();
    final String relayKey = deviceData['relay'] as String? ?? '';

    if (RelayState.irControlledStates[relayKey] == true && currentStatus == 'ON') {
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
                   Navigator.of(context).pop(false);
                 },
               ),
               TextButton(
                 child: Text("Turn Off"),
                 onPressed: () {
                   Navigator.of(context).pop(true);
                 },
               ),
             ],
           );
         },
       ) ?? false;

       if (!confirmTurnOff) {
         return;
       }
    } else if (RelayState.irControlledStates[relayKey] == true && currentStatus == 'OFF') {
    }

    final newStatus = currentStatus == 'ON' ? 'OFF' : 'ON';
    try {
      print("Toggling device $applianceName from $currentStatus to $newStatus");

      final deviceDoc = _devices.firstWhere((doc) => doc.data()['applianceName'] == applianceName);
      final deviceData = deviceDoc.data();
      print("Device data: $deviceData");

      final String relayKey = deviceData['relay'] as String? ?? '';

      if (relayKey.isNotEmpty) {
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

      print("Updating appliance status in Firestore");
      Map<String, dynamic> updateData = {
  'applianceStatus': newStatus,
  'lastToggleTime': FieldValue.serverTimestamp(),
};

await FirebaseFirestore.instance
    .collection('users')
    .doc(FirebaseAuth.instance.currentUser!.uid)
    .collection('appliances')
    .doc(deviceDoc.id)
    .update(updateData);

      print("Device $applianceName toggled successfully");

      final userUid = FirebaseAuth.instance.currentUser!.uid;
      final applianceId = deviceDoc.id;
      final double wattage = (deviceData['wattage'] is num) ? (deviceData['wattage'] as num).toDouble() : 0.0;

      DocumentSnapshot userSnap = await FirebaseFirestore.instance.collection('users').doc(userUid).get();
      double kwhrRate = DEFAULT_KWHR_RATE;
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

    } catch (e) {
      print("Error toggling device $applianceName: $e");
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

                  Transform.translate(
                    offset: Offset(0, 20),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 31, vertical: 6),
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
                                    ? Text('Loading...', style: GoogleFonts.inter(fontSize: 12))
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
                              _currentWeather?.weatherDescription ?? 'Loading weather...',
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
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.black38,
                ),
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
                                color: RelayState.relayStates['relay8'] == 1 ? Colors.black : Colors.grey,
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
                                final String applianceName = deviceData['applianceName'] as String? ?? 'Unknown Device';
                                final String roomName = deviceData['roomName'] as String? ?? 'Unknown Room';
                                final String deviceType = deviceData['deviceType'] as String? ?? 'Unknown Type';
                                final String applianceStatus = deviceData['applianceStatus'] as String? ?? 'OFF';
                                final bool isOn = applianceStatus == 'ON';
                                final int iconCodePoint = (deviceData['icon'] is int) ? deviceData['icon'] as int : Icons.devices.codePoint;

                                return GestureDetector(
                                  onTap: () {
                                    if (RelayState.relayStates['relay8'] == 1) {
                                      _toggleIndividualDevice(applianceName, applianceStatus);
                                    } else {
                                       ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            "Turn on master power first",
                                            style: const TextStyle(color: Colors.white),
                                          ),
                                          backgroundColor: Colors.red,
                                          duration: const Duration(seconds: 5),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                                  onLongPress: () {
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
                                      color: RelayState.relayStates['relay8'] == 1 && isOn ? Colors.black : Colors.white,
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
                                      isOn: RelayState.relayStates['relay8'] == 1 && isOn,
                                      icon: _getIconFromCodePoint(iconCodePoint),
                                      applianceStatus: applianceStatus,
                                      masterSwitchIsOn: RelayState.relayStates['relay8'] == 1,
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
    final screenSize = MediaQuery.of(context).size;
    showModalBottomSheet(
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {},
              child: Align(
                alignment: Alignment.centerRight,
                child: Transform.translate(
                  offset: Offset(-90, -0),
                  child: Container(
                    width: screenSize.width * 0.75,
                    height: screenSize.height -0,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D3D3D),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(0),
                        bottomLeft: Radius.circular(0),
                      ),
                    ),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 60),
                        
                        Row(
                          children: [
                            Icon(Icons.home, size: 50, color: Colors.white),
                            SizedBox(width: 10),
                            Expanded( 
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FutureBuilder<String>(
                                    future: getCurrentUsername(),
                                    builder: (context, snapshot) {
                                      return Text(
                                        snapshot.data ?? "User",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      );
                                    },
                                  ),
                                  Text(
                                    _auth.currentUser?.email ?? "No email",
                                    style: GoogleFonts.inter(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis, 
                                    maxLines: 1, 
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 40),
                        
                        ListTile(
                          leading: Icon(Icons.person, color: Colors.white,size: 35,),
                          title: Text('Profile', style: GoogleFonts.inter( color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/profile');
                          },
                        ),  

                        SizedBox(height: 15),
                        ListTile(
                          leading: Icon(Icons.notifications, color: Colors.white, size: 35,),
                          title: Text('Notification', style: GoogleFonts.inter(color: Colors.white)),
                           onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => NotificationScreen()),
                            );
                          },
                        ),  
                         SizedBox(height: 15),
                        ListTile(
                          leading: Icon(Icons.info_outline, color: Colors.white, size: 35),
                          title: Text('About', style: GoogleFonts.inter(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => AboutScreen()),
                            );
                           
                          },
                        ),

                        SizedBox(height: 15),
                          ListTile(
                        leading: Padding(
                          padding: EdgeInsets.only(left: 5),
                          child: Icon(Icons.logout, color: Colors.white, size: 35,),
                        ),
                          title: Text('Logout', style: GoogleFonts.inter(color: Colors.white)),
                         onTap: () async {
                            Navigator.pop(context);
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
            padding: EdgeInsets.symmetric(horizontal:12, vertical: 8),
            minimumSize: Size(80, 36)
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
          child:Container(
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

class ON {
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
              Icon(icon, color: effectiveIsOn ? Colors.white : Colors.black, size: 35,),
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