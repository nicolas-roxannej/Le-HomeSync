import 'package:flutter/material.dart';
import 'package:homesync/notification_screen.dart';
import 'package:homesync/profile_screen.dart';
import 'package:weather/weather.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/welcome_screen.dart';
import 'package:homesync/room_data_manager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:homesync/about.dart';

const String _apiKey = 'd542f2e03ea5728e77e367f19c0fb675'; 
const String _cityName = 'Manila'; 

class Rooms extends StatefulWidget {
  const Rooms({super.key});

  @override
  State<Rooms> createState() => RoomsState();
}

class RoomsState extends State<Rooms> with SingleTickerProviderStateMixin {
  Weather? _currentWeather;
  int _selectedIndex = 2;
  final RoomDataManager _roomDataManager = RoomDataManager();

  // Search functionality variables
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Method to get username from Firestore
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

  // Weather fetching method
  Future<void> _fetchWeather() async {
    if (_apiKey == 'YOUR_API_KEY') {
      print("Weather API key is a placeholder. Please replace it.");
      if (mounted) {
        setState(() {
        });
      }
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

  // Helper method to filter rooms based on search query
  List<RoomItem> _filterRooms(List<RoomItem> allRooms) {
    if (_searchQuery.isEmpty) {
      return allRooms;
    } else {
      return allRooms.where((room) {
        final String roomName = room.title.toLowerCase();
        final String searchLower = _searchQuery.toLowerCase();
        return roomName.contains(searchLower);
      }).toList();
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
    
    // Initialize search controller listener
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddRoomDialog(context);
        },
        backgroundColor: Colors.black,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
        elevation: 8,
      ),
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
                    BoxShadow(
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
                        // Rooms Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Your Rooms',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 20),

                        // Search Bar
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search rooms...',
                              hintStyle: GoogleFonts.inter(
                                fontSize: 15,
                                color: Colors.grey[500],
                              ),
                              prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[600]),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.clear_rounded, color: Colors.grey[600]),
                                      onPressed: () {
                                        _searchController.clear();
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            ),
                            style: GoogleFonts.inter(fontSize: 15),
                          ),
                        ),
                        SizedBox(height: 24),

                        // Room List
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseAuth.instance.currentUser != null
                              ? FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(FirebaseAuth.instance.currentUser!.uid)
                                  .collection('Rooms')
                                  .snapshots()
                              : Stream.empty(),
                          builder: (context, roomSnapshot) {
                            if (roomSnapshot.hasError) {
                              print("Error fetching rooms: ${roomSnapshot.error}");
                              return _buildErrorCard('Error loading rooms: ${roomSnapshot.error}');
                            }

                            if (roomSnapshot.connectionState == ConnectionState.waiting) {
                              return Center(
                                child: Padding(
                                  padding: EdgeInsets.all(40),
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                  ),
                                ),
                              );
                            }
                            
                            if (FirebaseAuth.instance.currentUser == null) {
                              return _buildEmptyCard('Please log in to view your rooms.');
                            }

                            if (roomSnapshot.data!.docs.isEmpty) {
                              return _buildEmptyCard('No rooms found. Add a room to get started.');
                            }

                            // Fetch devices for all rooms
                            return StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(FirebaseAuth.instance.currentUser!.uid)
                                  .collection('appliances')
                                  .snapshots(),
                              builder: (context, deviceSnapshot) {
                                if (deviceSnapshot.hasError) {
                                  print("Error fetching devices: ${deviceSnapshot.error}");
                                  return _buildErrorCard('Error loading devices: ${deviceSnapshot.error}');
                                }

                                // Create a map of room name to appliance names
                                final Map<String, List<String>> roomDevices = {};
                                
                                if (deviceSnapshot.hasData) {
                                  for (final doc in deviceSnapshot.data!.docs) {
                                    final data = doc.data() as Map<String, dynamic>;
                                    final roomName = data['roomName'] as String? ?? '';
                                    final applianceName = data['applianceName'] as String? ?? 'Unknown Device';
                                    
                                    final trimmedRoomName = roomName.trim();
                                    
                                    if (trimmedRoomName.isNotEmpty) {
                                      if (!roomDevices.containsKey(trimmedRoomName)) {
                                        roomDevices[trimmedRoomName] = [];
                                      }
                                      roomDevices[trimmedRoomName]!.add(applianceName);
                                    }
                                  }
                                }

                                // Convert Firestore documents to RoomItem objects with appliances
                                final List<RoomItem> allRooms = roomSnapshot.data!.docs.map((doc) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final roomName = (data['roomName'] as String? ?? 'Unknown Room').trim();
                                  final iconCodePoint = data['icon'] as int? ?? Icons.home.codePoint;
                                  
                                  final appliances = roomDevices[roomName] ?? [];
                                  
                                  return RoomItem(
                                    title: roomName,
                                    icon: _getIconFromCodePoint(iconCodePoint),
                                    appliances: appliances,
                                  );
                                }).toList();

                                // Filter rooms based on search query
                                final List<RoomItem> filteredRooms = _filterRooms(allRooms);

                                if (filteredRooms.isEmpty && _searchQuery.isNotEmpty) {
                                  return _buildEmptyCard("No rooms found matching '$_searchQuery'");
                                }

                                return _buildRoomsList(filteredRooms);
                              },
                            );
                          },
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
              Navigator.pushNamed(context, '/homepage');
              break;
            case 1:
              Navigator.pushNamed(context, '/devices');
              break;
            case 2:
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

  Widget _buildEmptyCard(String message) {
    return Container(
      padding: EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.meeting_room_rounded, size: 48, color: Colors.grey[400]),
            SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.inter(
                color: Colors.grey[600],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: Colors.red[400]),
            SizedBox(height: 12),
            Text(
              message,
              style: GoogleFonts.inter(
                color: Colors.grey[600],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomsList(List<RoomItem> rooms) {
    return Container(
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
        itemCount: rooms.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          indent: 70,
          endIndent: 20,
          color: Colors.grey[200],
        ),
        itemBuilder: (context, index) {
          return RoomListTile(
            room: rooms[index],
            onDelete: () {
              _deleteRoom(rooms[index].title);
            },
            onEdit: (newName) {
              _editRoomName(rooms[index].title, newName);
            },
          );
        },
      ),
    );
  }

  void _deleteRoom(String roomName) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        print("User not authenticated. Cannot delete room.");
        return;
      }

      final roomQuerySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('Rooms')
          .where('roomName', isEqualTo: roomName)
          .limit(1)
          .get();

      if (roomQuerySnapshot.docs.isNotEmpty) {
        final roomIdToDelete = roomQuerySnapshot.docs.first.id;
        
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('Rooms')
            .doc(roomIdToDelete)
            .delete();
            
        print('Deleted room: $roomName');
      } else {
        print('Room not found for deletion: $roomName');
      }

      final deviceQuerySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .where('roomName', isEqualTo: roomName)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in deviceQuerySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      
      print('Deleted ${deviceQuerySnapshot.docs.length} devices associated with room: $roomName');

    } catch (e) {
      print('Error deleting room: $e');
    }
  }

  void _editRoomName(String oldName, String newName) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        print("User not authenticated. Cannot edit room name.");
        return;
      }

      final roomQuerySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('Rooms')
          .where('roomName', isEqualTo: oldName)
          .limit(1)
          .get();

      if (roomQuerySnapshot.docs.isNotEmpty) {
        final roomIdToUpdate = roomQuerySnapshot.docs.first.id;
        
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('Rooms')
            .doc(roomIdToUpdate)
            .update({'roomName': newName});
            
        print('Updated room name from $oldName to $newName');
      } else {
        print('Room not found for editing: $oldName');
      }

      final deviceQuerySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .where('roomName', isEqualTo: oldName)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in deviceQuerySnapshot.docs) {
        batch.update(doc.reference, {'roomName': newName});
      }
      await batch.commit();
      
      print('Updated room name for ${deviceQuerySnapshot.docs.length} devices associated with room: $oldName');

    } catch (e) {
      print('Error editing room name: $e');
    }
  }

  void _showAddRoomDialog(BuildContext context) {
    TextEditingController roomInput = TextEditingController();
    IconData roomIconSelected = Icons.home;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setDialogState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add Room',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    SizedBox(height: 20),
                    TextField(
                      controller: roomInput,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        color: Colors.black,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        hintText: "Room name",
                        hintStyle: GoogleFonts.inter(
                          color: Colors.grey[500],
                          fontSize: 15,
                        ),
                        prefixIcon: Container(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            roomIconSelected,
                            color: Colors.black,
                            size: 24,
                          ),
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      ),
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Select Icon',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    SizedBox(height: 12),
                    Container(
                      height: 200,
                      width: double.maxFinite,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        padding: EdgeInsets.all(8),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        children: const [
                          Icons.living, Icons.bed, Icons.kitchen, Icons.dining,
                          Icons.bathroom, Icons.meeting_room, Icons.garage, Icons.local_library, Icons.stairs,
                        ].map((icon) {
                          bool isSelected = roomIconSelected == icon;
                          return GestureDetector(
                            onTap: () {
                              setDialogState(() {
                                roomIconSelected = icon;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.black : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                icon,
                                color: isSelected ? Colors.white : Colors.black,
                                size: 28,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            if (roomInput.text.isNotEmpty) {
                              final newRoomName = roomInput.text;
                              final iconCodePoint = roomIconSelected.codePoint;

                              final userId = FirebaseAuth.instance.currentUser?.uid;
                              if (userId == null) {
                                print("User not authenticated. Cannot add room.");
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("User not authenticated. Cannot add room."),
                                      backgroundColor: Colors.red[400],
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  );
                                }
                                Navigator.pop(context);
                                return;
                              }

                              final roomData = {
                                'roomName': newRoomName,
                                'icon': iconCodePoint,
                                'createdAt': FieldValue.serverTimestamp(),
                              };

                              try {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(userId)
                                    .collection('Rooms')
                                    .add(roomData);

                                print('Added room: $newRoomName to user $userId Rooms subcollection with auto-generated ID');

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          Icon(Icons.check_circle_rounded, color: Colors.white),
                                          SizedBox(width: 12),
                                          Text("Room '$newRoomName' added successfully!"),
                                        ],
                                      ),
                                      backgroundColor: Color(0xFF4CAF50),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } catch (e) {
                                print('Error adding room to user subcollection: $e');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Failed to add room: ${e.toString()}"),
                                      backgroundColor: Colors.red[400],
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  );
                                }
                              }
                            }
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Add',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }
          ),
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
                          colors: [Color(0xFFE9EFEC), Colors.white],
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
                          await FirebaseAuth.instance.signOut();
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

class RoomItem {
  final String title;
  final IconData icon;
  final List<String> appliances;

  RoomItem({
    required this.title,
    required this.icon,
    this.appliances = const [],
  });
}

class RoomListTile extends StatelessWidget {
  final RoomItem room;
  final VoidCallback onDelete;
  final Function(String) onEdit;

  const RoomListTile({
    super.key,
    required this.room,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final String title = room.title;
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, '/roominfo', arguments: title);
      },
      onDoubleTap: () {
        _showAppliancesDialog(context);
      },
      onLongPress: () {
        _showEditDialog(context);
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
              child: Icon(room.icon, size: 28, color: Colors.black),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.title,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  if (room.appliances.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        '${room.appliances.length} ${room.appliances.length == 1 ? 'device' : 'devices'}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
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

  void _showAppliancesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
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
                  'Appliances in ${room.title}',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                SizedBox(height: 20),
                SizedBox(
                  width: double.maxFinite,
                  child: room.appliances.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.devices_other_rounded, size: 40, color: Colors.grey[400]),
                                SizedBox(height: 12),
                                Text(
                                  'No appliances in this room',
                                  style: GoogleFonts.inter(
                                    color: Colors.grey[600],
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Container(
                          constraints: BoxConstraints(maxHeight: 300),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: room.appliances.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              color: Colors.grey[200],
                            ),
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(Icons.devices, size: 20, color: Colors.black),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        room.appliances[index],
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
                SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Close',
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
      },
    );
  }
  
  void _showEditDialog(BuildContext context) {
  final TextEditingController nameController = TextEditingController(text: room.title);

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: EdgeInsets.symmetric(horizontal: 16),
        child: SingleChildScrollView(
          child: Container(
            width: double.maxFinite,
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
                  'Edit Room',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  style: GoogleFonts.inter(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Room Name',
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  ),
                ),
                SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        onDelete();
                        Navigator.of(context).pop();
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: Icon(Icons.delete_rounded, color: Colors.red, size: 20),
                      label: Text(
                        'Delete',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        SizedBox(width: 4),
                        ElevatedButton(
                          onPressed: () {
                            if (nameController.text.isNotEmpty) {
                              onEdit(nameController.text);
                            }
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Save',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
}