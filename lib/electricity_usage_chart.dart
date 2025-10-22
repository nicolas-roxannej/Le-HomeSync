import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class ChartDataPoint {
  final String xLabel;
  final double kwh;
  final double cost;
  final int xIndex;

  ChartDataPoint({required this.xIndex, required this.xLabel, required this.kwh, required this.cost});
}

class ElectricityUsageChart extends StatefulWidget {
  final String selectedPeriod; 

  const ElectricityUsageChart({
    super.key, 
    required this.selectedPeriod,
  });

  @override
  State<ElectricityUsageChart> createState() => _ElectricityUsageChartState();
}

class _ElectricityUsageChartState extends State<ElectricityUsageChart> {
  bool _isLoading = true;
  String _displayMode = 'kWh'; // 'kWh' or 'cost'
  List<ChartDataPoint> _chartDataPoints = [];
  double _maxY = 10.0;
  String _chartTitle = '';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final List<Color> _barColors = [
    const Color.fromARGB(255, 150, 204, 229),  
    Colors.black,               
    const Color.fromARGB(255, 248, 198, 133), 
  ];

  @override
  void initState() {
    super.initState();
    _fetchChartData();
  }

  @override
  void didUpdateWidget(covariant ElectricityUsageChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPeriod != oldWidget.selectedPeriod) {
      _fetchChartData();
    }
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

  Future<List<String>> _getApplianceIds(String userId) async {
    final snapshot = await _firestore.collection('users').doc(userId).collection('appliances').get();
    return snapshot.docs.map((doc) => doc.id).toList();
  }

