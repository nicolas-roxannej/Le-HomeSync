import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/usage.dart'; // UsageService
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:homesync/databaseservice.dart'; 
import 'package:firebase_auth/firebase_auth.dart'; //FirebaseAuth
import 'package:intl/intl.dart'; // date formatting


class DeviceInfoScreen extends StatefulWidget {
  final String applianceId; 
  final String initialDeviceName;

  const DeviceInfoScreen({
    super.key,
    required this.applianceId,
    required this.initialDeviceName,
  });

  @override
  DeviceInfoScreenState createState() => DeviceInfoScreenState();
}

class DeviceInfoScreenState extends State<DeviceInfoScreen> {
  final DatabaseService _dbService = DatabaseService();
  StreamSubscription? _applianceSubscription;
  final FirebaseAuth _auth = FirebaseAuth.instance; 
  late UsageService _usageService; // Instance of UsageService

  // to hold data from Firestore and for editing
  bool _isDeviceOn = false;
  bool _isLoadingUsage = false; // immediate display
  String _currentDeviceName = "";
  String _currentDeviceUsage = "0 kWh"; 
  // State variable for latest daily usage
  final String _latestDailyUsage = "0 kWh";
  //  to toggle between latest daily usage and average usages
  final bool _showAverageUsages = false;
  // to hold average usages
  Map<String, double> _averageUsages = {};
  // to track the selected usage period
  final String _selectedUsagePeriod = 'daily'; // Default to daily
  bool _isRefreshing = false; // State for refresh indicator

 
  String _currentRoomName = "";
  String _currentDeviceType = "";
  IconData _currentIcon = Icons.devices;
  
  final TextEditingController _kWhRateController = TextEditingController(text: "0.0"); 

  // State variables for usage display
  String _selectedPeriod = 'Daily'; // State variable for selected period
  double _totalUsageKwh = 0.0; // State variable for total usage
  double _totalElectricityCost = 0.0; // State variable for total cost
  StreamSubscription? _periodicUsageSubscription;


  @override
  void initState() {
    super.initState();
    _usageService = UsageService(); // UsageService
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      _listenToPeriodicUsageData(); // Changed from _calculateTotalUsageForPeriod
    } else {
       // Handle case where user is not logged in, maybe navigate to login
       print("User not logged in in initState");
    }

