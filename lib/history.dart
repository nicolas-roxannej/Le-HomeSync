import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

class DeviceHistoryScreen extends StatefulWidget {
  @override
  _DeviceHistoryScreenState createState() => _DeviceHistoryScreenState();
}
class _DeviceHistoryScreenState extends State<DeviceHistoryScreen> {
  String _selectedDeviceFilter = 'All Devices';
  String _selectedDateFilter = 'Today';
  TextEditingController _searchController = TextEditingController();
  TextEditingController _yearController = TextEditingController();
  bool _isSearching = false;
  
  Map<String, Map<String, dynamic>> _applianceCache = {};
  List<String> _userRooms = []; // registered rooms
  List<String> deviceFilters = [
    'All Devices',
  ]; 
  // date filters
  final List<String> dateFilters = [
    'Today',
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
    _loadUserRooms(); 
  }
  // user room in Firestore
  Future<void> _loadUserRooms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('Rooms')
          .get();
      
      List<String> rooms = ['All Devices']; 
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final roomName = data['roomName'] as String?;
        if (roomName != null && roomName.isNotEmpty) {
          rooms.add('$roomName Devices');
        }
      }
      
      setState(() {
        _userRooms = snapshot.docs.map((doc) {
          final data = doc.data();
          return data['roomName'] as String? ?? '';
        }).where((name) => name.isNotEmpty).toList();
        deviceFilters = rooms;
      });
    } catch (e) {
      print('Error loading user rooms: $e');
    }
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
              style: GoogleFonts.jaldi(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          iconSize: 45,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isSearching) ...[
            IconButton(
              icon: Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                });
              },
            ),
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: () {
                _loadApplianceCache();
                _loadUserRooms();
                setState(() {});
                _showSuccessSnackbar('Data refreshed');
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
                _loadUserRooms(); 
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
                          return FutureBuilder<List<QueryDocumentSnapshot>>(
                            future: _applyApplianceFiltersAsync(appliances),
                            builder: (context, filteredSnapshot) {
                              if (!filteredSnapshot.hasData) {
                                return _buildStatCard('Active Devices', '...', Icons.timeline, Colors.blue);
                              }
                              final filteredAppliances = filteredSnapshot.data!;
                              
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
                              Icon(Icons.calendar_month, size: 16, color: Colors.grey[600]),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _getDateRangeDisplay(), 
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
                
                return FutureBuilder<List<QueryDocumentSnapshot>>(
                  future: _applyApplianceFiltersAsync(appliances),
                  builder: (context, filteredSnapshot) {
                    if (filteredSnapshot.connectionState == ConnectionState.waiting) {
                      return _buildLoadingState();
                    }
                    if (filteredSnapshot.hasError) {
                      return _buildErrorState(filteredSnapshot.error.toString());
                    }
                    if (!filteredSnapshot.hasData || filteredSnapshot.data!.isEmpty) {
                      return _buildNoResultsState();
                    }
                    
                    final filteredAppliances = filteredSnapshot.data!;
                    return ListView.separated(
                      itemCount: filteredAppliances.length,
                      separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[200]),
                      itemBuilder: (context, index) => _buildDeviceRow(filteredAppliances[index]),
                    );
                  },
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
  Future<List<QueryDocumentSnapshot>> _applyApplianceFiltersAsync(List<QueryDocumentSnapshot> docs) async {
    List<QueryDocumentSnapshot> filtered = docs;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    // user's registered rooms filter
    if (_selectedDeviceFilter != 'All Devices') {
      String targetRoom = _selectedDeviceFilter.replaceAll(' Devices', '');
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final roomName = data['roomName'] ?? '';
        return roomName.toLowerCase() == targetRoom.toLowerCase();
      }).toList();
    }
    // Apply search filter
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
    
    // show actual usage data for selected period of appliance
    if (_selectedDateFilter == 'Months' && (_selectedMonths.isNotEmpty || _selectedYear != DateTime.now().year)) {
      List<QueryDocumentSnapshot> devicesWithData = [];
      for (var doc in filtered) {
        bool hasData = await _hasUsageDataForSelectedPeriod(user.uid, doc.id);
        if (hasData) {
          devicesWithData.add(doc);
        }
      }
      filtered = devicesWithData;
    } else if (_selectedDateFilter != 'All Time' && _selectedDateFilter != 'Months') {
      List<QueryDocumentSnapshot> devicesWithData = [];
      for (var doc in filtered) {
        final usageData = await _getApplianceUsageData(user.uid, doc.id);
        final totalUsage = usageData['kwh'] ?? 0.0;
        if (totalUsage > 0 || usageData['lastActivity'] != null && usageData['lastActivity']! > 0) {
          devicesWithData.add(doc);
        }
      }
      filtered = devicesWithData;
    }
    return filtered;
  }
  Future<bool> _hasUsageDataForSelectedPeriod(String userId, String applianceId) async {
    try {
      List<int> monthsToCheck = [];
      if (_selectedMonths.isNotEmpty) {
        monthsToCheck = _selectedMonths.map((monthName) => months.indexOf(monthName) + 1).toList();
      } else {
        monthsToCheck = List.generate(12, (index) => index + 1);
      }
      for (int month in monthsToCheck) {
        String monthName = _getMonthName(month);
        String monthPath = 'users/$userId/appliances/$applianceId/yearly_usage/$_selectedYear/monthly_usage/${monthName}_usage';
        try {
          DocumentSnapshot monthDoc = await FirebaseFirestore.instance.doc(monthPath).get();
          if (monthDoc.exists && monthDoc.data() != null) {
            final monthData = monthDoc.data() as Map<String, dynamic>;
            final monthKwh = (monthData['kwh'] as num?)?.toDouble() ?? 0.0;
            if (monthKwh > 0) {
              return true; 
            }
          }
        } catch (e) {   
        }
      } 
      return false; 
    } catch (e) {
      print('Error checking usage data for selected period: $e');
      return false;
    }
  }
  Future<Map<String, double>> _getApplianceUsageData(String userId, String applianceId) async {
    double totalKwh = 0.0;
    double totalCost = 0.0;
    DateTime? lastActivity;
    final now = DateTime.now();
    try {
      if (_selectedDateFilter == 'Today') {
        // tiday data
        totalKwh = await _getTodayUsage(userId, applianceId);
      } else if (_selectedDateFilter == 'All Time') {
        // yearly data
        totalKwh = await _getAllTimeYearlyUsage(userId, applianceId);
      } else if (_selectedDateFilter == 'Months') {
        // monthly data - only selected data
        totalKwh = await _getSelectedYearMonthlyUsage(userId, applianceId);
      } else if (_selectedDateFilter == 'Last 30 Days') {
        //  data for last 30 days
        totalKwh = await _getDailyUsageInRange(userId, applianceId, 30);
      } else if (_selectedDateFilter == 'Last 7 Days') {
        // data for last 7 days
        totalKwh = await _getDailyUsageInRange(userId, applianceId, 7);
      }
      // last activity
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
  // Get today's usage data
  Future<double> _getTodayUsage(String userId, String applianceId) async {
    final today = DateTime.now();
    return await _getDayUsage(userId, applianceId, today);
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
  Future<double> _getSelectedYearMonthlyUsage(String userId, String applianceId) async {
    double totalKwh = 0.0;
    try {
      // the only validated year here is 2020 - to more years
      if (_selectedYear < 2020 || _selectedYear > DateTime.now().year + 1) {
        print('Invalid year selected: $_selectedYear');
        return 0.0;
      }
      List<int> monthsToCheck = [];
      if (_selectedMonths.isNotEmpty) {
        monthsToCheck = _selectedMonths.map((monthName) => months.indexOf(monthName) + 1).toList();
      } else {
        monthsToCheck = List.generate(12, (index) => index + 1);
      }
      print('Checking months: $monthsToCheck for year: $_selectedYear');
      bool foundAnyData = false;
      for (int month in monthsToCheck) {
        String monthName = _getMonthName(month);
        String monthPath = 'users/$userId/appliances/$applianceId/yearly_usage/$_selectedYear/monthly_usage/${monthName}_usage';
        try {
          DocumentSnapshot monthDoc = await FirebaseFirestore.instance.doc(monthPath).get();
          if (monthDoc.exists && monthDoc.data() != null) {
            final monthData = monthDoc.data() as Map<String, dynamic>;
            final monthKwh = (monthData['kwh'] as num?)?.toDouble() ?? 0.0;
            if (monthKwh > 0) {
              totalKwh += monthKwh;
              foundAnyData = true;
              print('Month $monthName: ${monthKwh} kWh');
            }
          } else {
            print('No data found for month: $monthName');
          }
        } catch (e) {
          print('Error fetching month $monthName: $e');
        }
      }
      if (!foundAnyData) {
        print('No usage data found for selected year/months');
      }
      print('Total kWh for selected year/months: $totalKwh');
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
      int weekNumber = ((date.day - 1) ~/ 7) + 1; 
      String dayPath = 'users/$userId/appliances/$applianceId/yearly_usage/${date.year}/monthly_usage/${monthName}_usage/week_usage/week${weekNumber}_usage/day_usage/${DateFormat('yyyy-MM-dd').format(date)}';
      
      DocumentSnapshot dayDoc = await FirebaseFirestore.instance.doc(dayPath).get();
      if (dayDoc.exists && dayDoc.data() != null) {
        final dayData = dayDoc.data() as Map<String, dynamic>;
        totalKwh = (dayData['kwh'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (e) {
    }
    return totalKwh;
  }
// real time last act
  Future<DateTime?> _getLastActivity(String userId, String applianceId) async {
    DateTime? lastActivity;
    try {
      DocumentSnapshot applianceDoc = await FirebaseFirestore.instance
          .doc('users/$userId/appliances/$applianceId')
          .get();
      if (applianceDoc.exists) {
        final data = applianceDoc.data() as Map<String, dynamic>;
        final lastStatusChange = data['lastStatusChange'] as Timestamp?;
        final lastUpdated = data['lastUpdated'] as Timestamp?;
        final updatedAt = data['updatedAt'] as Timestamp?;
        final createdAt = data['createdAt'] as Timestamp?; 
        final currentStatus = data['applianceStatus'] ?? 'OFF';
        List<DateTime?> timestamps = [
          lastStatusChange?.toDate(),
          lastUpdated?.toDate(),
          updatedAt?.toDate(),
          createdAt?.toDate(), 
        ];
        for (DateTime? timestamp in timestamps) {
          if (timestamp != null) {
            if (lastActivity == null || timestamp.isAfter(lastActivity)) {
              lastActivity = timestamp;
            }
          }
        }
        if (lastActivity == null && createdAt != null) {
          lastActivity = createdAt.toDate();
        }
        // recent activity na pag guma na yung device
        if (currentStatus.toLowerCase() == 'on' && lastActivity != null) {
          final now = DateTime.now();
          final timeDiff = now.difference(lastActivity).inMinutes;
          if (timeDiff <= 5) {
            lastActivity = now;
          }
        }
        if (createdAt != null) {
          final now = DateTime.now();
          final timeSinceCreation = now.difference(createdAt.toDate()).inHours;
          if (timeSinceCreation <= 1 && lastActivity == null) {
            lastActivity = createdAt.toDate();
          }
        }
      }
      if (lastActivity == null) {
        final now = DateTime.now();
        for (int dayOffset = 0; dayOffset < 7; dayOffset++) {
          final checkDate = now.subtract(Duration(days: dayOffset));
          String monthName = _getMonthName(checkDate.month);
          int weekNumber = ((checkDate.day - 1) ~/ 7) + 1;
          String dayPath = 'users/$userId/appliances/$applianceId/yearly_usage/${checkDate.year}/monthly_usage/${monthName}_usage/week_usage/week${weekNumber}_usage/day_usage/${DateFormat('yyyy-MM-dd').format(checkDate)}';
          try {
            DocumentSnapshot dayDoc = await FirebaseFirestore.instance.doc(dayPath).get();
            if (dayDoc.exists && dayDoc.data() != null) {
              final dayData = dayDoc.data() as Map<String, dynamic>;
              final kwh = (dayData['kwh'] as num?)?.toDouble() ?? 0.0;
              
              if (kwh > 0) {
                lastActivity = checkDate;
                break;
              }
            }
          } catch (e) {
          }
        }
      }
    } catch (e) {
      print('Error getting real-time last activity for $applianceId: $e');
    }
    return lastActivity;
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
  //calculate the total power from all appliances with date filtering
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
      List<QueryDocumentSnapshot> filteredAppliances = await _applyApplianceFiltersAsync(appliancesSnapshot.docs);
      
      for (var applianceDoc in filteredAppliances) {
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
  String _formatLastActivity(DateTime? activityTime) {
    if (activityTime == null) return 'Never';
    
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
          backgroundColor: const Color(0xFFE9E7E6),
          title: Text('Filter by Room'),
          titleTextStyle: GoogleFonts.jaldi(
          fontSize: 23, 
          fontWeight: FontWeight.bold,
          color: Colors.black,
),            
          content: Container(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: deviceFilters.map((filter) {
                return ListTile(
                  leading: Icon(
                    _selectedDeviceFilter == filter ? Icons.check_circle : Icons.circle_outlined,
                    color: _selectedDeviceFilter == filter ? Colors.black : Colors.grey,
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
              child: Text('Cancel',
              style:GoogleFonts.inter(
              color: Colors.black,
              fontSize: 15,
              ),
            ),
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
          backgroundColor: const Color(0xFFE9E7E6),
          title: Text('Date Filter'),
          titleTextStyle: GoogleFonts.jaldi(
          fontSize: 23, 
          fontWeight: FontWeight.bold,
          color: Colors.black,
),            
          content: Container(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: dateFilters.map((filter) {
                return ListTile(
                  leading: Icon(
                    _selectedDateFilter == filter ? Icons.check_circle : Icons.circle_outlined,
                    color: _selectedDateFilter == filter ? Colors.black : Colors.grey,
                  ),
                  title: Text(filter),
                  trailing: filter == 'Months' 
                    ? IconButton(
                        icon: Icon(Icons.settings, size: 20, color: Colors.black),
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
                        _selectedMonths.clear(); 
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
              child: Text('Cancel',
              style:GoogleFonts.inter(
              color: Colors.black,
              fontSize: 15,
              ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showMonthYearSelectionDialog() {
    _yearController.text = _selectedYear.toString();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFFE9E7E6),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.7,
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Select Year and Months',
                      style: GoogleFonts.jaldi(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: 16),
                    // Year input
                    TextField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.inter(fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Year',
                        labelStyle: GoogleFonts.inter(),
                        hintText: 'Enter year (e.g., 2024)',
                        hintStyle: GoogleFonts.inter(color: Colors.grey),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        prefixIcon: Icon(Icons.calendar_month),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: Colors.white,
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
                    Container(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () {
                                setDialogState(() {
                                  _selectedMonths.clear();
                                });
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.grey[200],
                                foregroundColor: Colors.black,
                              ),
                              child: Text('Clear All', 
                                style: GoogleFonts.inter(fontSize: 12)),
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
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                              ),
                              child: Text('Select All', 
                                style: GoogleFonts.inter(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    Divider(color: Colors.grey),
                    
                    // Month checkbox
                    Expanded(
                      child: ListView.builder(
                        itemCount: months.length,
                        itemBuilder: (context, index) {
                          final month = months[index];
                          final isSelected = _selectedMonths.contains(month);
                          return Container(
                            margin: EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.black.withOpacity(0.1) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: CheckboxListTile(
                              title: Text(
                                month, 
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                              value: isSelected,
                              dense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8),
                              activeColor: Colors.black,
                              checkColor: Colors.white,
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  if (value == true) {
                                    if (!_selectedMonths.contains(month)) {
                                      _selectedMonths.add(month);
                                    }
                                  } else {
                                    _selectedMonths.remove(month);
                                  }
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey[600],
                          ),
                          child: Text('Cancel', style: GoogleFonts.inter()),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                          child: Text('Apply', style: GoogleFonts.inter()),
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
  String _getDateRangeDisplay() {
    if (_selectedDateFilter == 'Months') {
      String yearDisplay = '$_selectedYear';
      if (_selectedMonths.isNotEmpty) {
        if (_selectedMonths.length == 12) {
          return '$yearDisplay (All Months)';
        } else if (_selectedMonths.length <= 3) {
          String monthsDisplay = _selectedMonths.map((month) => month.substring(0, 3)).join(', ');
          return '$yearDisplay ($monthsDisplay)';
        } else {
          return '$yearDisplay (${_selectedMonths.length} months)';
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
          backgroundColor: const Color(0xFFE9E7E6),
          title: Text('Device Details'),
          titleTextStyle: GoogleFonts.jaldi(
          fontSize: 23, 
          fontWeight: FontWeight.bold,
          color: Colors.black,
),   

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
              child: Text('Close',
              style:GoogleFonts.inter(
              color: Colors.black,
              fontSize: 15,
              ), 
              ),
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