import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class DeviceHistoryScreen extends StatefulWidget {
  @override
  _DeviceHistoryScreenState createState() => _DeviceHistoryScreenState();
}

class _DeviceHistoryScreenState extends State<DeviceHistoryScreen> {
  String _selectedDeviceFilter = 'All Devices';
  String _selectedDateFilter = 'Last 30 Days'; // Updated default
  TextEditingController _searchController = TextEditingController();
  TextEditingController _yearController = TextEditingController();
  bool _isSearching = false;
  
  // avoid repeated queries
  Map<String, Map<String, dynamic>> _applianceCache = {};

  final List<String> deviceFilters = [
    'All Devices',
    'Kitchen Devices',
    'Bedroom Devices', 
    'Living Room Devices',
    'Office Devices',
    'Garden Devices',
    'Bathroom Devices',
    'Laundry Devices'
  ];
  
  // date filters
  final List<String> dateFilters = [
    'Last 7 Days',
    'Last 30 Days',
    'Months',
    'All Time'
  ];

  // Months filter
  List<String> _selectedMonths = [];
  int _selectedYear = DateTime.now().year;
  final List<String> months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadApplianceCache();
  }

  // all user appliances collection 
  Future<void> _loadApplianceCache() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('appliances')
          .get();
      
      for (var doc in snapshot.docs) {
        _applianceCache[doc.id] = doc.data();
      }
      setState(() {});
    } catch (e) {
      print('Error loading appliance cache: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search devices...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey[400]),
              ),
              style: TextStyle(color: Colors.black),
              onChanged: (value) => setState(() {}),
            )
          : Text(
              'Device History',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isSearching) ...[
            IconButton(
              icon: Icon(Icons.clear),
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
            ),
            IconButton(
              icon: Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                });
              },
            ),
          ] else ...[
            IconButton(
              icon: Icon(Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: () {
                _loadApplianceCache();
                setState(() {});
                _showSuccessSnackbar('Data refreshed');
              },
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                // appliance details
                Row(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _getAppliancesStream(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return _buildStatCard('Active Devices', '...', Icons.timeline, Colors.blue);
                          }
                          final appliances = snapshot.data!.docs;
                          final filteredAppliances = _applyApplianceFilters(appliances);
                          
                          // active device count
                          int activeDevices = filteredAppliances.where((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final status = data['applianceStatus'] ?? 'OFF';
                            return status.toLowerCase() == 'on';
                          }).length;
                          return _buildStatCard(
                            'Active Devices',
                            activeDevices.toString(),
                            Icons.timeline,
                            Colors.blue,
                          );
                        },
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: FutureBuilder<double>(
                        future: _calculateTotalPowerFromHierarchy(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return _buildStatCard('Power Consumed', '...', Icons.bolt, Colors.orange);
                          }
                          final totalPower = snapshot.data ?? 0.0;
                          return _buildStatCard(
                            'Power Consumed',
                            '${totalPower.toStringAsFixed(1)} kWh',
                            Icons.bolt,
                            Colors.orange,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showDeviceFilterDialog(),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.filter_list, size: 16, color: Colors.grey[600]),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedDeviceFilter, 
                                  style: TextStyle(color: Colors.grey[600]),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey[600]),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showDateFilterDialog(),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedDateFilter, 
                                  style: TextStyle(color: Colors.grey[600]),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.grey[600]),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  flex: 3, 
                  child: Text(
                    'DEVICE NAME', 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[600]),
                    textAlign: TextAlign.left,
                  ),
                ),
                Expanded(
                  flex: 2, 
                  child: Text(
                    'STATUS', 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2, 
                  child: Text(
                    'USAGE', 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2, 
                  child: Text(
                    'LAST ACTIVITY', 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          
          // Device List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getAppliancesStream(), 
              builder: (context, applianceSnapshot) {
                if (applianceSnapshot.hasError) {
                  return _buildErrorState(applianceSnapshot.error.toString());
                }
                if (applianceSnapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingState();
                }
                if (!applianceSnapshot.hasData || applianceSnapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }
                final appliances = applianceSnapshot.data!.docs;
                final filteredAppliances = _applyApplianceFilters(appliances);
                if (filteredAppliances.isEmpty) {
                  return _buildNoResultsState();
                }
                return ListView.separated(
                  itemCount: filteredAppliances.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[200]),
                  itemBuilder: (context, index) => _buildDeviceRow(filteredAppliances[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  // get all appliance
  Stream<QuerySnapshot> _getAppliancesStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.empty();
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('appliances')
        .snapshots();
  }

// usage hierarchy 
  Stream<QuerySnapshot> _getUsageHistoryStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.empty();
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('appliances')
        .snapshots();
  }
  Future<Map<String, double>> _getApplianceUsageData(String userId, String applianceId) async {
    double totalKwh = 0.0;
    double totalCost = 0.0;
    DateTime? lastActivity;
    final now = DateTime.now();
    
    try {
      if (_selectedDateFilter == 'All Time') {
        // yearly 
        totalKwh = await _getAllTimeYearlyUsage(userId, applianceId);
      } else if (_selectedDateFilter == 'Months') {
        // monthly data for selected year 
        totalKwh = await _getSelectedYearMonthlyUsage(userId, applianceId);
      } else if (_selectedDateFilter == 'Last 30 Days') {
        // daily data for last 30 days
        totalKwh = await _getDailyUsageInRange(userId, applianceId, 30);
      } else if (_selectedDateFilter == 'Last 7 Days') {
        // daily data for last 7 days
        totalKwh = await _getDailyUsageInRange(userId, applianceId, 7);
      }
      // Get last activity
      lastActivity = await _getLastActivity(userId, applianceId);
    } catch (e) {
      print('Error fetching usage data for $applianceId: $e');
    }
    return {
      'kwh': totalKwh,
      'cost': totalCost,
      'lastActivity': lastActivity?.millisecondsSinceEpoch.toDouble() ?? 0.0,
    };
  }
  //all time usage data 
  Future<double> _getAllTimeYearlyUsage(String userId, String applianceId) async {
    double totalKwh = 0.0;
    final now = DateTime.now();
    //current year and previous years
    for (int year = 2020; year <= now.year; year++) {
      totalKwh += await _getYearUsage(userId, applianceId, year);
    }
    return totalKwh;
  }
  // selected year's monthly usage
  Future<double> _getSelectedYearMonthlyUsage(String userId, String applianceId) async {
    double totalKwh = 0.0;
    try {
      final yearPath = 'users/$userId/appliances/$applianceId/yearly_usage/$_selectedYear';
      // specific months or all, 
      List<int> monthsToCheck = [];
      if (_selectedMonths.isNotEmpty) {
        monthsToCheck = _selectedMonths.map((monthName) => months.indexOf(monthName) + 1).toList();
      } else {
        // all months for that year
        monthsToCheck = List.generate(12, (index) => index + 1);
      }
      for (int month in monthsToCheck) {
        String monthName = _getMonthName(month);
        String monthPath = '$yearPath/monthly_usage/${monthName}_usage';
        try {
          DocumentSnapshot monthDoc = await FirebaseFirestore.instance.doc(monthPath).get();
          if (monthDoc.exists && monthDoc.data() != null) {
            final monthData = monthDoc.data() as Map<String, dynamic>;
            totalKwh += (monthData['kwh'] as num?)?.toDouble() ?? 0.0;
          }
        } catch (e) {
        }
      }
    } catch (e) {
      print('Error fetching selected year monthly usage: $e');
    }
    return totalKwh;
  }
  // usage for a specific year
  Future<double> _getYearUsage(String userId, String applianceId, int year) async {
    double totalKwh = 0.0;
    try {
      final yearPath = 'users/$userId/appliances/$applianceId/yearly_usage/$year';
      // monthly data for the year
      for (int month = 1; month <= 12; month++) {
        String monthName = _getMonthName(month);
        String monthPath = '$yearPath/monthly_usage/${monthName}_usage';
        try {
          DocumentSnapshot monthDoc = await FirebaseFirestore.instance.doc(monthPath).get();
          if (monthDoc.exists && monthDoc.data() != null) {
            final monthData = monthDoc.data() as Map<String, dynamic>;
            totalKwh += (monthData['kwh'] as num?)?.toDouble() ?? 0.0;
          }
        } catch (e) {
        }
      }
    } catch (e) {
      print('Error fetching year usage for $year: $e');
    }
    return totalKwh;
  }
  // usage for range days
  Future<double> _getDailyUsageInRange(String userId, String applianceId, int days) async {
    double totalKwh = 0.0;
    final now = DateTime.now();
    for (int i = 0; i < days; i++) {
      final targetDate = now.subtract(Duration(days: i));
      totalKwh += await _getDayUsage(userId, applianceId, targetDate);
    }
    return totalKwh;
  }
  // usage specific day
  Future<double> _getDayUsage(String userId, String applianceId, DateTime date) async {
    double totalKwh = 0.0;
    
    try {
      String monthName = _getMonthName(date.month);
      int weekNumber = ((date.day - 1) ~/ 7) + 1; // week count
      String dayPath = 'users/$userId/appliances/$applianceId/yearly_usage/${date.year}/monthly_usage/${monthName}_usage/week_usage/week${weekNumber}_usage/day_usage/${DateFormat('yyyy-MM-dd').format(date)}';
      
      DocumentSnapshot dayDoc = await FirebaseFirestore.instance.doc(dayPath).get();
      if (dayDoc.exists && dayDoc.data() != null) {
        final dayData = dayDoc.data() as Map<String, dynamic>;
        totalKwh = (dayData['kwh'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (e) {
      // error day
    }
    return totalKwh;
  }
  // last activity time appliance
  Future<DateTime?> _getLastActivity(String userId, String applianceId) async {
    DateTime? lastActivity;
    final now = DateTime.now();
    try {
      // recent months activity
      for (int monthOffset = 0; monthOffset < 6; monthOffset++) {
        final checkDate = DateTime(now.year, now.month - monthOffset, 1);
        if (checkDate.year < 2020) break;
        
        String monthName = _getMonthName(checkDate.month);
        String monthPath = 'users/$userId/appliances/$applianceId/yearly_usage/${checkDate.year}/monthly_usage/${monthName}_usage';
        
        // weekly data
        for (int week = 1; week <= 5; week++) {
          String weekPath = '$monthPath/week_usage/week${week}_usage';
          
          try {
            // Check week document that exists
            DocumentSnapshot weekDoc = await FirebaseFirestore.instance.doc(weekPath).get();
            if (weekDoc.exists) {
              // Check daily data in todays week
              for (int day = 1; day <= 31; day++) {
                DateTime checkDayDate = DateTime(checkDate.year, checkDate.month, day);
                if (checkDayDate.month == checkDate.month) {
                  String dayPath = '$weekPath/day_usage/${DateFormat('yyyy-MM-dd').format(checkDayDate)}';
                  
                  try {
                    DocumentSnapshot dayDoc = await FirebaseFirestore.instance.doc(dayPath).get();
                    if (dayDoc.exists && dayDoc.data() != null) {
                      if (lastActivity == null || checkDayDate.isAfter(lastActivity)) {
                        lastActivity = checkDayDate;
                      }
                    }
                  } catch (e) {
                  }
                }
              }
            }
          } catch (e) {
          }
        }
      }
    } catch (e) {
      print('Error getting last activity for $applianceId: $e');
    }
    return lastActivity;
  }
  // get date range on filter
  DateTimeRange? _getDateRange() {
    DateTime now = DateTime.now();
    switch (_selectedDateFilter) {
      case 'Last 7 Days':
        return DateTimeRange(
          start: now.subtract(Duration(days: 7)),
          end: now,
        );
      case 'Last 30 Days':
        return DateTimeRange(
          start: now.subtract(Duration(days: 30)),
          end: now,
        );
      case 'Last 12 Months':
        return DateTimeRange(
          start: DateTime(now.year - 1, now.month, now.day),
          end: now,
        );
      case 'This Year':
        return DateTimeRange(
          start: DateTime(now.year, 1, 1),
          end: now,
        );
      default:
        return null;
    }
  }
  String _getMonthName(int month) {
    const monthNames = ['', 'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
    return monthNames[month].toLowerCase();
  }
  Widget _buildDeviceRow(QueryDocumentSnapshot applianceDoc) {
    final applianceData = applianceDoc.data() as Map<String, dynamic>;
    final deviceName = applianceData['applianceName'] ?? 'Unknown Device';
    final roomName = applianceData['roomName'] ?? 'Unknown Room';
    final applianceStatus = applianceData['applianceStatus'] ?? 'OFF';
    final applianceId = applianceDoc.id;

    return FutureBuilder<Map<String, double>>(
      future: _getApplianceUsageData(FirebaseAuth.instance.currentUser!.uid, applianceId),
      builder: (context, usageSnapshot) {
        double totalUsage = 0.0;
        String lastActivity = 'Never';
        
        if (usageSnapshot.hasData) {
          final usageData = usageSnapshot.data!;
          totalUsage = usageData['kwh'] ?? 0.0;
          
          double lastActivityTimestamp = usageData['lastActivity'] ?? 0.0;
          if (lastActivityTimestamp > 0) {
            DateTime lastActivityTime = DateTime.fromMillisecondsSinceEpoch(lastActivityTimestamp.toInt());
            lastActivity = _formatLastActivity(lastActivityTime);
          }
        }

        return GestureDetector(
          onTap: () => _showDeviceDetails(applianceId, applianceData),
          child: Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceName,
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        roomName,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: _buildActionStatusChip(applianceStatus),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${totalUsage.toStringAsFixed(1)} kWh',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[700]),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    lastActivity,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.trending_up, color: color, size: 16),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionStatusChip(String status) {
    Color color;
    String text;
    
    switch (status.toLowerCase()) {
      case 'on':
        color = Colors.green;
        text = 'ON';
        break;
      case 'off':
        color = Colors.red;
        text = 'OFF';
        break;
      default:
        color = Colors.grey;
        text = status;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error, size: 64, color: Colors.red[300]),
          SizedBox(height: 16),
          Text(
            'Error loading data',
            style: TextStyle(fontSize: 16, color: Colors.red[600]),
          ),
          SizedBox(height: 8),
          Text(
            'Please check your connection',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() {}),
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading device history...',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'No devices found',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Add devices to see them here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          SizedBox(height: 16),
          Text(
            'No results found',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
  List<QueryDocumentSnapshot> _applyApplianceFilters(List<QueryDocumentSnapshot> docs) {
    List<QueryDocumentSnapshot> filtered = docs;
    if (_selectedDeviceFilter != 'All Devices') {
      String targetRoom = _selectedDeviceFilter.replaceAll(' Devices', '');
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final roomName = data['roomName'] ?? '';
        return roomName.toLowerCase().contains(targetRoom.toLowerCase());
      }).toList();
    }
    if (_searchController.text.isNotEmpty) {
      String searchTerm = _searchController.text.toLowerCase();
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final deviceName = (data['applianceName'] ?? '').toString().toLowerCase();
        final roomName = (data['roomName'] ?? '').toString().toLowerCase();
        final deviceType = (data['deviceType'] ?? '').toString().toLowerCase();
        
        return deviceName.contains(searchTerm) || 
               roomName.contains(searchTerm) || 
               deviceType.contains(searchTerm);
      }).toList();
    }
    
    return filtered;
  }
  List<QueryDocumentSnapshot> _applyClientSideFilters(List<QueryDocumentSnapshot> docs) {
    List<QueryDocumentSnapshot> filtered = docs;
    if (_selectedDeviceFilter != 'All Devices') {
      String targetRoom = _selectedDeviceFilter.replaceAll(' Devices', '');
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final applianceId = data['applianceId'] as String?;
        final applianceData = _applianceCache[applianceId];
        final roomName = applianceData?['roomName'] ?? '';
        return roomName.toLowerCase().contains(targetRoom.toLowerCase());
      }).toList();
    }
    if (_searchController.text.isNotEmpty) {
      String searchTerm = _searchController.text.toLowerCase();
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final applianceId = data['applianceId'] as String?;
        final applianceData = _applianceCache[applianceId];
        final deviceName = (applianceData?['applianceName'] ?? '').toString().toLowerCase();
        final roomName = (applianceData?['roomName'] ?? '').toString().toLowerCase();
        return deviceName.contains(searchTerm) || roomName.contains(searchTerm);
      }).toList();
    }
    return filtered;
  }
  DateTime? _getFilterDate() {
    DateTime now = DateTime.now();
    switch (_selectedDateFilter) {
      case 'Last 7 Days':
        return now.subtract(Duration(days: 7));
      case 'Last 30 Days':
        return now.subtract(Duration(days: 30));
      case 'Months':
        return DateTime(_selectedYear, 1, 1);
      default:
        return null;
    }
  }
  double _calculateTotalPower(List<QueryDocumentSnapshot> docs) {
    return 0.0; 
  }
  //calculate total power from all appliances with date filtering
  Future<double> _calculateTotalPowerFromHierarchy() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0.0;
    double totalPower = 0.0;
    try {
      final appliancesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('appliances')
          .get();
      for (var applianceDoc in appliancesSnapshot.docs) {
        final usageData = await _getApplianceUsageData(user.uid, applianceDoc.id);
        totalPower += usageData['kwh'] ?? 0.0;
      }
    } catch (e) {
      print('Error calculating total power: $e');
    }
    return totalPower;
  }
  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    DateTime date = (timestamp as Timestamp).toDate();
    return '${date.day}/${date.month}/${date.year}';
  }
  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    DateTime date = (timestamp as Timestamp).toDate();
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  String _formatLastActivity(DateTime activityTime) {
    final now = DateTime.now();
    final difference = now.difference(activityTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '${months}mo ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '${years}y ago';
    }
  }

  void _showDeviceFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Filter by Device/Room'),
          content: Container(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: deviceFilters.map((filter) {
                return ListTile(
                  leading: Icon(
                    _selectedDeviceFilter == filter ? Icons.check_circle : Icons.circle_outlined,
                    color: _selectedDeviceFilter == filter ? Colors.blue : Colors.grey,
                  ),
                  title: Text(filter),
                  onTap: () {
                    setState(() {
                      _selectedDeviceFilter = filter;
                    });
                    Navigator.of(context).pop();
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showDateFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Filter by Date Range'),
          content: Container(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: dateFilters.map((filter) {
                return ListTile(
                  leading: Icon(
                    _selectedDateFilter == filter ? Icons.check_circle : Icons.circle_outlined,
                    color: _selectedDateFilter == filter ? Colors.blue : Colors.grey,
                  ),
                  title: Text(filter),
                  trailing: filter == 'Months' 
                    ? IconButton(
                        icon: Icon(Icons.settings, size: 20, color: Colors.blue),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showMonthYearSelectionDialog();
                        },
                      )
                    : null,
                  onTap: () {
                    setState(() {
                      _selectedDateFilter = filter;
                      if (filter != 'Months') {
                        _selectedMonths.clear(); // Clear month selection for other filters
                      }
                    });
                    Navigator.of(context).pop();
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
  void _showMonthYearSelectionDialog() {
    //current selected year
    _yearController.text = _selectedYear.toString();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.7,
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Select Year and Months',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 16),
                    // Year enter
                    TextField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Year',
                        hintText: 'Enter year (e.g., 2024)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (value) {
                        final year = int.tryParse(value);
                        if (year != null && year >= 2020 && year <= DateTime.now().year + 1) {
                          setDialogState(() {
                            _selectedYear = year;
                          });
                        }
                      },
                    ),
                    SizedBox(height: 16),
                    // Month selection 
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              setDialogState(() {
                                _selectedMonths.clear();
                              });
                            },
                            child: Text('Clear All', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              setDialogState(() {
                                _selectedMonths = List.from(months);
                              });
                            },
                            child: Text('Select All', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    Divider(),
                    // Month checkbox
                    Expanded(
                      child: ListView.builder(
                        itemCount: months.length,
                        itemBuilder: (context, index) {
                          final month = months[index];
                          final isSelected = _selectedMonths.contains(month);
                          return CheckboxListTile(
                            title: Text(month, style: TextStyle(fontSize: 14)),
                            value: isSelected,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (bool? value) {
                              setDialogState(() {
                                if (value == true) {
                                  _selectedMonths.add(month);
                                } else {
                                  _selectedMonths.remove(month);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('Cancel'),
                        ),
                        SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            final year = int.tryParse(_yearController.text);
                            if (year == null || year < 2020 || year > DateTime.now().year + 1) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Please enter a valid year (2020-${DateTime.now().year + 1})'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            setState(() {
                              _selectedDateFilter = 'Months';
                              _selectedYear = year;
                            });
                            Navigator.of(context).pop();
                          },
                          child: Text('Apply'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  // date range selected months and year
  String _getDateRangeDisplay() {
    if (_selectedDateFilter == 'Months') {
      String yearDisplay = '$_selectedYear';
      if (_selectedMonths.isNotEmpty) {
        if (_selectedMonths.length == 12) {
          return '$yearDisplay (All Months)';
        } else if (_selectedMonths.length <= 3) {
          return '$yearDisplay (${_selectedMonths.join(', ')})';
        } else {
          return '$yearDisplay (${_selectedMonths.length} months selected)';
        }
      } else {
        return '$yearDisplay (All Months)';
      }
    }
    return _selectedDateFilter;
  }

  void _showDeviceDetails(String applianceId, Map<String, dynamic> applianceData) {
    final deviceName = applianceData['applianceName'] ?? 'Unknown Device';
    final roomName = applianceData['roomName'] ?? 'Unknown Room';
    final deviceType = applianceData['deviceType'] ?? 'Unknown Type';
    final wattage = (applianceData['wattage'] as num?)?.toDouble() ?? 0.0;
    final status = applianceData['applianceStatus'] ?? 'OFF';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Device Details'),
          content: FutureBuilder<Map<String, double>>(
            future: _getApplianceUsageData(FirebaseAuth.instance.currentUser!.uid, applianceId),
            builder: (context, usageSnapshot) {
              double totalUsage = 0.0;
              double totalCost = 0.0;
              String lastActivity = 'Never';

              if (usageSnapshot.hasData) {
                final usageData = usageSnapshot.data!;
                totalUsage = usageData['kwh'] ?? 0.0;
                totalCost = usageData['cost'] ?? 0.0;
                
                double lastActivityTimestamp = usageData['lastActivity'] ?? 0.0;
                if (lastActivityTimestamp > 0) {
                  DateTime lastActivityTime = DateTime.fromMillisecondsSinceEpoch(lastActivityTimestamp.toInt());
                  lastActivity = _formatLastActivity(lastActivityTime);
                }
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Device Name:', deviceName),
                  _buildDetailRow('Room:', roomName),
                  _buildDetailRow('Device Type:', deviceType),
                  _buildDetailRow('Wattage:', '${wattage.toStringAsFixed(0)}W'),
                  _buildDetailRow('Current Status:', status),
                  SizedBox(height: 8),
                  _buildDetailRow('Date Range:', _getDateRangeDisplay()),
                  _buildDetailRow('Total Energy Used:', '${totalUsage.toStringAsFixed(3)} kWh'),
                  _buildDetailRow('Last Activity:', lastActivity),
                  if (totalCost > 0)
                    _buildDetailRow('Estimated Cost:', '₱${totalCost.toStringAsFixed(2)}'),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[600]),
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }
}