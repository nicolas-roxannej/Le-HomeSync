import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';

class OptimizedDeviceHistoryScreen extends StatefulWidget {
  @override
  _OptimizedDeviceHistoryScreenState createState() => _OptimizedDeviceHistoryScreenState();
}

class _OptimizedDeviceHistoryScreenState extends State<OptimizedDeviceHistoryScreen> {
  String _selectedDeviceFilter = 'All Devices';
  String _selectedDateFilter = 'Today';
  TextEditingController _searchController = TextEditingController();
  TextEditingController _yearController = TextEditingController();
  bool _isSearching = false;
  
  Map<String, CachedUsageData> _usageCache = {};
  List<String> _userRooms = [];
  List<String> deviceFilters = ['All Devices'];
  Timer? _cacheRefreshTimer;
  Timer? _activityUpdateTimer;
  
  final List<String> dateFilters = [
    'Today',
    'Last 7 Days',
    'Last 30 Days',
    'Months',
    'All Time'
  ];
  
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
    _cacheRefreshTimer?.cancel();
    _activityUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadUserRooms();
    _cacheRefreshTimer = Timer.periodic(Duration(minutes: 2), (_) {
      if (mounted) {
        setState(() {
          _usageCache.clear();
        });
      }
    });
    _activityUpdateTimer = Timer.periodic(Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

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
      
      if (mounted) {
        setState(() {
          _userRooms = snapshot.docs.map((doc) {
            final data = doc.data();
            return data['roomName'] as String? ?? '';
          }).where((name) => name.isNotEmpty).toList();
          deviceFilters = rooms;
        });
      }
    } catch (e) {
      print('Error loading user rooms: $e');
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
                _loadUserRooms();
                setState(() {
                  _usageCache.clear();
                });
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
                _loadUserRooms();
                setState(() {
                  _usageCache.clear();
                });
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
                          return FutureBuilder<List<DeviceWithUsage>>(
                            future: _loadDevicesWithUsage(appliances),
                            builder: (context, filteredSnapshot) {
                              if (!filteredSnapshot.hasData) {
                                return _buildStatCard('Active Devices', '...', Icons.timeline, Colors.blue);
                              }
                              final filteredDevices = filteredSnapshot.data!;
                              
                              int activeDevices = filteredDevices.where((device) {
                                final data = device.doc.data() as Map<String, dynamic>;
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
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _getAppliancesStream(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return _buildStatCard('Power Consumed', '...', Icons.bolt, Colors.orange);
                          }
                          return FutureBuilder<double>(
                            future: _calculateTotalPowerOptimized(snapshot.data!.docs),
                            builder: (context, powerSnapshot) {
                              if (!powerSnapshot.hasData) {
                                return _buildStatCard('Power Consumed', '...', Icons.bolt, Colors.orange);
                              }
                              final totalPower = powerSnapshot.data ?? 0.0;
                              return _buildStatCard(
                                'Power Consumed',
                                '${totalPower.toStringAsFixed(2)} kWh',
                                Icons.bolt,
                                Colors.orange,
                              );
                            },
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
                    'RUNTIME',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
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
                
                return FutureBuilder<List<DeviceWithUsage>>(
                  future: _loadDevicesWithUsage(appliances),
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
                    
                    final filteredDevices = filteredSnapshot.data!;
                    return ListView.separated(
                      itemCount: filteredDevices.length,
                      separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[200]),
                      itemBuilder: (context, index) => _buildDeviceRowOptimized(filteredDevices[index]),
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

  Future<List<DeviceWithUsage>> _loadDevicesWithUsage(List<QueryDocumentSnapshot> docs) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    
    var filtered = _applyBasicFilters(docs);
    final usageDataFutures = filtered.map((doc) => 
      _getDeviceUsageWithCache(user.uid, doc)
    ).toList();
    
    final deviceUsageList = await Future.wait(usageDataFutures);
    return deviceUsageList.where((d) => d.hasActivity).toList();
  }

  Future<DeviceWithUsage> _getDeviceUsageWithCache(
    String userId, 
    QueryDocumentSnapshot doc
  ) async {
    final applianceId = doc.id;
    final applianceData = doc.data() as Map<String, dynamic>;
    final cacheKey = _getCacheKey(applianceId);
    final isActive = applianceData['applianceStatus']?.toLowerCase() == 'on';
    
    DateTime? lastActivity = await _getAccurateLastActivity(userId, applianceId, applianceData);
    
    final cached = _usageCache[cacheKey];
    final now = DateTime.now();
    
    if (cached != null && now.difference(cached.timestamp).inMinutes < 2) {
      if (isActive) {
        final realTimeUsage = _calculateCurrentSessionUsage(applianceData);
        return DeviceWithUsage(
          doc: doc,
          historicalUsage: cached.usage,
          currentSessionUsage: realTimeUsage,
          lastActivity: lastActivity,
          isCurrentlyActive: true,
        );
      }
      
      return DeviceWithUsage(
        doc: doc,
        historicalUsage: cached.usage,
        currentSessionUsage: 0.0,
        lastActivity: lastActivity,
        isCurrentlyActive: false,
      );
    }
    
    final usageData = await _calculateHistoricalUsage(userId, applianceId, applianceData);
    _usageCache[cacheKey] = CachedUsageData(
      usage: usageData['kwh'],
      lastActivity: null,
      timestamp: now,
    );
    
    double currentSession = 0.0;
    
    if (isActive) {
      currentSession = _calculateCurrentSessionUsage(applianceData);
    }
    
    return DeviceWithUsage(
      doc: doc,
      historicalUsage: usageData['kwh'],
      currentSessionUsage: currentSession,
      lastActivity: lastActivity,
      isCurrentlyActive: isActive,
    );
  }

  Future<Map<String, dynamic>> _calculateHistoricalUsage(
    String userId, 
    String applianceId,
    Map<String, dynamic> applianceData,
  ) async {
    double totalKwh = 0.0;
    
    try {
      if (_selectedDateFilter == 'Today') {
        totalKwh = await _getAccurateDayUsage(userId, applianceId, DateTime.now());
      } 
      else if (_selectedDateFilter == 'Last 7 Days') {
        totalKwh = await _getAccurateDaysRangeUsage(userId, applianceId, 7);
      } 
      else if (_selectedDateFilter == 'Last 30 Days') {
        totalKwh = await _getAccurateDaysRangeUsage(userId, applianceId, 30);
      }
      else if (_selectedDateFilter == 'Months') {
        totalKwh = await _getAccurateSelectedMonthsUsage(userId, applianceId);
      }
      else if (_selectedDateFilter == 'All Time') {
        totalKwh = await _getAccurateAllTimeUsage(userId, applianceId);
      }
      
    } catch (e) {
      print('Error calculating historical usage for $applianceId: $e');
    }
    
    return {'kwh': totalKwh};
  }

  double _calculateCurrentSessionUsage(Map<String, dynamic> applianceData) {
    final wattage = (applianceData['wattage'] as num?)?.toDouble() ?? 0.0;
    final lastToggleTime = applianceData['lastToggleTime'] as Timestamp?;
    
    if (wattage == 0 || lastToggleTime == null) return 0.0;
    
    final toggleTime = lastToggleTime.toDate();
    final now = DateTime.now();
    
    if (!_isWithinDateRange(toggleTime)) return 0.0;
    
    final duration = now.difference(toggleTime);
    final hoursRunning = duration.inSeconds / 3600.0;
    return (wattage * hoursRunning) / 1000.0;
  }

  Future<double> _calculateTotalPowerOptimized(List<QueryDocumentSnapshot> docs) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0.0;
    
    try {
      final deviceUsageList = await _loadDevicesWithUsage(docs);
      double total = 0.0;
      for (var device in deviceUsageList) {
        total += device.totalUsage;
      }
      return total;
    } catch (e) {
      print('Error calculating total power: $e');
      return 0.0;
    }
  }

  List<QueryDocumentSnapshot> _applyBasicFilters(List<QueryDocumentSnapshot> docs) {
    List<QueryDocumentSnapshot> filtered = docs;
    
    if (_selectedDeviceFilter != 'All Devices') {
      String targetRoom = _selectedDeviceFilter.replaceAll(' Devices', '');
      filtered = filtered.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final roomName = data['roomName'] ?? '';
        return roomName.toLowerCase() == targetRoom.toLowerCase();
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

  Future<double> _getAccurateDayUsage(String userId, String applianceId, DateTime date) async {
    double totalKwh = 0.0;
    try {
      String yearStr = date.year.toString();
      String monthName = _getMonthName(date.month);
      int weekNumber = _getWeekOfMonth(date);
      String dayStr = DateFormat('yyyy-MM-dd').format(date);
      
      String dayPath = 'users/$userId/appliances/$applianceId/yearly_usage/$yearStr/monthly_usage/${monthName}_usage/week_usage/week${weekNumber}_usage/day_usage/$dayStr';
      
      DocumentSnapshot dayDoc = await FirebaseFirestore.instance.doc(dayPath).get();
      if (dayDoc.exists && dayDoc.data() != null) {
        final dayData = dayDoc.data() as Map<String, dynamic>;
        totalKwh = (dayData['kwh'] as num?)?.toDouble() ?? 0.0;
      }
    } catch (e) {
      print('Error getting day usage: $e');
    }
    return totalKwh;
  }

  Future<double> _getAccurateDaysRangeUsage(String userId, String applianceId, int days) async {
    double totalKwh = 0.0;
    final now = DateTime.now();
    
    List<Future<double>> dayUsageFutures = [];
    for (int i = 0; i < days; i++) {
      final targetDate = now.subtract(Duration(days: i));
      dayUsageFutures.add(_getAccurateDayUsage(userId, applianceId, targetDate));
    }
    
    final usageList = await Future.wait(dayUsageFutures);
    totalKwh = usageList.fold(0.0, (sum, usage) => sum + usage);
    
    return totalKwh;
  }

  Future<double> _getAccurateSelectedMonthsUsage(String userId, String applianceId) async {
    double totalKwh = 0.0;
    
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
        
        QuerySnapshot weekSnapshots = await FirebaseFirestore.instance
            .collection('$monthPath/week_usage')
            .get();
        
        for (var weekDoc in weekSnapshots.docs) {
          QuerySnapshot daySnapshots = await weekDoc.reference
              .collection('day_usage')
              .get();
          
          for (var dayDoc in daySnapshots.docs) {
            Map<String, dynamic> dayData = dayDoc.data() as Map<String, dynamic>;
            totalKwh += (dayData['kwh'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }
    } catch (e) {
      print('Error getting selected months usage: $e');
    }
    
    return totalKwh;
  }

  Future<double> _getAccurateAllTimeUsage(String userId, String applianceId) async {
    double totalKwh = 0.0;
    final now = DateTime.now();
    
    try {
      for (int year = 2025; year <= now.year; year++) {
        String yearPath = 'users/$userId/appliances/$applianceId/yearly_usage/$year';
        
        QuerySnapshot monthSnapshots = await FirebaseFirestore.instance
            .collection('$yearPath/monthly_usage')
            .get();
        
        for (var monthDoc in monthSnapshots.docs) {
          QuerySnapshot weekSnapshots = await monthDoc.reference
              .collection('week_usage')
              .get();
          
          for (var weekDoc in weekSnapshots.docs) {
            QuerySnapshot daySnapshots = await weekDoc.reference
                .collection('day_usage')
                .get();
            
            for (var dayDoc in daySnapshots.docs) {
              Map<String, dynamic> dayData = dayDoc.data() as Map<String, dynamic>;
              totalKwh += (dayData['kwh'] as num?)?.toDouble() ?? 0.0;
            }
          }
        }
      }
    } catch (e) {
      print('Error getting all-time usage: $e');
    }
    
    return totalKwh;
  }

  Future<DateTime?> _getAccurateLastActivity(String userId, String applianceId, Map<String, dynamic> applianceData) async {
    DateTime? lastActivity;
    
    try {
      String status = applianceData['applianceStatus'] ?? 'OFF';
      if (status.toLowerCase() == 'on') {
        return DateTime.now();
      }
      
      final lastToggleTime = applianceData['lastToggleTime'] as Timestamp?;
      final lastStatusChange = applianceData['lastStatusChange'] as Timestamp?;
      final lastUpdated = applianceData['lastUpdated'] as Timestamp?;
      final updatedAt = applianceData['updatedAt'] as Timestamp?;
      final createdAt = applianceData['createdAt'] as Timestamp?;
      final timestamp = applianceData['timestamp'] as Timestamp?;
      
      List<DateTime?> timestamps = [
        lastToggleTime?.toDate(),
        lastStatusChange?.toDate(),
        lastUpdated?.toDate(),
        updatedAt?.toDate(),
        createdAt?.toDate(),
        timestamp?.toDate(),
      ];
      
      for (DateTime? ts in timestamps) {
        if (ts != null) {
          if (lastActivity == null || ts.isAfter(lastActivity)) {
            lastActivity = ts;
          }
        }
      }
      
      if (lastActivity != null) {
        print('Found last activity for $applianceId: $lastActivity');
      }
      
    } catch (e) {
      print('Error getting accurate last activity: $e');
    }
    
    return lastActivity;
  }

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

  bool _isWithinDateRange(DateTime time) {
    final now = DateTime.now();
    switch (_selectedDateFilter) {
      case 'Today':
        return DateFormat('yyyy-MM-dd').format(time) == 
               DateFormat('yyyy-MM-dd').format(now);
      case 'Last 7 Days':
        return now.difference(time).inDays < 7;
      case 'Last 30 Days':
        return now.difference(time).inDays < 30;
      case 'Months':
        return _isToggleInSelectedMonths(time);
      case 'All Time':
        return true;
      default:
        return true;
    }
  }

  bool _isToggleInSelectedMonths(DateTime toggleTime) {
    if (toggleTime.year != _selectedYear) return false;
    if (_selectedMonths.isEmpty) return true;
    String toggleMonthName = months[toggleTime.month - 1];
    return _selectedMonths.contains(toggleMonthName);
  }

  int _getWeekOfMonth(DateTime date) {
    if (date.day <= 7) return 1;
    if (date.day <= 14) return 2;
    if (date.day <= 21) return 3;
    if (date.day <= 28) return 4;
    return 5;
  }

  String _getMonthName(int month) {
    const monthNames = ['', 'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
    return monthNames[month].toLowerCase();
  }

  String _getCacheKey(String applianceId) {
    return '$applianceId-$_selectedDateFilter-${_selectedMonths.join(",")}';
  }

  String _formatRuntime(Map<String, dynamic> applianceData, bool isCurrentlyActive) {
    if (!isCurrentlyActive) {
      return '--';
    }
    
    DateTime? start;
    final lastToggleTime = applianceData['lastToggleTime'] as Timestamp?;
    if (lastToggleTime != null) {
      start = lastToggleTime.toDate();
    }
    
    if (start == null) {
      return 'Running';
    }
    
    final now = DateTime.now();
    final duration = now.difference(start);
    
    if (duration.isNegative || duration.inDays > 7) {
      return 'Running';
    }

    return _formatDuration(duration);
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds}s';
    } else if (duration.inMinutes < 60) {
      return '${duration.inMinutes}m';
    } else if (duration.inHours < 24) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      if (minutes > 0) {
        return '${hours}h ${minutes}m';
      }
      return '${hours}h';
    } else {
      final days = duration.inDays;
      final hours = duration.inHours % 24;
      if (hours > 0) {
        return '${days}d ${hours}h';
      }
      return '${days}d';
    }
  }

  String _formatLastActivity(DateTime? activityTime, bool isCurrentlyActive) {
    if (isCurrentlyActive) {
      return 'Active now';
    }
    
    if (activityTime == null) return 'Never';
    
    final now = DateTime.now();
    final difference = now.difference(activityTime);

    if (difference.inSeconds < 30) {
      return 'Active just now';
    } else if (difference.inMinutes < 1) {
      return 'Active ${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return 'Active ${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return 'Active ${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return 'Active ${difference.inDays}d ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return 'Active ${weeks}w ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return 'Active ${months}mo ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return 'Active ${years}y ago';
    }
  }

  Widget _buildDeviceRowOptimized(DeviceWithUsage deviceData) {
    final applianceData = deviceData.doc.data() as Map<String, dynamic>;
    final deviceName = applianceData['applianceName'] ?? 'Unknown Device';
    final roomName = applianceData['roomName'] ?? 'Unknown Room';
    final isActive = deviceData.isCurrentlyActive;
    final totalUsage = deviceData.totalUsage;

    return GestureDetector(
      onTap: () => _showDeviceDetailsBottomSheet(deviceData.doc.id, applianceData, deviceData),
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
                  Text(deviceName, style: TextStyle(fontWeight: FontWeight.w500)),
                  Text(roomName, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(child: _buildActionStatusChip(isActive ? 'ON' : 'OFF')),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${totalUsage.toStringAsFixed(3)} kWh',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[700]),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _formatRuntime(applianceData, deviceData.isCurrentlyActive),
                style: TextStyle(
                  fontSize: 12,
                  color: deviceData.isCurrentlyActive ? Colors.green[700] : Colors.grey[600],
                  fontWeight: deviceData.isCurrentlyActive ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 1, blurRadius: 5)],
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
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.trending_up, color: color, size: 16),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
          Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
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
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error, size: 64, color: Colors.red[300]),
          SizedBox(height: 16),
          Text('Error loading data', style: TextStyle(fontSize: 16, color: Colors.red[600])),
          SizedBox(height: 8),
          Text('Please check your connection', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          SizedBox(height: 16),
          ElevatedButton(onPressed: () => setState(() {}), child: Text('Retry')),
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
          Text('Loading device history...', style: TextStyle(color: Colors.grey[600])),
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
          Text('No devices found', style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          SizedBox(height: 8),
          Text('Add devices to see them here', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
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
          Text('No results found', style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          SizedBox(height: 8),
          Text('Try adjusting your filters', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }

  void _showDeviceFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFE9E7E6),
          title: Text('Filter by Room'),
          titleTextStyle: GoogleFonts.jaldi(fontSize: 23, fontWeight: FontWeight.bold, color: Colors.black),
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
                      _usageCache.clear();
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
              child: Text('Cancel', style: GoogleFonts.inter(color: Colors.black, fontSize: 15)),
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
          titleTextStyle: GoogleFonts.jaldi(fontSize: 23, fontWeight: FontWeight.bold, color: Colors.black),
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
                      _usageCache.clear();
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
              child: Text('Cancel', style: GoogleFonts.inter(color: Colors.black, fontSize: 15)),
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
                    Text('Select Year and Months', style: GoogleFonts.jaldi(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
                    SizedBox(height: 16),
                    TextField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.inter(fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Year',
                        labelStyle: GoogleFonts.inter(),
                        hintText: 'Enter year (e.g., 2024)',
                        hintStyle: GoogleFonts.inter(color: Colors.grey),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                              style: TextButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black),
                              child: Text('Clear All', style: GoogleFonts.inter(fontSize: 12)),
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
                              style: TextButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
                              child: Text('Select All', style: GoogleFonts.inter(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: Colors.grey),
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
                              title: Text(month, style: GoogleFonts.inter(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
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
                          style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
                          child: Text('Cancel', style: GoogleFonts.inter()),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final year = int.tryParse(_yearController.text);
                            if (year == null || year < 2020 || year > DateTime.now().year + 1) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Please enter a valid year (2020-${DateTime.now().year + 1})'), backgroundColor: Colors.red),
                              );
                              return;
                            }
                            setState(() {
                              _selectedDateFilter = 'Months';
                              _selectedYear = year;
                              _usageCache.clear();
                            });
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
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

  void _showDeviceDetailsBottomSheet(String applianceId, Map<String, dynamic> applianceData, DeviceWithUsage deviceData) {
    final deviceName = applianceData['applianceName'] ?? 'Unknown Device';
    final roomName = applianceData['roomName'] ?? 'Unknown Room';
    final deviceType = applianceData['deviceType'] ?? 'Unknown Type';
    final wattage = (applianceData['wattage'] as num?)?.toDouble() ?? 0.0;
    final status = applianceData['applianceStatus'] ?? 'OFF';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE9E7E6),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(child: Text('Device Details', style: GoogleFonts.jaldi(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black))),
                        IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.of(context).pop(), padding: EdgeInsets.zero, constraints: BoxConstraints()),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey[300]),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.all(20),
                      children: [
                        _buildInfoCard(
                          title: 'Device Information',
                          icon: Icons.info_outline,
                          children: [
                            _buildDetailRow('Device Name:', deviceName),
                            _buildDetailRow('Room:', roomName),
                            _buildDetailRow('Device Type:', deviceType),
                            _buildDetailRow('Wattage:', '${wattage.toStringAsFixed(0)}W'),
                            _buildDetailRowWithStatus('Current Status:', status),
                          ],
                        ),
                        SizedBox(height: 16),
                        _buildInfoCard(
                          title: 'Usage Information',
                          icon: Icons.bolt,
                          children: [
                            _buildDetailRow('Date Range:', _getDateRangeDisplay()),
                            _buildDetailRowHighlighted('Total Energy Used:', '${deviceData.totalUsage.toStringAsFixed(3)} kWh', Colors.green[700]!),
                            if (deviceData.currentSessionUsage > 0)
                              _buildDetailRow('Current Session:', '${deviceData.currentSessionUsage.toStringAsFixed(3)} kWh'),
                            if (deviceData.isCurrentlyActive)
                              _buildDetailRowHighlighted('Runtime:', _formatRuntime(applianceData, deviceData.isCurrentlyActive), Colors.green[700]!)
                            else
                              _buildDetailRowHighlighted('Last Activity:', _formatLastActivity(deviceData.lastActivity, deviceData.isCurrentlyActive), Colors.grey[600]!),
                          ],
                        ),
                        SizedBox(height: 80),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.1), spreadRadius: 1, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 20, color: Colors.black87),
                SizedBox(width: 8),
                Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          Padding(padding: EdgeInsets.all(16), child: Column(children: children)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]))),
          SizedBox(width: 8),
          Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87))),
        ],
      ),
    );
  }

  Widget _buildDetailRowWithStatus(String label, String status) {
    Color statusColor;
    switch (status.toLowerCase()) {
      case 'on':
        statusColor = Colors.green;
        break;
      case 'off':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]))),
          SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Text(status.toUpperCase(), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRowHighlighted(String label, String value, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]))),
          SizedBox(width: 8),
          Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: color))),
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

class DeviceWithUsage {
  final QueryDocumentSnapshot doc;
  final double historicalUsage;
  final double currentSessionUsage;
  final DateTime? lastActivity;
  final bool isCurrentlyActive;
  
  DeviceWithUsage({
    required this.doc,
    required this.historicalUsage,
    required this.currentSessionUsage,
    this.lastActivity,
    required this.isCurrentlyActive,
  });
  
  bool get hasActivity => historicalUsage > 0 || currentSessionUsage > 0 || lastActivity != null;
  double get totalUsage => historicalUsage + currentSessionUsage;
}

class CachedUsageData {
  final double usage;
  final DateTime? lastActivity;
  final DateTime timestamp;
  
  CachedUsageData({
    required this.usage,
    this.lastActivity,
    required this.timestamp,
  });
}