    _listenToApplianceData();
  }

  @override
  void dispose() {
    _applianceSubscription?.cancel();
    _periodicUsageSubscription?.cancel(); // Cancel new subscription
    _kWhRateController.dispose(); // Dispose new controller
    super.dispose();
  }

  void _listenToApplianceData() {
    final userId = _auth.currentUser?.uid; // FirebaseAuth to get user ID
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
              _currentRoomName = data['roomName'] ?? "";
              _currentDeviceType = data['deviceType'] ?? "Light";
              _currentIcon = IconData(data['icon'] ?? Icons.devices.codePoint, fontFamily: 'MaterialIcons');

              // Use kwhr from user document
              _kWhRateController.text = userKwhrValue.toString();

              //usage display with accumulated kWh
              double accumulatedKwh = (data['kwh'] is num) ? (data['kwh'] as num).toDouble() : 0.0;
              _currentDeviceUsage = "${accumulatedKwh.toStringAsFixed(2)} kWh"; 
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _currentDeviceName = "Appliance not found";
            _isDeviceOn = false; 
            _isLoadingUsage = false; // appliance not found (stop)
          });
        }
        print("Appliance document ${widget.applianceId} does not exist.");
      }
    }, onError: (error) {
      print("Error listening to appliance ${widget.applianceId}: $error");
      if (mounted) {
        setState(() {
          _currentDeviceName = "Error loading data";
          _isLoadingUsage = false; //loading on error (stop)
        });
      }
    });
  }
  String _getMonthNameHelper(int month) { 
    const monthNames = [
      '', 'january', 'february', 'march', 'april', 'may', 'june',
      'july', 'august', 'september', 'october', 'november', 'december'
    ];
    return monthNames[month].toLowerCase();
  }
  int _getWeekOfMonthHelper(DateTime date) {
    if (date.day <= 7) return 1;
    if (date.day <= 14) return 2;
    if (date.day <= 21) return 3;
    if (date.day <= 28) return 4;
    return 5;
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
    final now = DateTime.now();
    
    switch (_selectedPeriod.toLowerCase()) {
      case 'daily':
        _calculateDailyUsage(userId, applianceId, now);
        break;
      case 'weekly':
        _calculateWeeklyUsage(userId, applianceId, now);
        break;
      case 'monthly':
        _calculateMonthlyUsage(userId, applianceId, now);
        break;
      case 'yearly':
        _calculateYearlyUsage(userId, applianceId, now);
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
    }
  }

  // Calculate accurate daily usage by aggregating all sessions for the day
  Future<void> _calculateDailyUsage(String userId, String applianceId, DateTime date) async {
    String yearStr = date.year.toString();
    String monthName = _getMonthNameHelper(date.month);
    int weekOfMonth = _getWeekOfMonthHelper(date);
    String dayStr = DateFormat('yyyy-MM-dd').format(date);

    String dayPath = 'users/$userId/appliances/$applianceId/yearly_usage/$yearStr/monthly_usage/${monthName}_usage/week_usage/week${weekOfMonth}_usage/day_usage/$dayStr';
    
    print("Calculating accurate daily usage from: $dayPath");

    try {
      
      DocumentSnapshot dayDoc = await FirebaseFirestore.instance.doc(dayPath).get();
      
      if (dayDoc.exists && dayDoc.data() != null) {
        Map<String, dynamic> dayData = dayDoc.data() as Map<String, dynamic>;
        
        // Get accumulated kWh and cost from the day document
        double totalKwh = (dayData['kwh'] as num?)?.toDouble() ?? 0.0;
        double totalCost = (dayData['kwhrcost'] as num?)?.toDouble() ?? 0.0;

        // check if device is currently ON and real-time accumulation
        DocumentSnapshot applianceDoc = await FirebaseFirestore.instance
            .collection('users').doc(userId)
            .collection('appliances').doc(applianceId)
            .get();
        
        if (applianceDoc.exists && applianceDoc.data() != null) {
          Map<String, dynamic> applianceData = applianceDoc.data() as Map<String, dynamic>;
          
          // If device is ON, calculate current session usage
          if (applianceData['applianceStatus'] == 'ON') {
            Timestamp? lastToggleTime = applianceData['lastToggleTime'] as Timestamp?;
            double wattage = (applianceData['wattage'] as num?)?.toDouble() ?? 0.0;
            
            if (lastToggleTime != null && wattage > 0) {
              DateTime toggleTime = lastToggleTime.toDate();
              
              // Only calculate if toggle was today
              if (DateFormat('yyyy-MM-dd').format(toggleTime) == dayStr) {
                Duration runningTime = DateTime.now().difference(toggleTime);
                double hoursRunning = runningTime.inSeconds / 3600.0;
                double currentSessionKwh = (wattage * hoursRunning) / 1000.0;
                
                DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
                double kwhrRate = DEFAULT_KWHR_RATE;
                if (userDoc.exists && userDoc.data() != null) {
                  kwhrRate = ((userDoc.data() as Map<String, dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
                }
                
                double currentSessionCost = currentSessionKwh * kwhrRate;
                
                print("Device is ON - Adding current session: ${currentSessionKwh.toStringAsFixed(4)} kWh, Cost: ₱${currentSessionCost.toStringAsFixed(2)}");
                
                totalKwh += currentSessionKwh;
                totalCost += currentSessionCost;
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _totalUsageKwh = totalKwh;
            _totalElectricityCost = totalCost;
            _isLoadingUsage = false;
          });
        }
        
        print("Daily usage calculated: ${totalKwh.toStringAsFixed(4)} kWh, Cost: ₱${totalCost.toStringAsFixed(2)}");
        
        // periodic recalculation every 10 seconds if device is ON
        _periodicUsageSubscription = Stream.periodic(Duration(seconds: 10)).listen((_) {
          _calculateDailyUsage(userId, applianceId, date);
        });
        
      } else {
        print("No daily usage data found at: $dayPath");
        if (mounted) {
          setState(() {
            _totalUsageKwh = 0.0;
            _totalElectricityCost = 0.0;
            _isLoadingUsage = false;
          });
        }
      }
    } catch (e) {
      print("Error calculating daily usage: $e");
      if (mounted) {
        setState(() {
          _totalUsageKwh = 0.0;
          _totalElectricityCost = 0.0;
          _isLoadingUsage = false;
        });
      }
    }
  }

  // Calculate weekly usage by summing all days in the week
  Future<void> _calculateWeeklyUsage(String userId, String applianceId, DateTime date) async {
    String yearStr = date.year.toString();
    String monthName = _getMonthNameHelper(date.month);
    int weekOfMonth = _getWeekOfMonthHelper(date);

    String weekPath = 'users/$userId/appliances/$applianceId/yearly_usage/$yearStr/monthly_usage/${monthName}_usage/week_usage/week${weekOfMonth}_usage';
    
    print("Calculating accurate weekly usage from: $weekPath");

    try {
      double totalKwh = 0.0;
      double totalCost = 0.0;

      // Get all day documents in this week
      QuerySnapshot daySnapshots = await FirebaseFirestore.instance
          .collection(weekPath + '/day_usage')
          .get();

      for (var dayDoc in daySnapshots.docs) {
        Map<String, dynamic> dayData = dayDoc.data() as Map<String, dynamic>;
        totalKwh += (dayData['kwh'] as num?)?.toDouble() ?? 0.0;
        totalCost += (dayData['kwhrcost'] as num?)?.toDouble() ?? 0.0;
      }

      // Add current session if device is ON and it's today
      String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      DocumentSnapshot applianceDoc = await FirebaseFirestore.instance
          .collection('users').doc(userId)
          .collection('appliances').doc(applianceId)
          .get();
      
      if (applianceDoc.exists && applianceDoc.data() != null) {
        Map<String, dynamic> applianceData = applianceDoc.data() as Map<String, dynamic>;
        
        if (applianceData['applianceStatus'] == 'ON') {
          Timestamp? lastToggleTime = applianceData['lastToggleTime'] as Timestamp?;
          double wattage = (applianceData['wattage'] as num?)?.toDouble() ?? 0.0;
          
          if (lastToggleTime != null && wattage > 0) {
            DateTime toggleTime = lastToggleTime.toDate();
            
            if (DateFormat('yyyy-MM-dd').format(toggleTime) == todayStr) {
              Duration runningTime = DateTime.now().difference(toggleTime);
              double hoursRunning = runningTime.inSeconds / 3600.0;
              double currentSessionKwh = (wattage * hoursRunning) / 1000.0;
              
              DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
              double kwhrRate = DEFAULT_KWHR_RATE;
              if (userDoc.exists && userDoc.data() != null) {
                kwhrRate = ((userDoc.data() as Map<String, dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
              }
              
              double currentSessionCost = currentSessionKwh * kwhrRate;
              totalKwh += currentSessionKwh;
              totalCost += currentSessionCost;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalUsageKwh = totalKwh;
          _totalElectricityCost = totalCost;
          _isLoadingUsage = false;
        });
      }
      
      print("Weekly usage calculated: ${totalKwh.toStringAsFixed(4)} kWh, Cost: ₱${totalCost.toStringAsFixed(2)}");
      
      _periodicUsageSubscription = Stream.periodic(Duration(seconds: 10)).listen((_) {
        _calculateWeeklyUsage(userId, applianceId, date);
      });
      
    } catch (e) {
      print("Error calculating weekly usage: $e");
      if (mounted) {
        setState(() {
          _totalUsageKwh = 0.0;
          _totalElectricityCost = 0.0;
          _isLoadingUsage = false;
        });
      }
    }
  }

  // Calculate accurate monthly usage by summing all weeks in the month
  Future<void> _calculateMonthlyUsage(String userId, String applianceId, DateTime date) async {
    String yearStr = date.year.toString();
    String monthName = _getMonthNameHelper(date.month);

    String monthPath = 'users/$userId/appliances/$applianceId/yearly_usage/$yearStr/monthly_usage/${monthName}_usage';
    
    print("Calculating accurate monthly usage from: $monthPath");

    try {
      double totalKwh = 0.0;
      double totalCost = 0.0;

      // Get all week documents in this month
      QuerySnapshot weekSnapshots = await FirebaseFirestore.instance
          .collection(monthPath + '/week_usage')
          .get();

      for (var weekDoc in weekSnapshots.docs) {
        // Get all days in each week
        QuerySnapshot daySnapshots = await weekDoc.reference
            .collection('day_usage')
            .get();
        
        for (var dayDoc in daySnapshots.docs) {
          Map<String, dynamic> dayData = dayDoc.data() as Map<String, dynamic>;
          totalKwh += (dayData['kwh'] as num?)?.toDouble() ?? 0.0;
          totalCost += (dayData['kwhrcost'] as num?)?.toDouble() ?? 0.0;
        }
      }

      // Add current session if device is ON and it's today
      String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      DocumentSnapshot applianceDoc = await FirebaseFirestore.instance
          .collection('users').doc(userId)
          .collection('appliances').doc(applianceId)
          .get();
      
      if (applianceDoc.exists && applianceDoc.data() != null) {
        Map<String, dynamic> applianceData = applianceDoc.data() as Map<String, dynamic>;
        
        if (applianceData['applianceStatus'] == 'ON') {
          Timestamp? lastToggleTime = applianceData['lastToggleTime'] as Timestamp?;
          double wattage = (applianceData['wattage'] as num?)?.toDouble() ?? 0.0;
          
          if (lastToggleTime != null && wattage > 0) {
            DateTime toggleTime = lastToggleTime.toDate();
            
            if (DateFormat('yyyy-MM-dd').format(toggleTime) == todayStr) {
              Duration runningTime = DateTime.now().difference(toggleTime);
              double hoursRunning = runningTime.inSeconds / 3600.0;
              double currentSessionKwh = (wattage * hoursRunning) / 1000.0;
              
              DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
              double kwhrRate = DEFAULT_KWHR_RATE;
              if (userDoc.exists && userDoc.data() != null) {
                kwhrRate = ((userDoc.data() as Map<String, dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
              }
              
              double currentSessionCost = currentSessionKwh * kwhrRate;
              totalKwh += currentSessionKwh;
              totalCost += currentSessionCost;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalUsageKwh = totalKwh;
          _totalElectricityCost = totalCost;
          _isLoadingUsage = false;
        });
      }
      
      print("Monthly usage calculated: ${totalKwh.toStringAsFixed(4)} kWh, Cost: ₱${totalCost.toStringAsFixed(2)}");
      
      _periodicUsageSubscription = Stream.periodic(Duration(seconds: 10)).listen((_) {
        _calculateMonthlyUsage(userId, applianceId, date);
      });
      
    } catch (e) {
      print("Error calculating monthly usage: $e");
      if (mounted) {
        setState(() {
          _totalUsageKwh = 0.0;
          _totalElectricityCost = 0.0;
          _isLoadingUsage = false;
        });
      }
    }
  }

  // Calculate accurate yearly usage by summing all months in the year
  Future<void> _calculateYearlyUsage(String userId, String applianceId, DateTime date) async {
    String yearStr = date.year.toString();

    String yearPath = 'users/$userId/appliances/$applianceId/yearly_usage/$yearStr';
    
    print("Calculating accurate yearly usage from: $yearPath");

    try {
      double totalKwh = 0.0;
      double totalCost = 0.0;

      // Get all month documents in this year
      QuerySnapshot monthSnapshots = await FirebaseFirestore.instance
          .collection(yearPath + '/monthly_usage')
          .get();

      for (var monthDoc in monthSnapshots.docs) {
        // Get all weeks in each month
        QuerySnapshot weekSnapshots = await monthDoc.reference
            .collection('week_usage')
            .get();
        
        for (var weekDoc in weekSnapshots.docs) {
          // Get all days in each week
          QuerySnapshot daySnapshots = await weekDoc.reference
              .collection('day_usage')
              .get();
          
          for (var dayDoc in daySnapshots.docs) {
            Map<String, dynamic> dayData = dayDoc.data() as Map<String, dynamic>;
            totalKwh += (dayData['kwh'] as num?)?.toDouble() ?? 0.0;
            totalCost += (dayData['kwhrcost'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }

      // Add current session if device is ON and it's today
      String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      DocumentSnapshot applianceDoc = await FirebaseFirestore.instance
          .collection('users').doc(userId)
          .collection('appliances').doc(applianceId)
          .get();
      
      if (applianceDoc.exists && applianceDoc.data() != null) {
        Map<String, dynamic> applianceData = applianceDoc.data() as Map<String, dynamic>;
        
        if (applianceData['applianceStatus'] == 'ON') {
          Timestamp? lastToggleTime = applianceData['lastToggleTime'] as Timestamp?;
          double wattage = (applianceData['wattage'] as num?)?.toDouble() ?? 0.0;
          
          if (lastToggleTime != null && wattage > 0) {
            DateTime toggleTime = lastToggleTime.toDate();
            
            if (DateFormat('yyyy-MM-dd').format(toggleTime) == todayStr) {
              Duration runningTime = DateTime.now().difference(toggleTime);
              double hoursRunning = runningTime.inSeconds / 3600.0;
              double currentSessionKwh = (wattage * hoursRunning) / 1000.0;
              
              DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
              double kwhrRate = DEFAULT_KWHR_RATE;
              if (userDoc.exists && userDoc.data() != null) {
                kwhrRate = ((userDoc.data() as Map<String, dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
              }
              
              double currentSessionCost = currentSessionKwh * kwhrRate;
              totalKwh += currentSessionKwh;
              totalCost += currentSessionCost;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalUsageKwh = totalKwh;
          _totalElectricityCost = totalCost;
          _isLoadingUsage = false;
        });
      }
      
      print("Yearly usage calculated: ${totalKwh.toStringAsFixed(4)} kWh, Cost: ₱${totalCost.toStringAsFixed(2)}");
      
      _periodicUsageSubscription = Stream.periodic(Duration(seconds: 10)).listen((_) {
        _calculateYearlyUsage(userId, applianceId, date);
      });
      
    } catch (e) {
      print("Error calculating yearly usage: $e");
      if (mounted) {
        setState(() {
          _totalUsageKwh = 0.0;
          _totalElectricityCost = 0.0;
          _isLoadingUsage = false;
        });
      }
    }
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

      await FirebaseFirestore.instance
          .collection('users').doc(userId)
          .collection('appliances').doc(widget.applianceId)
          .update({'applianceStatus': newStatusString});

      await _usageService.handleApplianceToggle(
        userId: userId,
        applianceId: widget.applianceId,
        isOn: newStatus,
        wattage: wattage,
        kwhrRate: kwhrRate,
      );

    } catch (e) {
      print("Error updating appliance status: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update status: ${e.toString()}")),
        );
      }
    }
  }

  Future<void> _updateDeviceDetails() async {
    final userId = _auth.currentUser?.uid; 
    if (userId == null) {
      print("User not logged in, cannot update kWh rate.");
      return;
    }

    double kWhRate = double.tryParse(_kWhRateController.text) ?? 0.0;
    final userUpdateData = {
      'kwhr': kWhRate,
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update(userUpdateData);

      print("User kWh rate updated successfully");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("kWh rate updated successfully!")),
        );
      }
    } catch (e) {
      print("Error updating user kWh rate: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update kWh rate: ${e.toString()}"))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E7E6),
        elevation: 0, 
        leading: IconButton(
          icon: Transform.translate(
        offset: Offset(5, 0),
          child: Icon(Icons.arrow_back, size: 50, color: Colors.black), 
          ),
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
                // Device Status
                Container( 
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[350],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible( 
                              child: Row(
                                children: [
                                  Icon(
                                    _getIconForDevice(_currentDeviceName), // icon status design
                                    size: 30,
                                    color: _isDeviceOn ? Colors.black : Colors.grey,
                                  ),
                                  SizedBox(width: 12),
                                  Flexible( 
                                    child: Text(
                                      _currentDeviceName, // Use state variable
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis, 
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
                  child: Row( 
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Energy Usage",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row( 
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
                      ? Center(child: CircularProgressIndicator()) 
                      : Column( 
                          children: [
                            _buildEnergyStatCard(
                              title: "Total Usage",
                              value: "${_totalUsageKwh.toStringAsFixed(2)} kWh", 
                              period: _selectedPeriod,
                              icon: Icons.flash_on,
                            ),
                          ],
                        ),
                ),
                 Transform.translate(
                  offset: Offset(0, -9),
                  child: _buildEnergyStatCard(
                    title: "Estimated Cost",
                    value: "₱${(_totalElectricityCost).toStringAsFixed(2)}", 
                    period: _selectedPeriod, 
                    icon: Icons.attach_money,
                  ),
                ),
              
                Container( 
                    margin: const EdgeInsets.only(bottom: 0, top: 0), 
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
                      color: Colors.grey,
                      fontSize: 20,
                    ),
                    border: OutlineInputBorder(),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                  ),
                  style: GoogleFonts.jaldi(
                    fontSize: 20,
                    color: Colors.black,
                  ),
                ),

                SizedBox(height: 8),

                TextField(
                  controller: TextEditingController(text: _currentRoomName),
                  enabled: false,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white, 
                    labelText: 'Room Name',
                    labelStyle: GoogleFonts.jaldi(
                      color: Colors.grey,
                      fontSize: 20,
                    ),
                    border: OutlineInputBorder(),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                  ),
                  style: GoogleFonts.jaldi(
                    fontSize: 20,
                    color: Colors.black,
                  ),
                ),
                
                SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: _currentDeviceType),
                  enabled: false,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white, 
                    labelText: 'Device Type',
                    labelStyle: GoogleFonts.jaldi(
                      color: Colors.grey,
                      fontSize: 20,
                    ),
                    border: OutlineInputBorder(),
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                  ),
                  style: GoogleFonts.jaldi(
                    fontSize: 20,
                    color: Colors.black,
                  ),
                ),
                
                SizedBox(height: 8),
                
                SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                     padding: EdgeInsets.symmetric(vertical: 13, horizontal: 105),
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
      margin: const EdgeInsets.only(bottom: 10), 
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
          Expanded( 
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

  IconData _getIconForDevice(String deviceName) {
    final name = deviceName.toLowerCase();
    if (name.contains("light")) {
      return Icons.lightbulb_outline; 
    } else if (name.contains("socket") || name.contains("plug")) {
      return Icons.power_outlined;
    } else if (name.contains("ac") || name.contains("air conditioner") || name.contains("aircon")) {
      return Icons.ac_unit_outlined;
    } else if (name.contains("tv") || name.contains("television")) {
      return Icons.tv_outlined;
    } else if (name.contains("fan")) {
      return Icons.air_outlined;
    }
    return Icons.devices_other_outlined; 
  }
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
                _listenToPeriodicUsageData();
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
                _listenToPeriodicUsageData();
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
                _listenToPeriodicUsageData();
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
                _listenToPeriodicUsageData();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRefresh() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) {
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

      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('$_currentDeviceName usage data refreshed!')),
         );
      }
    } catch (e, s) {
      print("DeviceInfoScreen: Error during manual refresh: $e");
      print("DeviceInfoScreen: Stacktrace: $s");
      if (mounted) {
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