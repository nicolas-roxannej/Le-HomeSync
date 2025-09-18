import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class DeviceNotif extends StatefulWidget {
  const DeviceNotif({super.key});

  @override
  State<DeviceNotif> createState() => DeviceNotifState();
}

class DeviceNotifState extends State<DeviceNotif> {
  Map<String, bool> _notifications = {};
  bool _isLoading = true;
  StreamSubscription? _appliancesSubscription;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadUserAppliances();
  }

  @override
  void dispose() {
    _appliancesSubscription?.cancel();
    super.dispose();
  }

  
  void _loadUserAppliances() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("User not authenticated. Cannot fetch appliances.");
      setState(() {
        _notifications = {};
        _isLoading = false;
        _errorMessage = 'User not authenticated';
      });
      return;
    }

    print("Loading appliances for user: ${user.email}");

    
    _appliancesSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('appliances')
        .snapshots()
        .listen((snapshot) {
      print("Received ${snapshot.docs.length} appliances from Firestore");
      if (mounted) {
        if (snapshot.docs.isEmpty) {
          setState(() {
            _notifications = {};
            _isLoading = false;
            _errorMessage = '';
          });
        } else {
          _processAppliances(snapshot.docs);
        }
      }
    }, onError: (error) {
      print("Error listening to appliances: $error");
      if (mounted) {
        setState(() {
          _notifications = {};
          _isLoading = false;
          _errorMessage = 'Error loading appliances: $error';
        });
      }
    });
  }

  
  void _processAppliances(List<QueryDocumentSnapshot<Map<String, dynamic>>> appliances) {
    try {
      Map<String, bool> tempNotifications = {};
      
      for (var applianceDoc in appliances) {
        final applianceData = applianceDoc.data();
        final String applianceName = applianceData['applianceName'] ?? 'Unknown Device';
        
        
        tempNotifications[applianceName] = true;
        
        print("Added appliance to notifications: $applianceName");
      }

      setState(() {
        _notifications = tempNotifications;
        _isLoading = false;
        _errorMessage = '';
      });

      print("Successfully loaded ${_notifications.length} appliances for notifications");
      
      
      _loadSavedPreferences(appliances);
      
    } catch (e) {
      print('Error processing appliances: $e');
      setState(() {
        _notifications = {};
        _isLoading = false;
        _errorMessage = 'Error processing appliances: $e';
      });
    }
  }

  
  Future<void> _loadSavedPreferences(List<QueryDocumentSnapshot<Map<String, dynamic>>> appliances) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (userDoc.exists) {
        Map<String, dynamic>? userData = userDoc.data() as Map<String, dynamic>?;
        Map<String, dynamic> notificationPrefs = userData?['notificationPreferences'] ?? {};

        if (notificationPrefs.isNotEmpty) {
          Map<String, bool> updatedNotifications = Map.from(_notifications);
          
          for (var applianceDoc in appliances) {
            final applianceData = applianceDoc.data();
            final String applianceName = applianceData['applianceName'] ?? 'Unknown Device';
            
            // Update with saved preference if it exists
            if (notificationPrefs.containsKey(applianceDoc.id)) {
              updatedNotifications[applianceName] = notificationPrefs[applianceDoc.id] ?? true;
            }
          }

          setState(() {
            _notifications = updatedNotifications;
          });
          
          print("Loaded saved notification preferences");
        }
      }
    } catch (e) {
      print('Error loading saved preferences: $e');
     
    }
  }

  
  Future<void> _saveNotificationPreference(String applianceName, bool value) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      
      QuerySnapshot applianceQuery = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('appliances')
          .where('applianceName', isEqualTo: applianceName)
          .limit(1)
          .get();

      if (applianceQuery.docs.isNotEmpty) {
        String applianceId = applianceQuery.docs.first.id;
        
        
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
              'notificationPreferences': {
                applianceId: value
              }
            }, SetOptions(merge: true));

        print("Saved notification preference for $applianceName: $value");
      }
    } catch (e) {
      print('Error saving notification preference: $e');
    }
  }

  IconData _getIcon(String name) {
    String lowerName = name.toLowerCase();
    if (lowerName.contains('light')) {
      return Icons.light;
    } else if (lowerName.contains('plug')) {
      return Icons.power;
    } else if (lowerName.contains('fan')) {
      return Icons.air;
    } else if (lowerName.contains('tv') || lowerName.contains('television')) {
      return Icons.tv;
    } else if (lowerName.contains('ac') || lowerName.contains('air conditioner')) {
      return Icons.ac_unit;
    } else if (lowerName.contains('heater')) {
      return Icons.local_fire_department;
    } else if (lowerName.contains('speaker')) {
      return Icons.speaker;
    } else if (lowerName.contains('laptop') || lowerName.contains('computer')) {
      return Icons.laptop;
    } else if (lowerName.contains('microwave')) {
      return Icons.microwave;
    } else if (lowerName.contains('coffee')) {
      return Icons.coffee_maker;
    } else if (lowerName.contains('thermostat')) {
      return Icons.thermostat;
    } else if (lowerName.contains('camera')) {
      return Icons.camera;
    } else if (lowerName.contains('door')) {
      return Icons.sensor_door;
    } else if (lowerName.contains('lock')) {
      return Icons.lock;
    } else if (lowerName.contains('washing') || lowerName.contains('laundry')) {
      return Icons.local_laundry_service;
    } else if (lowerName.contains('router') || lowerName.contains('wifi')) {
      return Icons.router;
    } else if (lowerName.contains('grill')) {
      return Icons.outdoor_grill;
    } else if (lowerName.contains('alarm')) {
      return Icons.alarm;
    } else {
      return Icons.electrical_services; 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              Padding( 
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 30),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, size: 50, color: Colors.black),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 1),
                  Text(
                    'System Notification',
                     textAlign: TextAlign.center,
                  style: GoogleFonts.jaldi(
                    textStyle: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                    color: Colors.black,
                  ),
                  ),
                ],
              ),
            ),
              
              const SizedBox(height: 1),

              
              if (_errorMessage.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(12),
                  margin: EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Text(
                    'Debug: $_errorMessage',
                    style: TextStyle(color: Colors.red[800]),
                  ),
                ),

              
              Expanded(
                child: SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  child: _isLoading 
                    ? Container(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: Colors.black,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Loading your appliances...',
                                style: GoogleFonts.jaldi(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _notifications.isEmpty
                      ? Container(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.notifications_off,
                                  size: 64,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No appliances found',
                                  style: GoogleFonts.jaldi(
                                    fontSize: 20,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Add some appliances first to manage notifications',
                                  style: GoogleFonts.jaldi(
                                    fontSize: 16,
                                    color: Colors.grey[500],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isLoading = true;
                                    });
                                    _loadUserAppliances();
                                  },
                                  child: Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          constraints: BoxConstraints(
                            minHeight: 100,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: _notifications.keys.map((applianceName) {
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Icon(_getIcon(applianceName), size: 24),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  applianceName,
                                                  style: GoogleFonts.jaldi(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Switch(
                                          value: _notifications[applianceName]!,
                                          onChanged: (val) {
                                            setState(() {
                                              _notifications[applianceName] = val;
                                            });
                                            _saveNotificationPreference(applianceName, val);
                                          },
                                          activeColor: Colors.white,
                                          activeTrackColor: Colors.black,
                                          inactiveThumbColor: Colors.white,
                                          inactiveTrackColor: Colors.black,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (applianceName != _notifications.keys.last)
                                    Divider(
                                      thickness: 1,
                                      color: Colors.grey[400],
                                      indent: 36,
                                    ),
                                ],
                              );
                            }).toList(),
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
}