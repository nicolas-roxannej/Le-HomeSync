import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/device_usage.dart';
import 'package:homesync/usage.dart'; // Now imports UsageService
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:homesync/databaseservice.dart'; // Import DatabaseService
// Import ElectricityUsageChart
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth
// Import DetailedUsageScreen
import 'package:intl/intl.dart'; // Import for date formatting

// Adding a comment to trigger re-analysis
class DeviceInfoScreen extends StatefulWidget {
  final String applianceId; // e.g., "light1", "socket2"
  final String initialDeviceName;
  // deviceUsage might be better fetched directly or calculated from Firestore data
  // For now, let's assume it might be passed or derived.
  // final String initialDeviceUsage;

  const DeviceInfoScreen({
    super.key,
    required this.applianceId,
    required this.initialDeviceName,
    // required this.initialDeviceUsage,
  });

  @override
  DeviceInfoScreenState createState() => DeviceInfoScreenState();
}

class DeviceInfoScreenState extends State<DeviceInfoScreen> {
  final DatabaseService _dbService = DatabaseService();
  StreamSubscription? _applianceSubscription;
  final FirebaseAuth _auth = FirebaseAuth.instance; // FirebaseAuth instance
  late UsageService _usageService; // Instance of UsageService

  // State variables to hold data from Firestore and for editing
  bool _isDeviceOn = false;
  bool _isLoadingUsage = false; // Initialize to false for immediate display
  String _currentDeviceName = "";
  String _currentDeviceUsage = "0 kWh"; // Default or placeholder
  // State variable for latest daily usage
  final String _latestDailyUsage = "0 kWh";
  // State variable to toggle between latest daily usage and average usages
  final bool _showAverageUsages = false;
  // State variable to hold average usages
  Map<String, double> _averageUsages = {};
  // State variable to track the selected usage period
  final String _selectedUsagePeriod = 'daily'; // Default to daily
  bool _isRefreshing = false; // State for refresh indicator

  // Editable fields - removed _nameController since name is no longer editable
  late TextEditingController _roomController;
  late TextEditingController _typeController;
  final TextEditingController _kWhRateController = TextEditingController(text: "0.0"); // Initialize immediately
  IconData _selectedIcon = Icons.devices; // State for selected icon
  
  // Add state variable for device type dropdown
  String _deviceType = 'Light'; // Default value

  // State variable for room names
  List<String> _roomNames = [];
  String? _selectedRoom; // Added state variable for selected room

  // State variables for usage display
  String _selectedPeriod = 'Daily'; // State variable for selected period
  double _totalUsageKwh = 0.0; // State variable for total usage
  double _totalElectricityCost = 0.0; // State variable for total cost
  StreamSubscription? _periodicUsageSubscription;


  @override
  void initState() {
    super.initState();
    // Removed _nameController initialization since name is no longer editable
    _roomController = TextEditingController(); // Will be populated from fetched data
    _typeController = TextEditingController(); // Will be populated from fetched data
    _usageService = UsageService(); // Initialize UsageService
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      _listenToPeriodicUsageData(); // Changed from _calculateTotalUsageForPeriod
    } else {
       // Handle case where user is not logged in, maybe navigate to login
       print("User not logged in in initState");
       // Consider adding a check and navigation here if necessary
    }