  // Calculate real-time usage for devices that are currently ON
  Future<Map<String, double>> _calculateCurrentSessionUsage(String userId, List<String> applianceIds, DateTime targetDate) async {
    Map<String, double> currentSessionData = {'kwh': 0.0, 'cost': 0.0};
    String targetDayStr = DateFormat('yyyy-MM-dd').format(targetDate);
    DateTime now = DateTime.now();
    
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
        String toggleDayStr = DateFormat('yyyy-MM-dd').format(toggleTime);
        
        // Only include if toggle was on the target date
        if (toggleDayStr == targetDayStr) {
          Duration runningTime = now.difference(toggleTime);
          double hoursRunning = runningTime.inSeconds / 3600.0;
          double sessionKwh = (wattage * hoursRunning) / 1000.0;
          
          // user's kWh rate
          DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
          double kwhrRate = 0.15; // Default
          if (userDoc.exists && userDoc.data() != null) {
            kwhrRate = ((userDoc.data() as Map<String, dynamic>)['kwhr'] as num?)?.toDouble() ?? 0.15;
          }
          
          double sessionCost = sessionKwh * kwhrRate;
          
          currentSessionData['kwh'] = (currentSessionData['kwh'] ?? 0.0) + sessionKwh;
          currentSessionData['cost'] = (currentSessionData['cost'] ?? 0.0) + sessionCost;
        }
      } catch (e) {
        print('Error calculating current session for $applianceId: $e');
      }
    }
    
    return currentSessionData;
  }

  Future<void> _fetchChartData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _chartDataPoints = []; 
    });

    final User? user = _auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }
    final userId = user.uid;
    final now = DateTime.now();
    List<ChartDataPoint> newPoints = [];

    List<String> applianceIds = await _getApplianceIds(userId);
    if (!mounted) return;

    try {
      switch (widget.selectedPeriod) {
        case 'Daily':
          _chartTitle = 'Daily Usage (This Week)';
          DateTime firstDayOfWeek = now.subtract(Duration(days: now.weekday == DateTime.sunday ? 6 : now.weekday - 1));

          // daily
          final dailyResults = await Future.wait(
            List.generate(7, (i) async {
              DateTime dayToFetch = firstDayOfWeek.add(Duration(days: i));
              String dayLabel = DateFormat('EEE').format(dayToFetch);
              
              // Fetch from all appliances 
              final applianceResults = await Future.wait(
                applianceIds.map((applianceId) async {
                  String path = 'users/$userId/appliances/$applianceId/yearly_usage/${dayToFetch.year}/monthly_usage/${_getMonthName(dayToFetch.month)}_usage/week_usage/week${_getWeekOfMonth(dayToFetch)}_usage/day_usage/${DateFormat('yyyy-MM-dd').format(dayToFetch)}';
                  DocumentSnapshot docSnap = await _firestore.doc(path).get();
                  
                  if (docSnap.exists && docSnap.data() != null) {
                    final data = docSnap.data() as Map<String, dynamic>;
                    return {
                      'kwh': (data['kwh'] as num?)?.toDouble() ?? 0.0,
                      'cost': (data['kwhrcost'] as num?)?.toDouble() ?? 0.0,
                    };
                  }
                  return {'kwh': 0.0, 'cost': 0.0};
                })
              );
              
              double dailyTotalKwh = applianceResults.fold(0.0, (sum, result) => sum + result['kwh']!);
              double dailyTotalCost = applianceResults.fold(0.0, (sum, result) => sum + result['cost']!);
              
              // Add current session (today)
              if (DateFormat('yyyy-MM-dd').format(dayToFetch) == DateFormat('yyyy-MM-dd').format(now)) {
                Map<String, double> currentSession = await _calculateCurrentSessionUsage(userId, applianceIds, dayToFetch);
                dailyTotalKwh += currentSession['kwh'] ?? 0.0;
                dailyTotalCost += currentSession['cost'] ?? 0.0;
              }
              
              return ChartDataPoint(xIndex: i, xLabel: dayLabel, kwh: dailyTotalKwh, cost: dailyTotalCost);
            })
          );
          
          newPoints = dailyResults;
          break;

        case 'Weekly': 
          _chartTitle = 'Weekly Usage (${DateFormat('MMMM yyyy').format(now)})';
          int year = now.year;
          int month = now.month;
          
          // all weeks
          final weeklyResults = await Future.wait(
            List.generate(5, (weekNum) async {
              String weekLabel = 'W${weekNum + 1}';
              
              // Process all appliances 
              final applianceResults = await Future.wait(
                applianceIds.map((applianceId) async {
                  String weekPath = 'users/$userId/appliances/$applianceId/yearly_usage/$year/monthly_usage/${_getMonthName(month)}_usage/week_usage/week${weekNum + 1}_usage';
                  QuerySnapshot dayDocs = await _firestore.collection('$weekPath/day_usage').get();
                  
                  double weekKwh = 0.0;
                  double weekCost = 0.0;
                  
                  for (var dayDoc in dayDocs.docs) {
                    if (dayDoc.exists && dayDoc.data() != null) {
                      final data = dayDoc.data() as Map<String, dynamic>;
                      weekKwh += (data['kwh'] as num?)?.toDouble() ?? 0.0;
                      weekCost += (data['kwhrcost'] as num?)?.toDouble() ?? 0.0;
                    }
                  }
                  
                  return {'kwh': weekKwh, 'cost': weekCost};
                })
              );
              
              double weeklyTotalKwh = applianceResults.fold(0.0, (sum, result) => sum + result['kwh']!);
              double weeklyTotalCost = applianceResults.fold(0.0, (sum, result) => sum + result['cost']!);
              
              //  current week session
              if (year == now.year && month == now.month && (weekNum + 1) == _getWeekOfMonth(now)) {
                Map<String, double> currentSession = await _calculateCurrentSessionUsage(userId, applianceIds, now);
                weeklyTotalKwh += currentSession['kwh'] ?? 0.0;
                weeklyTotalCost += currentSession['cost'] ?? 0.0;
              }
              
              return {
                'point': ChartDataPoint(xIndex: weekNum, xLabel: weekLabel, kwh: weeklyTotalKwh, cost: weeklyTotalCost),
                'hasData': weeklyTotalKwh > 0 || weeklyTotalCost > 0,
              };
            })
          );
          
       
          for (var result in weeklyResults) {
            bool isPotentiallyValid = (result['point'] as ChartDataPoint).xIndex < (DateUtils.getDaysInMonth(year, month) / 7.0).ceil();
            if (result['hasData'] == true || isPotentiallyValid) {
              newPoints.add(result['point'] as ChartDataPoint);
            }
          }
          
         
          if (newPoints.isNotEmpty && newPoints.last.xLabel == 'W5' && newPoints.last.kwh == 0 && newPoints.last.cost == 0) {
            if ((DateUtils.getDaysInMonth(year, month) / 7.0).ceil() < 5) {
              newPoints.removeLast();
            }
          }
          break;

        case 'Monthly':
          _chartTitle = 'Current Monthly Usage (${now.year})';
          
         //  12 months
          final monthlyResults = await Future.wait(
            List.generate(12, (monthIndex) async {
              int monthNum = monthIndex + 1;
              String monthLabel = DateFormat('MMM').format(DateTime(now.year, monthNum));
              
              // all appliance
              final applianceResults = await Future.wait(
                applianceIds.map((applianceId) async {
                  String monthPath = 'users/$userId/appliances/$applianceId/yearly_usage/${now.year}/monthly_usage/${_getMonthName(monthNum)}_usage';
                  QuerySnapshot weekDocs = await _firestore.collection('$monthPath/week_usage').get();
                  
                  // all weeks
                  final weekResults = await Future.wait(
                    weekDocs.docs.map((weekDoc) async {
                      QuerySnapshot dayDocs = await weekDoc.reference.collection('day_usage').get();
                      
                      return dayDocs.docs.fold<Map<String, double>>({'kwh': 0.0, 'cost': 0.0}, (sum, dayDoc) {
                        if (dayDoc.exists && dayDoc.data() != null) {
                          final data = dayDoc.data() as Map<String, dynamic>;
                          return {
                            'kwh': sum['kwh']! + ((data['kwh'] as num?)?.toDouble() ?? 0.0),
                            'cost': sum['cost']! + ((data['kwhrcost'] as num?)?.toDouble() ?? 0.0),
                          };
                        }
                        return sum;
                      });
                    })
                  );
                  
                  return weekResults.fold<Map<String, double>>({'kwh': 0.0, 'cost': 0.0}, (sum, weekData) {
                    return {
                      'kwh': sum['kwh']! + weekData['kwh']!,
                      'cost': sum['cost']! + weekData['cost']!,
                    };
                  });
                })
              );
              
              double monthlyTotalKwh = applianceResults.fold(0.0, (sum, result) => sum + result['kwh']!);
              double monthlyTotalCost = applianceResults.fold(0.0, (sum, result) => sum + result['cost']!);
              
              //  current month session
              if (monthNum == now.month && now.year == now.year) {
                Map<String, double> currentSession = await _calculateCurrentSessionUsage(userId, applianceIds, now);
                monthlyTotalKwh += currentSession['kwh'] ?? 0.0;
                monthlyTotalCost += currentSession['cost'] ?? 0.0;
              }
              
              return ChartDataPoint(xIndex: monthIndex, xLabel: monthLabel, kwh: monthlyTotalKwh, cost: monthlyTotalCost);
            })
          );
          
          newPoints = monthlyResults;
          break;

        case 'Yearly':
          _chartTitle = 'Current Yearly Usage (${now.year})';
          
          // all months
          final yearlyResults = await Future.wait(
            List.generate(12, (monthIndex) async {
              int monthNum = monthIndex + 1;
              String monthLabel = DateFormat('MMM').format(DateTime(now.year, monthNum));
              
              // all appliances
              final applianceResults = await Future.wait(
                applianceIds.map((applianceId) async {
                  String monthPath = 'users/$userId/appliances/$applianceId/yearly_usage/${now.year}/monthly_usage/${_getMonthName(monthNum)}_usage';
                  QuerySnapshot weekDocs = await _firestore.collection('$monthPath/week_usage').get();
                  
                  // all weeeks
                  final weekResults = await Future.wait(
                    weekDocs.docs.map((weekDoc) async {
                      QuerySnapshot dayDocs = await weekDoc.reference.collection('day_usage').get();
                      
                      return dayDocs.docs.fold<Map<String, double>>({'kwh': 0.0, 'cost': 0.0}, (sum, dayDoc) {
                        if (dayDoc.exists && dayDoc.data() != null) {
                          final data = dayDoc.data() as Map<String, dynamic>;
                          return {
                            'kwh': sum['kwh']! + ((data['kwh'] as num?)?.toDouble() ?? 0.0),
                            'cost': sum['cost']! + ((data['kwhrcost'] as num?)?.toDouble() ?? 0.0),
                          };
                        }
                        return sum;
                      });
                    })
                  );
                  
                  return weekResults.fold<Map<String, double>>({'kwh': 0.0, 'cost': 0.0}, (sum, weekData) {
                    return {
                      'kwh': sum['kwh']! + weekData['kwh']!,
                      'cost': sum['cost']! + weekData['cost']!,
                    };
                  });
                })
              );
              
              double monthlyTotalKwh = applianceResults.fold(0.0, (sum, result) => sum + result['kwh']!);
              double monthlyTotalCost = applianceResults.fold(0.0, (sum, result) => sum + result['cost']!);
              //current month session
              if (monthNum == now.month && now.year == now.year) {
                Map<String, double> currentSession = await _calculateCurrentSessionUsage(userId, applianceIds, now);
                monthlyTotalKwh += currentSession['kwh'] ?? 0.0;
                monthlyTotalCost += currentSession['cost'] ?? 0.0;
              }
              
              return ChartDataPoint(xIndex: monthIndex, xLabel: monthLabel, kwh: monthlyTotalKwh, cost: monthlyTotalCost);
            })
          );
          
          newPoints = yearlyResults;
          break;
      }
    } catch (e) {
      print("Error fetching chart data: $e");
    }

    if (!mounted) return;
    setState(() {
      _chartDataPoints = newPoints;
      _updateMaxY();
      _isLoading = false;
    });
  }

  void _updateMaxY() {
    if (_chartDataPoints.isEmpty) {
      _maxY = 10;
      return;
    }
    double maxVal = 0;
    for (var point in _chartDataPoints) {
      double currentVal = _displayMode == 'kWh' ? point.kwh : point.cost;
      if (currentVal > maxVal) {
        maxVal = currentVal;
      }
    }
    _maxY = maxVal == 0 ? 10 : (maxVal * 1.2); 
  }

  BarChartGroupData _generateBarGroup(int x, double value) {
    Color barColor = _barColors[x % _barColors.length];
    
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: value,
          color: barColor,
          width: 15,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _getBottomTitles(double value, TitleMeta meta) {
    String text = '';
    if (value.toInt() >= 0 && value.toInt() < _chartDataPoints.length) {
      text = _chartDataPoints[value.toInt()].xLabel;
    }
    return Text(text, style: const TextStyle(fontSize: 10, color: Colors.black54));
  }
  
  Widget _getLeftTitles(double value, TitleMeta meta) {
    if (value == meta.max || value == meta.min) {
      return const Text('');
    }
    if (meta.appliedInterval < 1 && value % 1 != 0) {
      if(value != value.floor()){
        return const Text('');
      }
    }

    return Text(meta.formattedValue, style: const TextStyle(fontSize: 10, color: Colors.black54));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_chartDataPoints.isEmpty && !_isLoading) {
      return Center(child: Text('No usage data available for ${widget.selectedPeriod} period.'));
    }

    List<BarChartGroupData> barGroups = [];
    for(var point in _chartDataPoints) {
      barGroups.add(
        _generateBarGroup(
          point.xIndex,
          _displayMode == 'kWh' ? point.kwh : point.cost
        )
      );
    }
    _updateMaxY();

    return Column(
      children: [
        Text(_chartTitle, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _displayMode = _displayMode == 'kWh' ? 'cost' : 'kWh';
              _updateMaxY();
            });
          },
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.black, 
          ),
          child: Text(_displayMode == 'kWh' ? 'Show kWh Usage' : 'Show Estimated Cost'),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _maxY,
                minY: 0,
                groupsSpace: 12,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => Colors.grey.shade700, 
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final point = _chartDataPoints[group.x.toInt()];
                      final val = _displayMode == 'kWh' ? point.kwh : point.cost;
                      final unit = _displayMode == 'kWh' ? 'kWh' : '₱';
                      
                      String text = '${val.toStringAsFixed(2)} $unit';

                      return BarTooltipItem(
                        text,
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tooltipMargin: 8,
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, 
                      getTitlesWidget: _getBottomTitles, 
                      reservedSize: 30,
                    )
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, 
                      getTitlesWidget: _getLeftTitles, 
                      reservedSize: 42,
                      interval: null,
                    )
                  ),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: false, 
                ),
                gridData: FlGridData(
                  show: true, 
                  drawVerticalLine: false, 
                  horizontalInterval: null,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.black.withOpacity(0.2), 
                      strokeWidth: 0.6,
                    );
                  },
                ),
                barGroups: barGroups,
              ),
            ),
          ),
        ),
      ],
    );
  }
}