import 'package:flutter/material.dart';
import 'package:homesync/about.dart';
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

class _HomeScreenState extends State<HomepageScreen> with SingleTickerProviderStateMixin {
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
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

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
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
    
    _fetchWeather();
    _listenToAppliances();
    _fetchAccurateTotalUsage();
    
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
    _fadeController.dispose();
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

      Map<String, double> currentSessionData = await _calculateCurrentSessionUsage(userId, applianceIds, now);
      totalKwh += currentSessionData['kwh'] ?? 0.0;
      double sessionCost = currentSessionData['cost'] ?? 0.0;
      
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      double kwhrRate = DEFAULT_KWHR_RATE;
      if (userDoc.exists && userDoc.data() != null) {
        kwhrRate = ((userDoc.data() as Map<String, dynamic>)['kwhr'] as num?)?.toDouble() ?? DEFAULT_KWHR_RATE;
      }
      
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
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
                    BoxShadow( // header gradient
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
                        // Usage Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Usage Overview',
                                  style: GoogleFonts.inter(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                ),
                                SizedBox(width: 10),
                                _isRefreshing
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                        ),
                                      )
                                    : GestureDetector(
                                        onTap: _handleRefresh,
                                        child: Container(
                                          padding: EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.refresh_rounded,
                                            color:Colors.black,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                            Row(
                              children: [
                                _buildIconButton(
                                  Icons.calendar_today_rounded,
                                  () => _showPeriodPicker(),
                                ),
                                SizedBox(width: 8),
                                _buildIconButton(
                                  Icons.history_rounded,
                                  () => Navigator.pushNamed(context, '/history'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 20),

                        // Chart Container
                        Container(
                          height: 280,
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
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: ElectricityUsageChart(selectedPeriod: _selectedPeriod),
                            ),
                          ),
                        ),
                        SizedBox(height: 20),

                        // Stats Cards
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'Total Usage',
                                _isLoadingUsage ? '...' : '${_totalUsageKwh.toStringAsFixed(2)}',
                                'kWh',
                                Icons.bolt_rounded,
                                Color(0xFFFFB84D),
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                'Estimated Cost',
                                _isLoadingUsage ? '...' : '${_totalCost.toStringAsFixed(2)}',
                                '₱',
                                Icons.payments_rounded,
                                Color(0xFF4CAF50),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 24),

                        // Appliances Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Your Appliances',
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            Text(
                              '${_appliances.length} devices',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),

                        // Appliances List
                        _appliances.isEmpty
                            ? Container(
                                padding: EdgeInsets.all(40),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.devices_other_rounded, size: 48, color: Colors.grey[400]),
                                      SizedBox(height: 12),
                                      Text(
                                        'No appliances found',
                                        style: GoogleFonts.inter(
                                          color: Colors.grey[600],
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.09),
                                      blurRadius: 16,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListView.separated(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemCount: _appliances.length,
                                  separatorBuilder: (context, index) => Divider(
                                    height: 1,
                                    indent: 70,
                                    endIndent: 20,
                                    color: Colors.grey[200],
                                  ),
                                  itemBuilder: (context, index) {
                                    final applianceDoc = _appliances[index];
                                    final applianceData = applianceDoc.data();
                                    final String applianceId = applianceDoc.id;
                                    final String applianceName = applianceData['applianceName'] as String? ?? 'Unknown Device';
                                    final int iconCodePoint = (applianceData['icon'] is int) ? (applianceData['icon'] as int) : Icons.devices.codePoint;
                                    final IconData icon = _getIconFromCodePoint(iconCodePoint);

                                    return _buildModernDeviceItem(applianceId, applianceName, icon);
                                  },
                                ),
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
              break;
            case 1:
              Navigator.pushNamed(context, '/devices');
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
                : null,
          ),
          child: Center(
            child: Text(
              title,
              style: GoogleFonts.inter(
                color: isSelected ? Colors.black : Colors.grey[600],
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 20,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String unit, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.1),
            color.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (unit == '₱')
                Text(
                  unit,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit != '₱')
                Text(
                  ' $unit',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernDeviceItem(String id, String name, IconData icon) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DeviceInfoScreen(
              applianceId: id,
              initialDeviceName: name,
            ),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.grey.withOpacity(0.4), Colors.grey.withOpacity(0.4)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 28, color: Colors.black),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey[400],
              size: 24,
            ),
          ],
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
                              Navigator.pushNamed(context, '/notification');
                            },
                          ),
                          _buildMenuTile(
                            Icons.info_rounded,
                            "About",
                            () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/about');
                            },
                          ),
                          _buildMenuTile(
                            Icons.help_rounded,
                            "Help",
                            () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/help');
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

  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
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
        _fetchAccurateTotalUsage();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User not authenticated. Cannot refresh.'),
          backgroundColor: Colors.red[400],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
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
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text('Usage data refreshed!'),
            ],
          ),
          backgroundColor: Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e, s) {
      print("Homepage: Error during fast refresh: $e");
      print("Homepage: Stacktrace: $s");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing data: $e'),
            backgroundColor: Colors.red[400],
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