    _listenToApplianceData();
    _fetchRooms(); // Fetch rooms when the state is initialized
  }

  @override
  void dispose() {
    _applianceSubscription?.cancel();
    _periodicUsageSubscription?.cancel(); // Cancel the new subscription
    // Removed _nameController.dispose() since it's no longer used
    _roomController.dispose();
    _typeController.dispose();
    _kWhRateController.dispose(); // Dispose the new controller
    super.dispose();
  }

  void _listenToApplianceData() {
    final userId = _auth.currentUser?.uid; // Use FirebaseAuth to get user ID
    if (userId == null) {
      print("User not logged in, cannot listen to appliance data.");
      // Handle not logged in state, maybe show an error or default view
      if (mounted) {
        setState(() {
          _currentDeviceName = "Error: Not logged in";
        });
      }
      return;
    }

    _applianceSubscription = _dbService.streamDocument(
      collectionPath: 'users/$userId/appliances',
      docId: widget.applianceId,
    ).listen((DocumentSnapshot<Map<String, dynamic>> snapshot) async { // Added async here
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        if (mounted) {
          // Fetch user document to get kwhr
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
          double userKwhrValue = (userDoc.exists && userDoc.data() != null && userDoc.data()!['kwhr'] is num) ? (userDoc.data()!['kwhr'] as num).toDouble() : 0.0;

          // Get wattage from appliance data
          final double wattage = (data['wattage'] is num) ? (data['wattage'] as num).toDouble() : 0.0;

          // _usageService is already initialized. Wattage will be passed to its methods.

          if (mounted) {
            setState(() {
              _isDeviceOn = (data['applianceStatus'] == 'ON');
              _currentDeviceName = data['applianceName'] ?? widget.initialDeviceName;

              // Populate editing fields - removed _nameController.text line
              _roomController.text = data['roomName'] ?? "";
              print("RoomController text set to: ${_roomController.text}"); // Add print statement
              _deviceType = data['deviceType'] ?? "Light"; // Set the device type for dropdown
              _typeController.text = _deviceType; // Keep controller synced for compatibility
              _selectedIcon = IconData(data['icon'] ?? Icons.devices.codePoint, fontFamily: 'MaterialIcons');

              // Use kwhr from user document
              _kWhRateController.text = userKwhrValue.toString();

              // Update usage display with accumulated kWh
              double accumulatedKwh = (data['kwh'] is num) ? (data['kwh'] as num).toDouble() : 0.0;
              _currentDeviceUsage = "${accumulatedKwh.toStringAsFixed(2)} kWh"; // Display in kWh

              // _presentHourlyUsage = (data['presentHourlyusage'] is num) ? (data['presentHourlyusage'] as num).toStringAsFixed(2) : "0.0";

              // Set the selected room based on fetched data
              _selectedRoom = data['roomName'] as String?;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _currentDeviceName = "Appliance not found";
            _isDeviceOn = false;
            _isLoadingUsage = false; // Stop loading if appliance not found
          });
        }
        print("Appliance document ${widget.applianceId} does not exist.");
      }
    }, onError: (error) {
      print("Error listening to appliance ${widget.applianceId}: $error");
      if (mounted) {
        setState(() {
          _currentDeviceName = "Error loading data";
          _isLoadingUsage = false; // Stop loading on error
        });
      }
    });
  }

  // Method to fetch room names from the database
  Future<void> _fetchRooms() async {
    print("Fetching rooms..."); // Debug print
    final userId = _auth.currentUser?.uid; // Use FirebaseAuth to get user ID
    if (userId == null) {
      print("User not logged in, cannot fetch rooms.");
      return;
    }
    try {
      final roomDocs = await _dbService.getCollection(collectionPath: 'users/$userId/Rooms'); // Corrected path
      final roomNames = roomDocs.docs.map((doc) => doc['roomName'] as String).toList(); // Fetch roomName field
      if (mounted) {
        setState(() {
          _roomNames = roomNames;
          // Set initial selected room if device data has a roomName
          if (_roomController.text.isNotEmpty && _roomNames.contains(_roomController.text)) {
            _selectedRoom = _roomController.text;
          } else if (_roomNames.isNotEmpty) {
            _selectedRoom = _roomNames.first; // Default to first room if available
            _roomController.text = _selectedRoom!;
          } else {
            _selectedRoom = null;
            _roomController.text = '';
          }
        });
      }
       print("Fetched rooms: $_roomNames"); // Debug print
    } catch (e) {
      print("Error fetching rooms: $e");
      // Handle error, maybe show a message
    }
  }

  void _addRoom() async {
    TextEditingController newRoomController = TextEditingController();
    IconData roomIconSelected = Icons.home;

    String? newRoomName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFE9E7E6),
          titleTextStyle: GoogleFonts.jaldi(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          title: Text('Add New Room'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: newRoomController,
                      style: GoogleFonts.inter(
                        textStyle: TextStyle(fontSize: 17),
                        color: Colors.black,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                        hintText: "Enter Room Name",
                        hintStyle: GoogleFonts.inter(
                          color: Colors.grey,
                          fontSize: 15,
                        ),
                        prefixIcon: Icon(
                          roomIconSelected,
                          color: Colors.black,
                          size: 24,
                        ),
                      ),
                    ),
                    SizedBox(height: 15),
                    Text(
                      'Select Icon',
                      style: GoogleFonts.jaldi(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 5),
                    Container(
                      height: 200,
                      width: double.maxFinite,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        children: const [
                        Icons.living, Icons.bed, Icons.kitchen, Icons.dining,
                        Icons.bathroom, Icons.meeting_room,Icons.garage, Icons.local_library, Icons.stairs,
                        ].map((icon) {
                          return IconButton(
                            icon: Icon(
                              icon,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                roomIconSelected = icon;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            }
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancel',
                style: GoogleFonts.jaldi(
                  textStyle: TextStyle(fontSize: 18, color: Colors.black87),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              onPressed: () async {
                if (newRoomController.text.trim().isNotEmpty) {
                  Navigator.of(context).pop(newRoomController.text.trim());
                }
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.black),
                foregroundColor: WidgetStateProperty.all(Colors.white),
              ),
              child: Text(
                'Add',
                style: GoogleFonts.jaldi(
                  textStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (newRoomName != null && newRoomName.isNotEmpty) {
      final userId = _auth.currentUser?.uid; // Use _auth instance
      if (userId != null) {
        try {
          // Add the new room to the database with both name and icon
          await _dbService.addDocumentToCollection( // Use _dbService instance
            collectionPath: 'users/$userId/Rooms', // Corrected path
            data: {
              'roomName': newRoomName,
              'icon': roomIconSelected.codePoint,
              'createdAt': FieldValue.serverTimestamp(),
            },
          );
          // Refresh the room list
          await _fetchRooms();
          // Optionally select the newly added room
          if (mounted) {
            if (_roomNames.contains(newRoomName)) {
              if (mounted) {
                setState(() {
                  _selectedRoom = newRoomName; // Update new state variable
                  _roomController.text = newRoomName;
                });
              }
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Room '$newRoomName' added successfully!"))
          );
        } catch (e) {
          print("Error adding room: $e");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error adding room: ${e.toString()}"))
          );
        }
      }
    }
  }

  // Method to fetch average usages for a specific period
  Future<void> _fetchUsageForPeriod(String period) async {
     final userId = _auth.currentUser?.uid; // Use FirebaseAuth to get user ID
     if (userId == null) {
      print("User not logged in, cannot fetch average usages.");
      return;
    }

    final applianceDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('appliances')
        .doc(widget.applianceId)
        .get();

    double wattage = 0.0;
    if (applianceDoc.exists && applianceDoc.data() != null) {
      wattage = (applianceDoc.data()!['wattage'] is num) ? (applianceDoc.data()!['wattage'] as num).toDouble() : 0.0;
    } else {
      print('Appliance ${widget.applianceId} not found or wattage not set.');
    }

    // This method needs to be rewritten to fetch data from the new Firestore structure
    // populated by UsageService. For now, it won't fetch meaningful data.
    // _usageTracker = UsageTracker(userId: userId, applianceId: widget.applianceId, wattage: wattage);

    if (mounted) {
      // try {
      //   // final usageData = await _usageTracker.getUsageData(period); // Old call
      //   // This needs to be replaced with fetching from new aggregated paths.
      //   if (mounted) {
      //     setState(() {
      //       // Update _averageUsages with the fetched data for the selected period
      //       // _averageUsages[period] = (usageData['totalKwhr'] is num) ? (usageData['totalKwhr'] as num).toDouble() : 0.0;
      //     });
      //   }
      // } catch (e) {
      //   print("Error fetching usage for $period: $e");
      //   if (mounted) {
      //      setState(() {
      //       _averageUsages[period] = 0.0;
      //      });
      //   }
      // }
      print("INFO: _fetchUsageForPeriod for '$period' needs rewrite for UsageService data structure.");
    }
  }

  // Helper for month name (consistent with UsageService)
  String _getMonthNameHelper(int month) { // Renamed to avoid conflict if class also has _getMonthName
    const monthNames = [
      '', 'january', 'february', 'march', 'april', 'may', 'june',
      'july', 'august', 'september', 'october', 'november', 'december'
    ];
    return monthNames[month].toLowerCase();
  }

  // Helper for week of month (consistent with UsageService)
  int _getWeekOfMonthHelper(DateTime date) { // Renamed
    if (date.day <= 7) return 1;
    if (date.day <= 14) return 2;
    if (date.day <= 21) return 3;
    if (date.day <= 28) return 4;
    return 5;
  }

  // Method to fetch all average usages (kept for initial load if needed elsewhere)
  Future<void> _fetchAverageUsages() async {
     final userId = _auth.currentUser?.uid; // Use FirebaseAuth to get user ID
     if (userId == null) {
      print("User not logged in, cannot fetch average usages.");
      return;
    }
    // This method needs to be rewritten for the new UsageService data structure.
    // // Ensure wattage is fetched before initializing UsageTracker
    // final applianceDoc = await FirebaseFirestore.instance
    //     .collection('users')
    //     .doc(userId)
    //     .collection('appliances')
    //     .doc(widget.applianceId)
    //     .get();

    // double wattage = 0.0;
    // if (applianceDoc.exists && applianceDoc.data() != null) {
    //   wattage = (applianceDoc.data()!['wattage'] is num) ? (applianceDoc.data()!['wattage'] as num).toDouble() : 0.0;
    // } else {
    //   print('Appliance ${widget.applianceId} not found or wattage not set.');
    // }

    // _usageTracker = UsageTracker(userId: userId, applianceId: widget.applianceId, wattage: wattage);


    // if (mounted) {
    //   try {
    //     // final averages = await _usageTracker.getAverageUsages(); // Old call
    //     if (mounted) {
    //       setState(() {
    //         // _averageUsages = Map<String, double>.from(averages); // Explicitly cast to Map<String, double>
    //       });
    //     }
    //   } catch (e) {
    //     print("Error fetching average usages: $e");
    //     if (mounted) {
    //        setState(() {
    //         _averageUsages = {
    //           'daily': 0.0,
    //           'weekly': 0.0,
    //           'monthly': 0.0,
    //           'yearly': 0.0,
    //         };
    //        });
    //     }
    //   }
    // }
    print("INFO: _fetchAverageUsages needs rewrite for UsageService data structure.");
  }

  // Function to listen to total usage and cost for the selected period for this device
  void _listenToPeriodicUsageData() {
    _periodicUsageSubscription?.cancel(); // Cancel any previous subscription

    final user = _auth.currentUser;
    if (user == null) {
      print("User not authenticated. Cannot calculate usage.");
      if (mounted) {
        setState(() {
          _totalUsageKwh = 0.0;
          _totalElectricityCost = 0.0;
          _isLoadingUsage = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingUsage = true;
      });
    }

    final userId = user.uid;
    final applianceId = widget.applianceId;
    final now = DateTime.now(); // Use current time to determine the period document
    String firestorePath;

    String yearStr = now.year.toString();
    String monthName = _getMonthNameHelper(now.month);
    int weekOfMonth = _getWeekOfMonthHelper(now);
    String dayStr = DateFormat('yyyy-MM-dd').format(now); // Current day for daily, or reference for others

    // Note: For weekly, monthly, yearly, this path points to the *current* week/month/year's document.
    // If you need to show historical data for a *specific* week/month selected by user,
    // the 'now' variable would need to be adjusted or passed in.
    // For simplicity, this implementation fetches the current period's data.
    switch (_selectedPeriod.toLowerCase()) {
      case 'daily':
        // For 'Daily', we usually want today's data.
        firestorePath = 'users/$userId/appliances/$applianceId/yearly_usage/$yearStr/monthly_usage/${monthName}_usage/week_usage/week${weekOfMonth}_usage/day_usage/$dayStr';
        break;
      case 'weekly':
        firestorePath = 'users/$userId/appliances/$applianceId/yearly_usage/$yearStr/monthly_usage/${monthName}_usage/week_usage/week${weekOfMonth}_usage';
        break;
      case 'monthly':
        firestorePath = 'users/$userId/appliances/$applianceId/yearly_usage/$yearStr/monthly_usage/${monthName}_usage';
        break;
      case 'yearly':
        firestorePath = 'users/$userId/appliances/$applianceId/yearly_usage/$yearStr';
        break;
      default:
        print('Invalid period selected: $_selectedPeriod');
        if (mounted) {
          setState(() {
            _totalUsageKwh = 0.0;
            _totalElectricityCost = 0.0;
            _isLoadingUsage = false;
          });
        }
        return;
    }
    
    print("Listening to device usage from Firestore path: $firestorePath");

    _periodicUsageSubscription = FirebaseFirestore.instance.doc(firestorePath).snapshots().listen(
      (snapshot) {
        if (mounted) {
          if (snapshot.exists && snapshot.data() != null) {
            final data = snapshot.data()!;
            setState(() {
              _totalUsageKwh = (data['kwh'] as num?)?.toDouble() ?? 0.0;
              _totalElectricityCost = (data['kwhrcost'] as num?)?.toDouble() ?? 0.0;
              _isLoadingUsage = false;
            });
          } else {
            print("Periodic usage document for appliance $applianceId not found at path: $firestorePath. Setting usage to 0.");
            setState(() {
              _totalUsageKwh = 0.0;
              _totalElectricityCost = 0.0;
              _isLoadingUsage = false;
            });
          }
        }
      },
      onError: (error) {
        print("Error listening to usage data for appliance $applianceId from $firestorePath: $error");
        if (mounted) {
          setState(() {
            _totalUsageKwh = 0.0;
            _totalElectricityCost = 0.0;
            _isLoadingUsage = false;
          });
        }
      }
    );
  }


  Future<void> _toggleDeviceStatus(bool newStatus) async {
    final newStatusString = newStatus ? 'ON' : 'OFF';
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      print("User not logged in, cannot update appliance status.");
      return;
    }

    try {
      // Fetch current appliance data to get wattage
      DocumentSnapshot applianceSnap = await FirebaseFirestore.instance
          .collection('users').doc(userId)
          .collection('appliances').doc(widget.applianceId)
          .get();

      if (!applianceSnap.exists || applianceSnap.data() == null) {
        print("Appliance data not found for ${widget.applianceId}");
        return;
      }
      Map<String, dynamic> applianceData = applianceSnap.data() as Map<String, dynamic>;
      double wattage = (applianceData['wattage'] as num?)?.toDouble() ?? 0.0;
      
      // Fetch user's kWh rate
      DocumentSnapshot userSnap = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      double kwhrRate = DEFAULT_KWHR_RATE; // Use default from usage.dart
      if (userSnap.exists && userSnap.data() != null) {
          kwhrRate = ((userSnap.data() as Map<String,dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
      }


      // Update appliance status in Firestore
      await FirebaseFirestore.instance
          .collection('users').doc(userId)
          .collection('appliances').doc(widget.applianceId)
          .update({'applianceStatus': newStatusString});

      // Call UsageService to handle the toggle
      await _usageService.handleApplianceToggle(
        userId: userId,
        applianceId: widget.applianceId,
        isOn: newStatus,
        wattage: wattage,
        kwhrRate: kwhrRate, // You might need to fetch this or have a default
      );

      // Optimistic update, or rely on stream to update _isDeviceOn
      // setState(() {
      //   _isDeviceOn = newStatus;
      // });
    } catch (e) {
      print("Error updating appliance status: $e");
      // Show a snackbar or error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update status: ${e.toString()}")),
        );
      }
    }
  }

  Future<void> _updateDeviceDetails() async {
    final userId = _auth.currentUser?.uid; // Use FirebaseAuth to get user ID
    if (userId == null) {
      print("User not logged in, cannot update appliance details.");
      return;
    }

   
    double kWhRate = double.tryParse(_kWhRateController.text) ?? 0.0;

    // Data to update on the appliance document - removed 'applianceName' since it's no longer editable
    final applianceUpdateData = {
      'roomName': _roomController.text,
      'deviceType': _deviceType,
      'icon': _selectedIcon.codePoint,
      // Remove kwhr from appliance update data
    };

    // Data to update on the user document
    final userUpdateData = {
      'kwhr': kWhRate,
    };

    try {
      // Update appliance document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .doc(widget.applianceId)
          .update(applianceUpdateData);

      // Update user document with kwhr
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update(userUpdateData);


      print("Appliance details and user kWh rate updated successfully for ${widget.applianceId}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Device details and kWh rate updated successfully!")),
        );
      }
    } catch (e) {
      print("Error updating appliance details or user kWh rate: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update details: ${e.toString()}"))
        );
      }
    }
  }

  // Method to show the icon picker dialog
  void _showIconPickerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFE9E7E6),
          title: Text('Select an Icon',
          style: GoogleFonts.jaldi(
          fontWeight: FontWeight.bold
          ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _getCommonIcons().map((IconData icon) {
                  return InkWell(
                    onTap: () {
                      if (mounted) {
                        setState(() {
                          _selectedIcon = icon;
                        });
                      }
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        
                        color: _selectedIcon.codePoint == icon.codePoint
                            ? Colors.grey[300]
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        size: 32,
                        color: Colors.black,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Cancel',
                style: GoogleFonts.jaldi(
                  textStyle: TextStyle(fontSize: 18, color: Colors.black87),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // List of common icons for devices
  List<IconData> _getCommonIcons() {
    return const [
      Icons.light, Icons.tv, Icons.power, Icons.kitchen,
          Icons.speaker, Icons.laptop, Icons.ac_unit, Icons.microwave,Icons.coffee_maker,Icons.radio_button_checked,
          Icons.thermostat,Icons.doorbell,Icons.camera,Icons.sensor_door,Icons.lock,Icons.door_sliding,Icons.local_laundry_service,
          Icons.dining,Icons.rice_bowl,Icons.wind_power,Icons.router,Icons.outdoor_grill,Icons.air,Icons.alarm,
      
    ];
  }

  @override
  Widget build(BuildContext context) {
    print("Building DeviceInfoScreen - RoomController text: ${_roomController.text}, RoomNames: $_roomNames"); // Debug print
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E7E6), // Match scaffold background
        elevation: 0, // No shadow
        leading: IconButton(
          icon: Transform.translate(
        offset: Offset(5, 0),
          child: Icon(Icons.arrow_back, size: 50, color: Colors.black), 
          ),// Adjusted size for visibility
          onPressed: () => Navigator.of(context).pop(),
        ),
      
         title: Transform.translate(
      offset: Offset(2, 5),
        child: Text(
          _currentDeviceName,
          style: GoogleFonts.jaldi(
            textStyle: TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          overflow: TextOverflow.ellipsis,
        ),
         ),
        actions: [
          _isRefreshing
              ? Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)),
                )
              : IconButton(
                     icon: Transform.translate(
                offset: Offset(-20, 5), 
                  child: Icon(Icons.refresh, color: Colors.black, size: 30,),
                     ),
                  onPressed: _handleRefresh,
                ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Removed manual back button and title as they are now in AppBar
                // SizedBox(height: 8),
                // Transform.translate(...)
                // SizedBox(height: 30), 
                // Device Status
                Container( // Removed Transform.translate
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration( //container
                      color: Colors.grey[350],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible( // Added Flexible to prevent overflow
                              child: Row(
                                children: [
                                  Icon(
                                    _getIconForDevice(_currentDeviceName), // icon status design
                                    size: 30,
                                    color: _isDeviceOn ? Colors.black : Colors.grey,
                                  ),
                                  SizedBox(width: 12),
                                  Flexible( // Added Flexible to prevent overflow
                                    child: Text(
                                      _currentDeviceName, // Use state variable
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis, // Handle text overflow
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isDeviceOn,
                              onChanged: (value) {
                                _toggleDeviceStatus(value);
                              },
                              activeColor: Colors.white,
                              activeTrackColor: Colors.black,
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: Colors.black,
                            ),
                          ],
                        ),
                        SizedBox(height: 20),
                        Text(
                          "Current Status",
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Colors.grey[700],
                          ),
                        ),
                        SizedBox(height: 8), // on off label
                        Text(
                          _isDeviceOn ? "ON" : "OFF",
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _isDeviceOn ? Colors.black : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Energy Usage
                Transform.translate(
                  offset: Offset(0, 5),
                  child: Row( // Use Row to place text and icon side-by-side
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Energy Usage",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row( // Replaced PopupMenuButton with Row
                        children: [
                          Text(_selectedPeriod), // Display selected period
                          IconButton(
                            icon: Icon(Icons.calendar_month),
                            onPressed: () => _showPeriodPicker(), // Call method to show period picker
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Energy Stats
                SizedBox(height: 20),
                Transform.translate(
                  offset: Offset(0, -15),
                  child: _isLoadingUsage
                      ? Center(child: CircularProgressIndicator()) // Show loading indicator
                      : Column( // Use a Column to display usage and cost vertically
                          children: [
                            _buildEnergyStatCard(
                              title: "Total Usage",
                              value: "${_totalUsageKwh.toStringAsFixed(2)} kWh", // Display total usage for selected period
                              period: _selectedPeriod,
                              icon: Icons.flash_on, // Use a relevant icon
                            ),
                            // Commented out Total Cost card as per user request
                            /*
                             _buildEnergyStatCard(
                              title: "Total Cost",
                              value: "₱${_totalElectricityCost.toStringAsFixed(2)}", // Display total cost for selected period
                              period: _selectedPeriod,
                              icon: Icons.attach_money,
                            ),
                            */
                          ],
                        ),
                ),
                 Transform.translate(
                  offset: Offset(0, -9),
                  child: _buildEnergyStatCard(
                    title: "Estimated Cost",
                    value: "₱${(_totalElectricityCost).toStringAsFixed(2)}", // Display fetched kwhrcost
                    period: _selectedPeriod, // Use the selected period for context
                    icon: Icons.attach_money,
                  ),
                ),
              
                // Removed the else block that displayed daily and total usage
                 
                Container( // Removed Transform.translate
                    margin: const EdgeInsets.only(bottom: 0, top: 0), // Added top margin
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    
                    child: Row(
                      children: [

                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.attach_money, color: Colors.blue),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "kWh Rate",
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 4),
                              TextField(
                                controller: _kWhRateController,
                                keyboardType: TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                  
                                  hintText: "Enter KWH rate",
                                  suffixText: "₱/kWh",
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: 24), // Add some spacing before the button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(0),
                      side: BorderSide(color: Colors.black, width: 1),
                    ),
                    minimumSize: Size(double.infinity, 50), // Make button full width
                  ),
                  onPressed: () {
                    // Navigate to the detailed usage screen
                    Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        // Handle the case where the user is not logged in,
        // though this is unlikely if they are on this screen.
        // You could return a placeholder widget or show an error.
        return Scaffold(
          appBar: AppBar(title: Text("Error")),
          body: Center(child: Text("User not logged in.")),
        );
      }
      return DeviceUsage(
        userId: userId,
        applianceId: widget.applianceId,
      );
    },
  ),
);
                  },
                  child: Text(
                    'View Detailed Usage',
                    style: GoogleFonts.judson(
                      fontSize: 20,
                      color: Colors.black,
                    ),
                  ),
                ),
                SizedBox(height: 24), 
                Text(
                  "Appliance Details",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                
                
                TextField(
                  controller: TextEditingController(text: _currentDeviceName),
                  enabled: false, 
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    labelText: 'Appliance Name',
                    labelStyle: GoogleFonts.jaldi(
                      color: Colors.black,
                      fontSize: 20,
                    ),
                    border: OutlineInputBorder(),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.black),
                    ),
                  ),
                  style: GoogleFonts.jaldi(
                    fontSize: 20,
                    color: Colors.black87,
                  ),
                ),

                SizedBox(height: 8),
                // Room Name Dropdown with Add Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          labelText: 'Room Name',
                          labelStyle: GoogleFonts.jaldi(
                            textStyle: TextStyle(fontSize: 20),
                          ),
                          border: OutlineInputBorder(),
                        ),
                        dropdownColor: Colors.grey[200],
                        style: GoogleFonts.jaldi(
                          textStyle: TextStyle(fontSize: 18, color: Colors.black87),
                        ),
                        value: _selectedRoom, // Use the new state variable
                        items: _roomNames.map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (mounted) {
                            setState(() {
                              _selectedRoom = newValue; // Update the new state variable
                              _roomController.text = newValue ?? ''; // Keep controller in sync
                            });
                          }
                        }
                      ),
                    ),
                    SizedBox(width: 8), // Add some spacing
                    IconButton(
                      icon: Icon(Icons.add, size: 30, color: Colors.black),
                      onPressed: _addRoom, // Call the _addRoom method
                    ),
                  ],
                ),
                SizedBox(height: 8),
                // Device Type Dropdown
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    labelText: 'Device Type',
                    labelStyle: GoogleFonts.jaldi(
                      textStyle: TextStyle(fontSize: 20),
                    ),
                    border: OutlineInputBorder(),
                  ),
                  dropdownColor: Colors.grey[200],
                  style: GoogleFonts.jaldi(
                    textStyle: TextStyle(fontSize: 18, color: Colors.black87),
                  ),
                  value: _deviceType,
                  items: ['Light', 'Socket'].map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (mounted) {
                      setState(() {
                        _deviceType = value!;
                        _typeController.text = value; // Keep the controller in sync
                      });
                    }
                  },
                ),
                SizedBox(height: 8),
                
                Transform.translate(
                    offset: Offset(-0, -0),
               child:  Row(
                  children: [
                    SizedBox(width: 16),
                    Icon(_selectedIcon),
                    TextButton(
                      
                      onPressed: _showIconPickerDialog, 
                      child: Text('Change Icon',
                      style: GoogleFonts.jaldi(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                      ),
                    ),
                    ),
                  ],
                ),
                ),
                SizedBox(height: 5),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(0),
      side: BorderSide(color: Colors.black, width: 1),
    )
                  ),
                  onPressed: _updateDeviceDetails,
                  child: Text('Save Changes',
                  style: GoogleFonts.judson(
                      fontSize: 20,
                      color: Colors.black,
                  ),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnergyStatCard({required String title, required String value, required String period, required IconData icon}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10), // Added margin for spacing
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.blue),
          ),
          SizedBox(width: 16),
          Expanded( // Added Expanded to prevent overflow if text is long
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  period,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get icon for usage period
  IconData _getIconForUsagePeriod(String period) {
    switch (period) {
      case 'daily':
        return Icons.query_stats;
      case 'weekly':
        return Icons.calendar_view_week;
      case 'monthly':
        return Icons.calendar_view_month;
      case 'yearly':
        return Icons.calendar_today;
      default:
        return Icons.query_stats;
    }
  }

  IconData _getIconForDevice(String deviceName) {
    // Normalize deviceName for robust matching
    final name = deviceName.toLowerCase();
    if (name.contains("light")) {
      return Icons.lightbulb_outline; // Using a more common light icon
    } else if (name.contains("socket") || name.contains("plug")) {
      return Icons.power_outlined;
    } else if (name.contains("ac") || name.contains("air conditioner") || name.contains("aircon")) {
      return Icons.ac_unit_outlined;
    } else if (name.contains("tv") || name.contains("television")) {
      return Icons.tv_outlined;
    } else if (name.contains("fan")) {
      return Icons.air_outlined;
    }
    return Icons.devices_other_outlined; // A generic fallback
  }

  // calendar picker function
  void _showPeriodPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Select Period',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              tileColor: Colors.white,
              title: Text('Daily'),
              onTap: () {
                if (mounted) {
                  setState(() {
                    _selectedPeriod = 'Daily';
                  });
                }
                _listenToPeriodicUsageData(); // Changed from _calculateTotalUsageForPeriod
                Navigator.pop(context);
              },
            ),
            ListTile(
              tileColor: Colors.white,
              title: Text('Weekly'),
              onTap: () {
                if (mounted) {
                  setState(() {
                    _selectedPeriod = 'Weekly';
                  });
                }
                _listenToPeriodicUsageData(); // Changed from _calculateTotalUsageForPeriod
                Navigator.pop(context);
              },
            ),
            ListTile(
              tileColor: Colors.white,
              title: Text('Monthly'),
              onTap: () {
                if (mounted) {
                  setState(() {
                    _selectedPeriod = 'Monthly';
                  });
                }
                _listenToPeriodicUsageData(); // Changed from _calculateTotalUsageForPeriod
                Navigator.pop(context);
              },
            ),
            ListTile(
              tileColor: Colors.white,
              title: Text('Yearly'),
              onTap: () {
                if (mounted) {
                  setState(() {
                    _selectedPeriod = 'Yearly';
                  });
                }
                _listenToPeriodicUsageData(); // Changed from _calculateTotalUsageForPeriod
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Function to calculate immediate cost
  /*
  double _calculateImmediateCost() {
    // Extract the numeric value from _currentDeviceUsage (e.g., "0.50 kWh" -> 0.50)
    final usageString = _currentDeviceUsage.replaceAll(' kWh', '');
    final usageKwh = double.tryParse(usageString) ?? 0.0;

    // Get the kWh rate from the controller
    final kWhRate = double.tryParse(_kWhRateController.text) ?? 0.0;

    return usageKwh * kWhRate;
  }
  */

  // Function to calculate average daily, weekly, monthly, and yearly usages
  Future<Map<String, double>> getAverageUsages() async {
    try {
      final now = DateTime.now();
      final userId = _auth.currentUser!.uid; // Assuming user is authenticated

      // Calculate date ranges for different periods
      final today = DateTime(now.year, now.month, now.day);
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(Duration(days: 6));
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);
      final startOfYear = DateTime(now.year, 1, 1);
      final endOfYear = DateTime(now.year, 12, 31);

      // Get average daily usage for each period
      final averageDaily = await _getAverageDailyUsageForPeriod(today, today);
      final averageWeekly = await _getAverageDailyUsageForPeriod(startOfWeek, endOfWeek);
      final averageMonthly = await _getAverageDailyUsageForPeriod(startOfMonth, endOfMonth);
      final averageYearly = await _getAverageDailyUsageForPeriod(startOfYear, endOfYear);

      return {
        'daily': averageDaily,
        'weekly': averageWeekly,
        'monthly': averageMonthly,
        'yearly': averageYearly,
      };
    } catch (e) {
      print('Error getting average usages: $e');
      if (mounted) {
        setState(() {
          _averageUsages = {
            'daily': 0.0,
            'weekly': 0.0,
            'monthly': 0.0,
            'yearly': 0.0,
          };
        });
      }
      return {
        'daily': 0.0,
        'weekly': 0.0,
        'monthly': 0.0,
        'yearly': 0.0,
      };
    }
  }

  // Function to get average daily usage (kWh) for a specific period
  Future<double> _getAverageDailyUsageForPeriod(DateTime startDate, DateTime endDate) async {
    try {
      double totalKwhr = 0.0;
      int numberOfDaysWithUsage = 0;
      final userId = _auth.currentUser!.uid; // Assuming user is authenticated
      final dayUsageCollectionRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .doc(widget.applianceId)
          .collection('yearly_usage');

      // Iterate through years within the date range
      for (int year = startDate.year; year <= endDate.year; year++) {
        final yearlyDocRef = dayUsageCollectionRef.doc(year.toString());
        final monthlySnapshots = await yearlyDocRef.collection('monthly_usage').get();

        for (final monthlyDoc in monthlySnapshots.docs) {
          final weekSnapshots = await monthlyDoc.reference.collection('week_usage').get();

          for (final weekDoc in weekSnapshots.docs) {
            final daySnapshots = await weekDoc.reference.collection('day_usage').get();

            for (final dayDoc in daySnapshots.docs) {
              final dateString = dayDoc.id; // e.g., '2023-10-27'
              try {
                final dateParts = dateString.split('-');
                final dayDate = DateTime(int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]));

                // Check if the day is within the specified date range
                if (dayDate.isAfter(startDate.subtract(Duration(days: 1))) && dayDate.isBefore(endDate.add(Duration(days: 1)))) {
                  final dayData = dayDoc.data();
                  final dailyKwhr = (dayData['kwh'] is num) ? (dayData['kwh'] as num).toDouble() : 0.0; // Use 'kwh' field
                  totalKwhr += dailyKwhr;
                  if (dailyKwhr > 0) {
                    numberOfDaysWithUsage++;
                  }
                }
              } catch (e) {
                print('Error parsing date from document ID $dateString: $e');
              }
            }
          }
        }
      }

      if (numberOfDaysWithUsage > 0) {
        return totalKwhr / numberOfDaysWithUsage;
      } else {
        return 0.0;
      }
    } catch (e) {
      print('Error getting average daily usage for period: $e');
      return 0.0;
    }
  }


  // Removed sumallkwh as its functionality is covered by UsageService

  Future<void> _handleRefresh() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) { // Check if widget is still in the tree
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User not authenticated. Cannot refresh.')),
        );
      }
      return;
    }
    if (_isRefreshing) return;

    if (mounted) {
      setState(() {
        _isRefreshing = true;
      });
    }

    try {
      print("DeviceInfoScreen: Manual refresh initiated for appliance ${widget.applianceId} by user ${user.uid}.");

      DocumentSnapshot applianceSnap = await FirebaseFirestore.instance
          .collection('users').doc(user.uid)
          .collection('appliances').doc(widget.applianceId)
          .get();
      
      double wattage = 0.0;
      if (applianceSnap.exists && applianceSnap.data() != null) {
        wattage = ((applianceSnap.data() as Map<String, dynamic>)['wattage'] as num?)?.toDouble() ?? 0.0;
      } else {
        print("DeviceInfoScreen: Could not fetch wattage for ${widget.applianceId} during refresh. Using 0.0.");
      }
      
      double kwhrRate = double.tryParse(_kWhRateController.text) ?? DEFAULT_KWHR_RATE;

      await _usageService.refreshApplianceUsage(
        userId: user.uid,
        applianceId: widget.applianceId,
        kwhrRate: kwhrRate, 
        wattage: wattage,
        referenceDate: DateTime.now(),
      );
      
      _listenToPeriodicUsageData();

      if (mounted) { // Check mounted before showing SnackBar
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('$_currentDeviceName usage data refreshed!')),
         );
      }
    } catch (e, s) {
      print("DeviceInfoScreen: Error during manual refresh: $e");
      print("DeviceInfoScreen: Stacktrace: $s");
      if (mounted) { // Check mounted before showing SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing data: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }
}

// Extension to capitalize the first letter of a string
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}

// Removed _fetchLatestDailyUsage, sumallkwh, and sumallkwhr methods as they used the old path structure
// and their functionality is either covered by _calculateTotalUsageForPeriod (for display)
// or handled by UsageService (for calculation and storage)
