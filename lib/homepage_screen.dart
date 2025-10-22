import 'package:flutter/material.dart';
import 'package:homesync/deviceinfo.dart';
import 'package:homesync/usage.dart';
import 'package:homesync/welcome_screen.dart';
import 'package:weather/weather.dart';
import 'package:homesync/electricity_usage_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/notification_screen.dart';
import 'package:homesync/profile_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:intl/intl.dart';

const String _apiKey = 'd542f2e03ea5728e77e367f19c0fb675';
const String _cityName = 'Manila';
const double DEFAULT_KWHR_RATE = 0.15;

class HomepageScreen extends StatefulWidget {
  const HomepageScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomepageScreen> {
  String _selectedPeriod = 'Daily';
  Weather? _currentWeather;
  int _selectedIndex = 0;
  bool _isRefreshing = false;
  bool _isLoadingUsage = true;

  double _totalUsageKwh = 0.0;
  double _totalCost = 0.0;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _appliancesSubscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _appliances = [];
  final UsageService _usageService = UsageService();
  
  Timer? _refreshTimer;

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

  @override
  void initState() {
    super.initState();
    _fetchWeather();
    _listenToAppliances();
    _fetchAccurateTotalUsage();
    
    // Set up periodic refresh every 5 MINUTES (300 seconds)
    _refreshTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      if (mounted) {
        _fetchAccurateTotalUsage();
      }
    });
  }

  @override
  void dispose() {
    _appliancesSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchWeather() async {
    if (_apiKey == 'YOUR_API_KEY') {
      print("Weather API key is a placeholder. Please replace it.");
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
    }
  }

  void _listenToAppliances() {
    _appliancesSubscription?.cancel();

    final user = _auth.currentUser;
    if (user == null) {
      print("User not authenticated. Cannot fetch appliances.");
      if (mounted) {
        setState(() {
          _appliances = [];
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
          _appliances = snapshot.docs;
        });
      }
    }, onError: (error) {
      print("Error listening to appliances: $error");
      if (mounted) {
        setState(() {
          _appliances = [];
        });
      }
    });
  }

  String _getMonthName(int month) {
    const monthNames = ['', 'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
    return monthNames[month].toLowerCase();
  }

  int _getWeekOfMonth(DateTime date) {
    if (date.day <= 7) return 1;
    if (date.day <= 14) return 2;
    if (date.day <= 21) return 3;
    if (date.day <= 28) return 4;
    return 5;
  }

  Future<void> _fetchAccurateTotalUsage() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingUsage = true;
    });

    final User? user = _auth.currentUser;
    if (user == null) {
      setState(() => _isLoadingUsage = false);
      return;
    }

    final userId = user.uid;
    final now = DateTime.now();
    double totalKwh = 0.0;

    try {
      QuerySnapshot appliancesSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .get();
      
      List<String> applianceIds = appliancesSnapshot.docs.map((doc) => doc.id).toList();
      switch (_selectedPeriod) {
        case 'Daily':
          totalKwh = await _calculateDailyTotalUsageParallel(userId, applianceIds, now);
          break;
        case 'Weekly':
          totalKwh = await _calculateWeeklyTotalUsageParallel(userId, applianceIds, now);
          break;
        case 'Monthly':
          totalKwh = await _calculateMonthlyTotalUsageParallel(userId, applianceIds, now);
          break;
        case 'Yearly':
          totalKwh = await _calculateYearlyTotalUsageParallel(userId, applianceIds, now);
          break;
      }

      //current session usage for devices that are ON
      Map<String, double> currentSessionData = await _calculateCurrentSessionUsage(userId, applianceIds, now);
      totalKwh += currentSessionData['kwh'] ?? 0.0;
      double sessionCost = currentSessionData['cost'] ?? 0.0;
      // user's kWh rate
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      double kwhrRate = DEFAULT_KWHR_RATE;
      if (userDoc.exists && userDoc.data() != null) {
        kwhrRate = ((userDoc.data() as Map<String, dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
      }
      // Calculate total cost (stored kWh * rate + current session cost)
      double storedCost = (totalKwh - (currentSessionData['kwh'] ?? 0.0)) * kwhrRate;
      double totalCost = storedCost + sessionCost;

      if (mounted) {
        setState(() {
          _totalUsageKwh = totalKwh;
          _totalCost = totalCost;
          _isLoadingUsage = false;
        });
      }
    } catch (e) {
      print('Error fetching accurate total usage: $e');
      if (mounted) {
        setState(() {
          _isLoadingUsage = false;
        });
      }
    }
  }

  Future<double> _calculateDailyTotalUsageParallel(String userId, List<String> applianceIds, DateTime date) async {
    String dayStr = DateFormat('yyyy-MM-dd').format(date);
    
    final results = await Future.wait(
      applianceIds.map((applianceId) async {
        String path = 'users/$userId/appliances/$applianceId/yearly_usage/${date.year}/monthly_usage/${_getMonthName(date.month)}_usage/week_usage/week${_getWeekOfMonth(date)}_usage/day_usage/$dayStr';
        DocumentSnapshot doc = await _firestore.doc(path).get();
        
        if (doc.exists && doc.data() != null) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['kwh'] as num?)?.toDouble() ?? 0.0;
        }
        return 0.0;
      })
    );
    
    return results.fold<double>(0.0, (sum, value) => sum + value);
  }

  Future<double> _calculateWeeklyTotalUsageParallel(String userId, List<String> applianceIds, DateTime date) async {
    final results = await Future.wait(
      applianceIds.map((applianceId) => _getWeeklyUsageForAppliance(userId, applianceId, date))
    );
    return results.fold<double>(0.0, (sum, value) => sum + value);
  }

  Future<double> _getWeeklyUsageForAppliance(String userId, String applianceId, DateTime date) async {
    String weekPath = 'users/$userId/appliances/$applianceId/yearly_usage/${date.year}/monthly_usage/${_getMonthName(date.month)}_usage/week_usage/week${_getWeekOfMonth(date)}_usage';
    
    QuerySnapshot dayDocs = await _firestore.collection('$weekPath/day_usage').get();
    
    return dayDocs.docs.fold<double>(0.0, (sum, dayDoc) {
      if (dayDoc.exists && dayDoc.data() != null) {
        final data = dayDoc.data() as Map<String, dynamic>;
        return sum + ((data['kwh'] as num?)?.toDouble() ?? 0.0);
      }
      return sum;
    });
  }

  Future<double> _calculateMonthlyTotalUsageParallel(String userId, List<String> applianceIds, DateTime date) async {
    final results = await Future.wait(
      applianceIds.map((applianceId) => _getMonthlyUsageForAppliance(userId, applianceId, date))
    );
    return results.fold<double>(0.0, (sum, value) => sum + value);
  }

  Future<double> _getMonthlyUsageForAppliance(String userId, String applianceId, DateTime date) async {
    String monthPath = 'users/$userId/appliances/$applianceId/yearly_usage/${date.year}/monthly_usage/${_getMonthName(date.month)}_usage';
    
    QuerySnapshot weekDocs = await _firestore.collection('$monthPath/week_usage').get();

    final weekResults = await Future.wait(
      weekDocs.docs.map((weekDoc) async {
        QuerySnapshot dayDocs = await weekDoc.reference.collection('day_usage').get();
        
        return dayDocs.docs.fold<double>(0.0, (sum, dayDoc) {
          if (dayDoc.exists && dayDoc.data() != null) {
            final data = dayDoc.data() as Map<String, dynamic>;
            return sum + ((data['kwh'] as num?)?.toDouble() ?? 0.0);
          }
          return sum;
        });
      })
    );
    
    return weekResults.fold<double>(0.0, (a, b) => a + b);
  }

  Future<double> _calculateYearlyTotalUsageParallel(String userId, List<String> applianceIds, DateTime date) async {
    final results = await Future.wait(
      applianceIds.map((applianceId) => _getYearlyUsageForAppliance(userId, applianceId, date))
    );
    return results.fold<double>(0.0, (sum, value) => sum + value);
  }

  Future<double> _getYearlyUsageForAppliance(String userId, String applianceId, DateTime date) async {
    String yearPath = 'users/$userId/appliances/$applianceId/yearly_usage/${date.year}';
    
    QuerySnapshot monthDocs = await _firestore.collection('$yearPath/monthly_usage').get();
    
    final monthResults = await Future.wait(
      monthDocs.docs.map((monthDoc) async {
        QuerySnapshot weekDocs = await monthDoc.reference.collection('week_usage').get();
        
        final weekResults = await Future.wait(
          weekDocs.docs.map((weekDoc) async {
            QuerySnapshot dayDocs = await weekDoc.reference.collection('day_usage').get();
            
            return dayDocs.docs.fold<double>(0.0, (sum, dayDoc) {
              if (dayDoc.exists && dayDoc.data() != null) {
                final data = dayDoc.data() as Map<String, dynamic>;
                return sum + ((data['kwh'] as num?)?.toDouble() ?? 0.0);
              }
              return sum;
            });
          })
        );
        
        return weekResults.fold<double>(0.0, (a, b) => a + b);
      })
    );
    
    return monthResults.fold<double>(0.0, (a, b) => a + b);
  }

  Future<Map<String, double>> _calculateCurrentSessionUsage(String userId, List<String> applianceIds, DateTime referenceDate) async {
    Map<String, double> result = {'kwh': 0.0, 'cost': 0.0};
    DateTime now = DateTime.now();
    
    // Get user's kWh rate
    DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
    double kwhrRate = DEFAULT_KWHR_RATE;
    if (userDoc.exists && userDoc.data() != null) {
      kwhrRate = ((userDoc.data() as Map<String, dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
    }
    
    for (String applianceId in applianceIds) {
      try {
        DocumentSnapshot applianceDoc = await _firestore
            .collection('users').doc(userId)
            .collection('appliances').doc(applianceId)
            .get();
        
        if (!applianceDoc.exists) continue;
        
        Map<String, dynamic> applianceData = applianceDoc.data() as Map<String, dynamic>;
        String status = applianceData['applianceStatus'] ?? 'OFF';
        
        if (status.toLowerCase() != 'on') continue;
        
        Timestamp? lastToggleTime = applianceData['lastToggleTime'] as Timestamp?;
        double wattage = (applianceData['wattage'] as num?)?.toDouble() ?? 0.0;
        
        if (lastToggleTime == null || wattage <= 0) continue;
        
        DateTime toggleTime = lastToggleTime.toDate();
        
        bool includeSession = false;
        
        switch (_selectedPeriod) {
          case 'Daily':
            String toggleDay = DateFormat('yyyy-MM-dd').format(toggleTime);
            String today = DateFormat('yyyy-MM-dd').format(now);
            includeSession = (toggleDay == today);
            break;
          case 'Weekly':
            int toggleWeek = _getWeekOfMonth(toggleTime);
            int currentWeek = _getWeekOfMonth(now);
            includeSession = (toggleTime.month == now.month && 
                             toggleTime.year == now.year && 
                             toggleWeek == currentWeek);
            break;
          case 'Monthly':
            includeSession = (toggleTime.month == now.month && toggleTime.year == now.year);
            break;
          case 'Yearly':
            includeSession = (toggleTime.year == now.year);
            break;
        }
        
        if (includeSession) {
          Duration runningTime = now.difference(toggleTime);
          double hoursRunning = runningTime.inSeconds / 3600.0;
          double sessionKwh = (wattage * hoursRunning) / 1000.0;
          double sessionCost = sessionKwh * kwhrRate;
          
          result['kwh'] = (result['kwh'] ?? 0.0) + sessionKwh;
          result['cost'] = (result['cost'] ?? 0.0) + sessionCost;
        }
      } catch (e) {
        print('Error calculating current session for $applianceId: $e');
      }
    }
    
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16.0),
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
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 6),
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
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.only(top: 10, bottom: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text('Usage',
                                    style: TextStyle(
                                        fontSize: 20, fontWeight: FontWeight.bold)),
                                SizedBox(width: 8),
                                _isRefreshing
                                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : GestureDetector(
                                        onTap: _handleRefresh,
                                        child: Icon(Icons.refresh, color: Colors.black, size: 20),
                                      ),
                              ],
                            ),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _showPeriodPicker(),
                                  child: Container(
                                    padding: EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      Icons.calendar_month,
                                      size: 20,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.pushNamed(context, '/history');
                                  },
                                  child: Container(
                                    padding: EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Icon(
                                      Icons.history,
                                      size: 20,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, -10),
                        child: Container(
                          height: 300,
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(118, 255, 255, 255),
                            borderRadius: BorderRadius.all(Radius.circular(8.0)),
                          ),
                          child: ElectricityUsageChart(selectedPeriod: _selectedPeriod),
                        ),
                      ),
                      _buildUsageStat(
                        'Total Electricity Usage',
                        _isLoadingUsage ? 'Calculating...' : '${_totalUsageKwh.toStringAsFixed(2)} kWh',
                        Icons.electric_bolt,
                      ),
                      _buildUsageStat(
                        'Total Estimated Cost',
                        _isLoadingUsage ? 'Calculating...' : '₱${_totalCost.toStringAsFixed(2)}',
                        Icons.attach_money,
                      ),

                      _buildDevicesList(),
                    ],
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
                    height: screenSize.height - 0,
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
                          leading: Icon(Icons.person, color: Colors.white, size: 35),
                          title: Text('Profile', style: GoogleFonts.inter(color: Colors.white)),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ProfileScreen()),
                            );
                          },
                        ),
                        SizedBox(height: 15),
                        ListTile(
                          leading: Icon(Icons.notifications, color: Colors.white, size: 35),
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
                          leading: Padding(
                            padding: EdgeInsets.only(left: 5),
                            child: Icon(Icons.logout, color: Colors.white, size: 35),
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
      children: [
        TextButton(
          onPressed: () {
            setState(() {
              _selectedIndex = index;
            });

            switch (index) {
              case 0:
                break;
              case 1:
                Navigator.pushNamed(context, '/devices');
                break;
              case 2:
                Navigator.pushNamed(context, '/rooms');
                break;
            }
          },
          child: Text(
            title,
            style: GoogleFonts.inter(
              color: isSelected ? Colors.black : Colors.grey[400],
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              fontSize: 17,
            ),
          ),
        ),
        if (isSelected)
          Transform.translate(
            offset: Offset(-0, -10),
            child: Container(
              height: 2,
              width: 70,
              color: Colors.brown,
              margin: EdgeInsets.only(top: 1),
            ),
          ),
      ],
    );
  }

  Widget _buildUsageStat(String title, String value, IconData icon) {
    return Transform.translate(
      offset: Offset(-0, 10),
      child: Row(
        children: [
          Icon(icon),
          SizedBox(width: 5, height: 40),
          Text(title, style: GoogleFonts.judson(color: Colors.black, fontSize: 16)),
          Spacer(),
          Text(value, style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 17)),
        ],
      ),
    );
  }

  Widget _buildDevicesList() {
    return Transform.translate(
      offset: Offset(-0, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Appliance',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          _appliances.isEmpty
              ? Center(child: Text("No appliances found."))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: _appliances.length,
                  itemBuilder: (context, index) {
                    final applianceDoc = _appliances[index];
                    final applianceData = applianceDoc.data();
                    final String applianceId = applianceDoc.id;
                    final String applianceName = applianceData['applianceName'] as String? ?? 'Unknown Device';
                    final int iconCodePoint = (applianceData['icon'] is int) ? (applianceData['icon'] as int) : Icons.devices.codePoint;
                    final IconData icon = _getIconFromCodePoint(iconCodePoint);

                    return Column(
                      children: [
                        _buildDeviceItem(applianceId, applianceName, '', icon),
                        if (index < _appliances.length - 1)
                          Divider(
                            color: Colors.grey[400],
                            thickness: 0.5,
                            indent: 50,
                            endIndent: 16,
                          ),
                      ],
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(String id, String name, String usage, IconData icon) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (context) => DeviceInfoScreen(
                    applianceId: id,
                    initialDeviceName: name,
                  )),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Row(
          children: [
            Icon(icon, size: 35),
            SizedBox(width: 12),
            Text(name, style: GoogleFonts.judson(color: Colors.black, fontSize: 18)),
            Spacer(),
            Text(usage, style: GoogleFonts.jaldi(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
            SizedBox(width: 8),
          ],
        ),
      ),
    );
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
            )),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              tileColor: Colors.white,
              title: Text('Daily'),
              onTap: () {
                setState(() {
                  _selectedPeriod = 'Daily';
                });
                _fetchAccurateTotalUsage();
                Navigator.pop(context);
              },
            ),
            ListTile(
              tileColor: Colors.white,
              title: Text('Weekly'),
              onTap: () {
                setState(() {
                  _selectedPeriod = 'Weekly';
                });
                _fetchAccurateTotalUsage();
                Navigator.pop(context);
              },
            ),
            ListTile(
              tileColor: Colors.white,
              title: Text('Monthly'),
              onTap: () {
                setState(() {
                  _selectedPeriod = 'Monthly';
                });
                _fetchAccurateTotalUsage();
                Navigator.pop(context);
              },
            ),
            ListTile(
              tileColor: Colors.white,
              title: Text('Yearly'),
              onTap: () {
                setState(() {
                  _selectedPeriod = 'Yearly';
                });
                _fetchAccurateTotalUsage();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User not authenticated. Cannot refresh.')),
      );
      return;
    }
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      print("Homepage: Fast refresh initiated by user ${user.uid}.");

      await _fetchAccurateTotalUsage();

      _fetchWeather();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Usage data refreshed!'), duration: Duration(seconds: 1)),
      );
    } catch (e, s) {
      print("Homepage: Error during fast refresh: $e");
      print("Homepage: Stacktrace: $s");
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