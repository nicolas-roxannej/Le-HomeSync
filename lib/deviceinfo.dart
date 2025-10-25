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

class DeviceInfoScreenState extends State<DeviceInfoScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _dbService = DatabaseService();
  StreamSubscription? _applianceSubscription;
  final FirebaseAuth _auth = FirebaseAuth.instance; 
  late UsageService _usageService; // Instance of UsageService
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

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
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
    
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
    _animationController.dispose();
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
          SnackBar(
            content: Text("Failed to update status: ${e.toString()}"),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
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
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text("kWh rate updated successfully!"),
              ],
            ),
            backgroundColor: Colors.green.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      print("Error updating user kWh rate: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update kWh rate: ${e.toString()}"),
            backgroundColor: Colors.red.shade400,
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
    backgroundColor: Color(0xFFE9E7E6),
    appBar: AppBar(
      backgroundColor: Color(0xFFE9E7E6),
      leading: Container(
        margin: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      title: Text(
        _currentDeviceName,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(
          textStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
  actions: [
          _isRefreshing
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black87),
                    ),
                  ),
                )
              : IconButton(
                  icon: Icon(Icons.refresh_rounded, color: Colors.black87, size: 26),
                  onPressed: _handleRefresh,
                ),
        ],
      ),
      
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _handleRefresh,
            color: Colors.black87,
            child: SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Modern Device Status Card
                  _buildDeviceStatusCard(),
                  
                  SizedBox(height: 24),
                  
                  // Energy Usage Section Header
                  _buildSectionHeader(),
                  
                  SizedBox(height: 16),
                  
                  // Energy Stats Cards
                  _isLoadingUsage
                      ? _buildLoadingCard()
                      : Column(
                          children: [
                            _buildModernEnergyCard(
                              title: "Total Usage",
                              value: "${_totalUsageKwh.toStringAsFixed(2)} kWh",
                              period: _selectedPeriod,
                              icon: Icons.bolt_rounded,
                             
                              gradient: LinearGradient(
                                colors: [ Color(0xFFFFB84D),  const Color.fromARGB(255, 255, 145, 1)],
                              ),
                            ),
                            SizedBox(height: 12),
                            _buildModernEnergyCard(
                              title: "Estimated Cost",
                              value: "${_totalElectricityCost.toStringAsFixed(2)}",
                              period: _selectedPeriod,
                              icon: Icons.payments_rounded,
                              gradient: LinearGradient(
                                colors: [Color(0xFF4CAF50),Colors.lightGreen],
                              ),
                            ),
                          ],
                        ),
                  
                  SizedBox(height: 24),
                  
                  // kWh Rate Card
                  _buildKwhRateCard(),
                  
                  SizedBox(height: 24),
                  
                  // Appliance Details Section
                  Text(
                    "Appliance Details",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Details Fields
                  _buildDetailField(
                    label: 'Appliance Name',
                    value: _currentDeviceName,
                    icon: Icons.label_outline_rounded,
                  ),
                  
                  SizedBox(height: 12),
                  
                  _buildDetailField(
                    label: 'Room Name',
                    value: _currentRoomName,
                    icon: Icons.house,
                  ),
                  
                  SizedBox(height: 12),
                  
                  _buildDetailField(
                    label: 'Device Type',
                    value: _currentDeviceType,
                    icon: Icons.devices_other_rounded,
                  ),
                  
                  SizedBox(height: 24),
                  
                  // Save Button
                  _buildSaveButton(),
                  
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceStatusCard() {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isDeviceOn 
            ? [Color(0xFF2C3E50), Color(0xFF3498DB)]
            : [Color(0xFF95a5a6), Color(0xFF7f8c8d)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _isDeviceOn 
              ? Color(0xFF3498DB).withOpacity(0.3)
              : Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getIconForDevice(_currentDeviceName),
                        size: 32,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _currentDeviceName,
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4),
                          Text(
                            _currentRoomName.isNotEmpty ? _currentRoomName : 'No Room',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: _isDeviceOn,
                  onChanged: (value) {
                    _toggleDeviceStatus(value);
                  },
                  activeColor: Color(0xFF2ECC71),
                  activeTrackColor: Color(0xFF2ECC71).withOpacity(0.5),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.white.withOpacity(0.3),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Container(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Current Status",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isDeviceOn ? Color(0xFF2ECC71) : Colors.white54,
                        shape: BoxShape.circle,
                        boxShadow: _isDeviceOn
                            ? [
                                BoxShadow(
                                  color: Color(0xFF2ECC71),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : [],
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      _isDeviceOn ? "ON" : "OFF",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Energy Usage",
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        InkWell(
          onTap: () => _showPeriodPicker(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedPeriod,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.calendar_today_rounded, size: 16, color: Colors.black54),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
              strokeWidth: 3,
            ),
            SizedBox(height: 16),
            Text(
              'Loading usage data...',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernEnergyCard({
    required String title,
    required String value,
    required String period,
    required IconData icon,
    required Gradient gradient,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: gradient.colors.first.withOpacity(0.3),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  period,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKwhRateCard() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.lightBlueAccent, Colors.blue],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.monetization_on_rounded, color: Colors.white, size: 28),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "kWh Rate",
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: _kWhRateController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    hintText: "Enter rate",
                    hintStyle: GoogleFonts.poppins(color: Colors.black38),
                    suffixText: '₱/kWh',
                    suffixStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                    filled: true,
                    fillColor: Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.black, width: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: Colors.black54),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.black45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value.isNotEmpty ? value : 'Not set',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return InkWell(
      onTap: _updateDeviceDetails,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black, Colors.black],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.save_rounded, color: Colors.white, size: 22),
            SizedBox(width: 12),
            Text(
              'Save Changes',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForDevice(String deviceName) {
  // Use the actual icon from Firebase if available
  if (_currentIcon.codePoint != Icons.devices.codePoint) {
    return _currentIcon;
  }
  
  // Fallback to name-based detection if icon not set
  final name = deviceName.toLowerCase();
  if (name.contains("light")) {
    return Icons.lightbulb_rounded;
  } else if (name.contains("socket") || name.contains("plug")) {
    return Icons.power_rounded;
  } else if (name.contains("ac") || name.contains("air conditioner") || name.contains("aircon")) {
    return Icons.ac_unit_rounded;
  } else if (name.contains("tv") || name.contains("television")) {
    return Icons.tv_rounded;
  } else if (name.contains("fan")) {
    return Icons.air_rounded;
  }
  return Icons.devices_other_rounded;
}

   void _showPeriodPicker() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Period',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              SizedBox(height: 20),
              _buildPeriodOption('Daily', Icons.today_rounded),
              _buildPeriodOption('Weekly', Icons.view_week_rounded),
              _buildPeriodOption('Monthly', Icons.calendar_month_rounded),
              _buildPeriodOption('Yearly', Icons.calendar_today_rounded),
            ],
          ),
        ),
      ),
    );
  }

 Widget _buildPeriodOption(String period, IconData icon) {
    bool isSelected = _selectedPeriod == period;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPeriod = period;
        });
        _listenToPeriodicUsageData();
        Navigator.pop(context);
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.withOpacity(0.5) : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.black : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.black : Colors.black,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white,
                size: 20,
              ),
            ),
            SizedBox(width: 16),
            Text(
              period,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Color(0xFF1A1A1A) : Color(0xFF1A1A1A),
              ),
            ),
           Spacer(),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: Colors.black, size: 24),
              
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
          SnackBar(
            content: Text('User not authenticated. Cannot refresh.'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
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
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('$_currentDeviceName usage data refreshed!'),
              ],
            ),
            backgroundColor: Colors.green.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e, s) {
      print("DeviceInfoScreen: Error during manual refresh: $e");
      print("DeviceInfoScreen: Stacktrace: $s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing data: $e'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
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