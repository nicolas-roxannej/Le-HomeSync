import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/notification_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> with SingleTickerProviderStateMixin {
  bool _isSelectionMode = false;
  bool _selectAll = false;
  bool _showingArchived = false;
  List<NotificationItem> _notifications = [];
  List<NotificationItem> _archivedNotifications = [];
  List<NotificationItem> _selectedNotifications = [];

  StreamSubscription<QuerySnapshot>? _notificationsSub;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _initNotificationsListener();
  }

  @override
  void dispose() {
    _notificationsSub?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _initNotificationsListener() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final local = await _loadNotificationsFromPrefs();
      setState(() => _notifications = local);
      final prefs = await SharedPreferences.getInstance();
      final lastTapped = prefs.getString('last_tapped_notification_docid') ?? '';
      if (lastTapped.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tapped notification: $lastTapped')));
        await prefs.remove('last_tapped_notification_docid');
      }
      return;
    }

    final coll = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('notifications');
    _notificationsSub = coll.orderBy('createdAt', descending: true).snapshots().listen((snap) {
      final active = <NotificationItem>[];
      final archived = <NotificationItem>[];
      for (var doc in snap.docs) {
        final data = doc.data();
        final title = (data['title'] as String?) ?? (data['body'] as String?) ?? '';
        final body = (data['body'] as String?) ?? '';
        final typeStr = (data['type'] as String?) ?? 'system';
        final isArchived = (data['archived'] as bool?) ?? false;
        String timeString = '';
        try {
          final ts = (data['createdAt'] ?? data['timestamp']);
          if (ts is Timestamp) {
            timeString = _readableTime(ts.toDate());
          } else {
            timeString = '';
          }
        } catch (_) {
          timeString = '';
        }

        final item = NotificationItem(
          id: doc.id,
          title: title,
          description: body,
          time: timeString,
          isSelected: false,
          type: typeStr,
        );
        if (isArchived) archived.add(item); else active.add(item);
      }
      setState(() {
        _notifications = active;
        _archivedNotifications = archived;
        SharedPreferences.getInstance().then((prefs) async {
          final lastTapped = prefs.getString('last_tapped_notification_docid') ?? '';
          if (lastTapped.isNotEmpty) {
            final combined = [..._notifications, ..._archivedNotifications];
            final found = combined.indexWhere((n) => n.id == lastTapped);
            if (found != -1) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tapped notification: ${combined[found].title}')));
            }
            await prefs.remove('last_tapped_notification_docid');
          }
        });
      });
    }, onError: (e) async {
      final local = await _loadNotificationsFromPrefs();
      setState(() => _notifications = local);
    });
  }

  Future<List<NotificationItem>> _loadNotificationsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('local_notifications') ?? [];
    final out = <NotificationItem>[];
    for (var s in list) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        final localId = (m['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString();
        final title = (m['title'] as String?) ?? '';
        final body = (m['body'] as String?) ?? '';
        final time = (m['time'] as String?) ?? '';
        final docId = (m['docId'] as String?) ?? '';
        final typeRaw = (m['type'] as String?) ?? 'system';
        final type = typeRaw.split('.').last;
        out.add(NotificationItem(id: docId.isNotEmpty ? docId : localId, title: title, description: body, time: time, isSelected: false, type: type));
      } catch (_) {}
    }
    return out;
  }

  String _readableTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return 'Today, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else {
      return '${diff.inDays} days ago';
    }
  }

  void _enterSelectionMode(NotificationItem notification) {
    setState(() {
      _isSelectionMode = true;
      notification.isSelected = true;
      _updateSelectedNotifications();
    });
    _animationController.forward();
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectAll = false;
      
      for (var notification in _notifications) {
        notification.isSelected = false;
      }
      for (var notification in _archivedNotifications) {
        notification.isSelected = false;
      }
      _selectedNotifications.clear();
    });
    _animationController.reverse();
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      List<NotificationItem> currentList = _showingArchived ? _archivedNotifications : _notifications;
      for (var notification in currentList) {
        notification.isSelected = _selectAll;
      }
      _updateSelectedNotifications();
    });
  }

  void _updateSelectedNotifications() {
    List<NotificationItem> currentList = _showingArchived ? _archivedNotifications : _notifications;
    _selectedNotifications = currentList.where((n) => n.isSelected).toList();
  }

  void _archiveSelected() {
    if (_selectedNotifications.isEmpty) return;
    
    setState(() {
      for (var notification in _selectedNotifications) {
        notification.isSelected = false;
        _archivedNotifications.add(notification);
      }
      
      _notifications.removeWhere((notification) => _selectedNotifications.contains(notification));
      
      _selectedNotifications.clear();
      _isSelectionMode = false;
      _selectAll = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Notifications archived successfully'),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    _persistArchiveSelected(_selectedNotifications, archived: true);
  }

  void _unarchiveSelected() {
    if (_selectedNotifications.isEmpty) return;
    
    setState(() {
      for (var notification in _selectedNotifications) {
        notification.isSelected = false;
        _notifications.add(notification);
      }
      
      _archivedNotifications.removeWhere((notification) => _selectedNotifications.contains(notification));
      
      _selectedNotifications.clear();
      _isSelectionMode = false;
      _selectAll = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Text('Notifications unarchived successfully'),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF2196F3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    _persistArchiveSelected(_selectedNotifications, archived: false);
  }

  Future<void> _persistArchiveSelected(List<NotificationItem> items, {required bool archived}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      for (var item in items) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('notifications').doc(item.id).set({'archived': archived, 'timestamp': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        } catch (e) {
          print('NotificationScreen: Failed to update archived state for ${item.id}: $e');
        }
      }
    } catch (e) {
      print('NotificationScreen: Error persisting archive state: $e');
    }
  }

  void _goToArchive() {
    setState(() {
      _showingArchived = true;
      _exitSelectionMode();
    });
  }

  void _goBackToActive() {
    setState(() {
      _showingArchived = false;
      _exitSelectionMode();
    });
  }

  List<NotificationItem> _getCurrentNotificationsList() {
    return _showingArchived ? _archivedNotifications : _notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: _getCurrentNotificationsList().isEmpty
                  ? _buildEmptyNotifications()
                  : _buildNotificationsList(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isSelectionMode
          ? _buildSelectionModeBar()
          : null,
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: Color(0xFFE9E7E6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios_new, size: 22, color: Colors.black87),
              onPressed: () {
                if (_showingArchived) {
                  _goBackToActive();
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                _showingArchived ? 'Archived' : 'Notifications',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          if (!_showingArchived) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                icon: Icon(Icons.archive_outlined, color: Colors.black87, size: 22),
                onPressed: _goToArchive,
                tooltip: 'View Archived',
              ),
            ),
            SizedBox(width: 8),
          ],
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.settings_outlined, color: Colors.black87, size: 22),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => NotificationSettings()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyNotifications() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _showingArchived ? Icons.archive_outlined : Icons.notifications_outlined,
              size: 80,
              color: Colors.black26,
            ),
          ),
          SizedBox(height: 24),
          Text(
            _showingArchived ? 'No Archived Notifications' : 'No Notifications',
            style: GoogleFonts.inter(
              color: Colors.black54,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            _showingArchived ? 'Archived items will appear here' : 'You\'re all caught up!',
            style: GoogleFonts.inter(
              color: Colors.black38,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsList() {
    List<NotificationItem> currentList = _getCurrentNotificationsList();
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: currentList.length,
      itemBuilder: (context, index) {
        final notification = currentList[index];
        return AnimatedScale(
          scale: notification.isSelected ? 0.98 : 1.0,
          duration: Duration(milliseconds: 200),
          child: NotificationCard(
            notification: notification,
            isDeleteMode: _isSelectionMode,
            onToggleSelection: () {
              setState(() {
                notification.isSelected = !notification.isSelected;
                if (!notification.isSelected) {
                  _selectAll = false;
                } else {
                  _selectAll = currentList.every((n) => n.isSelected == true);
                }
                _updateSelectedNotifications();
                
                if (_selectedNotifications.isEmpty) {
                  _isSelectionMode = false;
                }
              });
            },
            onLongPress: () {
              if (!_isSelectionMode) {
                _enterSelectionMode(notification);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildSelectionModeBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            GestureDetector(
              onTap: _toggleSelectAll,
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _selectAll ? Colors.black87 : Colors.transparent,
                      border: Border.all(
                        color: _selectAll ? Colors.black87 : Colors.black38,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: _selectAll
                        ? Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Select All',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Spacer(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _showingArchived 
                      ? [Colors.black, Colors.black]
                      : [Colors.black, Colors.black],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (_showingArchived ? Colors.black : Colors.black).withOpacity(0.3),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _showingArchived ? _unarchiveSelected : _archiveSelected,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(_showingArchived ? Icons.unarchive : Icons.archive, size: 20),
                label: Text(
                  _showingArchived ? 'Unarchive' : 'Archive',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationItem {
  final String id;
  final String title;
  final String description;
  final String time;
  final String type;
  bool isSelected;

  NotificationItem({
    required this.id,
    required this.title,
    required this.description,
    required this.time,
    required this.isSelected,
    this.type = 'system',
  });
}

class NotificationCard extends StatelessWidget {
  final NotificationItem notification;
  final bool isDeleteMode;
  final VoidCallback onToggleSelection;
  final VoidCallback onLongPress;
  final VoidCallback? onDelete;

  const NotificationCard({
    super.key,
    required this.notification,
    required this.isDeleteMode,
    required this.onToggleSelection,
    required this.onLongPress,
    this.onDelete,
  });

  IconData _getNotificationIcon(String type) {
    switch (type.toLowerCase()) {
      case 'device':
        return Icons.devices_outlined;
      case 'security':
        return Icons.security_outlined;
      case 'reminder':
        return Icons.schedule_outlined;
      case 'alert':
        return Icons.warning_amber_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type.toLowerCase()) {
      case 'device':
        return Colors.black;
      case 'security':
        return Color(0xFFF44336);
      case 'reminder':
        return Color(0xFF4CAF50);
      case 'alert':
        return Color(0xFFFF9800);
      default:
        return Color(0xFF9E9E9E);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.09),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onLongPress: onLongPress,
          onTap: isDeleteMode ? onToggleSelection : null,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDeleteMode)
                  Container(
                    margin: EdgeInsets.only(right: 16),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: notification.isSelected ? Colors.black87 : Colors.transparent,
                      border: Border.all(
                        color: notification.isSelected ? Colors.black87 : Colors.black26,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: notification.isSelected
                        ? Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  )
                else
                  Container(
                    margin: EdgeInsets.only(right: 16),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _getNotificationColor(notification.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _getNotificationIcon(notification.type),
                      color: _getNotificationColor(notification.type),
                      size: 24,
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                      ),
                      if (notification.description.isNotEmpty) ...[
                        SizedBox(height: 6),
                        Text(
                          notification.description,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.black54,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 14, color: Colors.black38),
                          SizedBox(width: 4),
                          Text(
                            notification.time,
                            style: GoogleFonts.inter(
                              color: Colors.black38,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}