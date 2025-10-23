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

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isSelectionMode = false;
  bool _selectAll = false;
  bool _showingArchived = false;
  List<NotificationItem> _notifications = [];
  List<NotificationItem> _archivedNotifications = [];
  List<NotificationItem> _selectedNotifications = [];

  StreamSubscription<QuerySnapshot>? _notificationsSub;

  @override
  void initState() {
    super.initState();
    _initNotificationsListener();
  }

  @override
  void dispose() {
    _notificationsSub?.cancel();
    super.dispose();
  }

  void _initNotificationsListener() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Fallback to local storage for unauthenticated users
      final local = await _loadNotificationsFromPrefs();
      setState(() => _notifications = local);
      // Check last tapped doc id (from local taps)
      final prefs = await SharedPreferences.getInstance();
      final lastTapped = prefs.getString('last_tapped_notification_docid') ?? '';
      if (lastTapped.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tapped notification: $lastTapped')));
        await prefs.remove('last_tapped_notification_docid');
      }
      return;
    }

  // Prefer ordering by createdAt (new schema). Fall back to timestamp for older records.
  final coll = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('notifications');
  // Use a try/catch ordering by createdAt; if createdAt missing on some docs, the query still works.
  _notificationsSub = coll.orderBy('createdAt', descending: true).snapshots().listen((snap) {
      final active = <NotificationItem>[];
      final archived = <NotificationItem>[];
      for (var doc in snap.docs) {
        final data = doc.data();
        final title = (data['title'] as String?) ?? (data['body'] as String?) ?? '';
        final body = (data['body'] as String?) ?? '';
        final typeStr = (data['type'] as String?) ?? 'system';
        final isArchived = (data['archived'] as bool?) ?? false;
        // Read createdAt if available, else fallback to older timestamp field
        String timeString = '';
        try {
          final ts = (data['createdAt'] ?? data['timestamp']); // prefer createdAt
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
        // Show last tapped doc id if present (quick highlight feedback)
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
      // If listener fails, fallback to local prefs
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
        final type = typeRaw.split('.').last; // e.g. NotificationType.device
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

  // Deletion helpers removed: deletion/remote delete is disabled per specification.

  void _enterSelectionMode(NotificationItem notification) {
    setState(() {
      _isSelectionMode = true;
      notification.isSelected = true;
      _updateSelectedNotifications();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectAll = false;
      
      // Clear all selections
      for (var notification in _notifications) {
        notification.isSelected = false;
      }
      for (var notification in _archivedNotifications) {
        notification.isSelected = false;
      }
      _selectedNotifications.clear();
    });
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
      // Move selected notifications to archived list
      for (var notification in _selectedNotifications) {
        notification.isSelected = false;
        _archivedNotifications.add(notification);
      }
      
      // Remove from main notifications list
      _notifications.removeWhere((notification) => _selectedNotifications.contains(notification));
      
      _selectedNotifications.clear();
      _isSelectionMode = false;
      _selectAll = false;
    });

    // Show confirmation message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Notifications archived successfully'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
    // Note: deletion to Firestore is intentionally disabled per specification.
    // Persist archived flag to Firestore for selected notifications (if user is signed in)
    _persistArchiveSelected(_selectedNotifications, archived: true);
  }

  // Attempt to delete corresponding Firestore notifications if they exist.
  // Deletion persistence disabled intentionally.

  void _unarchiveSelected() {
    if (_selectedNotifications.isEmpty) return;
    
    setState(() {
      // Move selected archived notifications back to main list
      for (var notification in _selectedNotifications) {
        notification.isSelected = false;
        _notifications.add(notification);
      }
      
      // Remove from archived list
      _archivedNotifications.removeWhere((notification) => _selectedNotifications.contains(notification));
      
      _selectedNotifications.clear();
      _isSelectionMode = false;
      _selectAll = false;
    });

    // Show confirmation message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Notifications unarchived successfully'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.blue,
      ),
    );
    // Persist unarchive state
    _persistArchiveSelected(_selectedNotifications, archived: false);
  }

  Future<void> _persistArchiveSelected(List<NotificationItem> items, {required bool archived}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return; // only persist for authenticated users
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

  // Per spec: deletion UI removed and deletion operations disabled.

  List<NotificationItem> _getCurrentNotificationsList() {
    return _showingArchived ? _archivedNotifications : _notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.only(left: 5, top: 70),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, size: 50, color: Colors.black),
                  onPressed: () {
                    if (_showingArchived) {
                      _goBackToActive();
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                ),
                Transform.translate(
                  offset: Offset(1, -1),
                  child: Expanded(
                    child: Text(
                      _showingArchived ? 'Archived' : 'Notification',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jaldi(
                        textStyle: TextStyle(
                            fontSize: 23, fontWeight: FontWeight.bold),
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                if (!_showingArchived) ...[
                  Transform.translate(
                    offset: Offset(70, -1),
                    child: IconButton(
                      icon: Icon(Icons.archive_outlined, color: Colors.black, size: 30),
                      onPressed: _goToArchive,
                      tooltip: 'View Archived',
                    ),
                  ),
                ],
                Transform.translate(
                  offset: Offset(_showingArchived ? 120: 68, -1),
                  child: IconButton(
                    icon: Icon(Icons.settings, color: Colors.black, size: 30),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => NotificationSettings()),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _getCurrentNotificationsList().isEmpty
                ? _buildEmptyNotifications()
                : _buildNotificationsList(),
          ),
        ],
      ),
      bottomNavigationBar: _isSelectionMode
          ? _buildSelectionModeBar()
          : null,
    );
  }

  Widget _buildEmptyNotifications() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.translate(
            offset: Offset(0, -70),
            child: Icon(
              Icons.notifications,
              size: 100,
              color: const Color(0xFF757575),
            ),
          ),
          SizedBox(height: 16),
          Transform.translate(
            offset: Offset(0, -85),
            child: Text(
              _showingArchived ? 'No Archived Notifications' : 'No Notification',
              style: GoogleFonts.inter(
                color: Colors.grey[600],
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsList() {
    List<NotificationItem> currentList = _getCurrentNotificationsList();
    return ListView.builder(
      itemCount: currentList.length,
      itemBuilder: (context, index) {
        final notification = currentList[index];
        return NotificationCard(
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
              
              // Exit selection mode if no items selected
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
        
        );
      },
    );
  }

  Widget _buildSelectionModeBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFE9E7E6),
      child: Row(
        children: [
          Row(
            children: [
              Checkbox(
                value: _selectAll,
                onChanged: (value) {
                  _toggleSelectAll();
                },
              ),
              Transform.translate(
                offset: Offset(-5, 0),
                child: Text(
                  'Select All',
                  style: GoogleFonts.jaldi(
                    textStyle: TextStyle(
                      fontSize: 18,
                    ),
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          Spacer(),
          ElevatedButton.icon(
            onPressed: _showingArchived ? _unarchiveSelected : _archiveSelected,
            style: ElevatedButton.styleFrom(
              backgroundColor: _showingArchived ? Colors.blue : Colors.orange,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            icon: Icon(
              _showingArchived ? Icons.unarchive : Icons.archive,
              size: 20,
            ),
            label: Text(
              _showingArchived ? 'Unarchive Selected' : 'Archive Selected',
              style: TextStyle(
                fontSize: 15,
              ),
            ),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, -15),
      child: Card(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        elevation: 5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onLongPress: onLongPress,
          onTap: isDeleteMode ? onToggleSelection : null,
          child: ListTile(
            contentPadding: EdgeInsets.all(16),
            leading: isDeleteMode
                ? Checkbox(
                    value: notification.isSelected,
                    onChanged: (value) {
                      onToggleSelection();
                    },
                  )
                : CircleAvatar(
                    backgroundColor: Colors.grey,
                    child: Icon(
                      Icons.notifications,
                      color: Colors.black,
                    ),
                  ),
            title: Text(
              notification.title,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 4),
                Text(notification.description),
                SizedBox(height: 4),
                Text(
                  notification.time,
                  style: GoogleFonts.inter(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: null,
          ),
        ),
      ),
    );
  }
}