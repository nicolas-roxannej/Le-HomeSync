import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/databaseservice.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

// to check if the month is leap year
bool isLeapYear(int year) {
  return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
}

class AddDeviceScreen extends StatefulWidget {
  final Map<String, dynamic>? deviceData;
  final String? initialRoomName;
  const AddDeviceScreen({super.key, this.deviceData, this.initialRoomName});

  @override
  _AddDeviceScreenState createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final List<String> _allRelays = List.generate(8, (index) => 'relay${index + 1}');
  List<String> _availableRelays = [];

  bool isEditing = false;
  bool _isLoading = true;

  final TextEditingController applianceNameController = TextEditingController();
  final TextEditingController wattageController = TextEditingController();
  final TextEditingController roomController = TextEditingController();
  final TextEditingController socketController = TextEditingController();

  String? selectedRelay;

  final _formKey = GlobalKey<FormState>();

  String deviceType = 'Light';
  String? selectedRoom;
  List<String> rooms = [];
  Map<String, IconData> roomIcons = {};

  TimeOfDay? startTime;
  TimeOfDay? endTime;

  final Map<String, Map<String, TimeOfDay>> presetTimes = {
    'Morning': {
      'start': TimeOfDay(hour: 6, minute: 0),
      'end': TimeOfDay(hour: 12, minute: 0),
    },
    'Afternoon': {
      'start': TimeOfDay(hour: 12, minute: 0),
      'end': TimeOfDay(hour: 18, minute: 0),
    },
    'Evening': {
      'start': TimeOfDay(hour: 18, minute: 0),
      'end': TimeOfDay(hour: 23, minute: 0),
    },
  };

  final List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  Map<String, bool> selectedDays = {
    'Mon': false,
    'Tue': false,
    'Wed': false,
    'Thu': false,
    'Fri': false,
    'Sat': false,
    'Sun': false,
  };

  IconData selectedIcon = Icons.device_hub;

  String? applianceNameError;
  String? wattageError;
  String? roomError;
  String? socketError;
  String? timeError;
  String? daysError;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    timeError = null;
    daysError = null;
  }

  void _fetchInitialData() async {
    setState(() {
      _isLoading = true;
    });

    await _fetchRoomsFromFirestore();
    await _fetchAndFilterRelays();

    if (widget.deviceData != null) {
      isEditing = true;
      final String? editingId = widget.deviceData!['id'] as String?;

      applianceNameController.text = widget.deviceData!['applianceName'] as String;
      wattageController.text = (widget.deviceData!['wattage'] ?? 0.0).toString();
      selectedRoom = widget.deviceData!['roomName'] as String?;
      deviceType = widget.deviceData!['deviceType'] as String? ?? 'Light';
      selectedRelay = widget.deviceData!['relay'] as String?;
      selectedIcon = IconData(widget.deviceData!['icon'] as int? ?? Icons.device_hub.codePoint, fontFamily: 'MaterialIcons');

      final startTimeString = widget.deviceData!['startTime'] as String?;
      final endTimeString = widget.deviceData!['endTime'] as String?;
      if (startTimeString != null) {
        try {
          final startTimeParts = startTimeString.split(':');
          startTime = TimeOfDay(hour: int.parse(startTimeParts[0]), minute: int.parse(startTimeParts[1]));
        } catch (e) {
          print("Error parsing start time: $e");
        }
      }
      if (endTimeString != null) {
        try {
          final endTimeParts = endTimeString.split(':');
          endTime = TimeOfDay(hour: int.parse(endTimeParts[0]), minute: int.parse(endTimeParts[1]));
        } catch (e) {
          print("Error parsing end time: $e");
        }
      }

      final daysList = List<String>.from(widget.deviceData!['days'] as List? ?? []);
      for (var day in selectedDays.keys) {
        selectedDays[day] = daysList.contains(day);
      }
    } else if (widget.initialRoomName != null) {
      selectedRoom = widget.initialRoomName;
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchAndFilterRelays() async {
    final userId = DatabaseService().getCurrentUserId();
    if (userId == null) {
      print("User not authenticated. Cannot fetch appliances.");
      setState(() {
        _availableRelays = [];
      });
      return;
    }

    try {
      final appliancesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .get();

      final occupiedRelays = <String>{};
      for (final doc in appliancesSnapshot.docs) {
        final data = doc.data();
        final assignedRelay = data['relay'] as String?;
        if (assignedRelay != null && assignedRelay.isNotEmpty) {
           if (isEditing && selectedRelay != null && assignedRelay == selectedRelay) {
               continue;
           }
           occupiedRelays.add(assignedRelay);
        }
      }

      setState(() {
        _availableRelays = _allRelays.where((relay) => !occupiedRelays.contains(relay)).toList();
        if (isEditing && selectedRelay != null && !_availableRelays.contains(selectedRelay)) {
           _availableRelays.add(selectedRelay!);
           _availableRelays.sort();
        }
      });

      print("Fetched and filtered relays based on appliances. Available: ${_availableRelays.length}");

    } catch (e) {
      print("Error fetching and filtering relays based on appliances: $e");
      setState(() {
        _availableRelays = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.black,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Custom App Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFF5F5F7),
                      Color(0xFFF5F5F7),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.0),
                      blurRadius: 1,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.arrow_back_ios_new, color: Colors.black, size: 20),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        isEditing ? 'Edit Appliance' : 'Add New Appliance',
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon Selector Card
                      Center(
                        child: GestureDetector(
                          onTap: () => _pickIcon(),
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.black,
                                  Colors.black,
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              selectedIcon,
                              size: 50,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Tap to change icon',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey.withOpacity(0.6),
                          ),
                        ),
                      ),
                      SizedBox(height: 30),

                      // Appliance Name
                      _buildSectionLabel('Appliance Name'),
                      _buildModernCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _addApplianceDialog,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(Icons.device_hub, size: 24, color: Colors.black),
                                      ),
                                      SizedBox(width: 15),
                                      Expanded(
                                        child: Text(
                                          applianceNameController.text.isEmpty 
                                            ? "Tap to add appliance" 
                                            : applianceNameController.text,
                                          style: GoogleFonts.poppins(
                                            fontSize: 15,
                                            color: applianceNameController.text.isEmpty 
                                              ? Colors.black.withOpacity(0.4)
                                              : Colors.black,
                                            fontWeight: applianceNameController.text.isEmpty 
                                              ? FontWeight.normal
                                              : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Icon(Icons.edit, size: 20, color: Colors.black),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        error: applianceNameError,
                      ),
                      SizedBox(height: 20),

                      // Wattage
                      _buildSectionLabel('Power Consumption'),
                      _buildModernTextField(
                        controller: wattageController,
                        hint: "Enter wattage (W)",
                        icon: Icons.bolt,
                        keyboardType: TextInputType.number,
                        errorText: wattageError,
                      ),
                      SizedBox(height: 20),

                      // Room and Device Type Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionLabel('Room'),
                                _buildModernDropdown(
                                  value: selectedRoom,
                                  items: rooms.isEmpty
                                    ? ['No Rooms']
                                    : rooms,
                                  hint: 'Select Room',
                                  icon: selectedRoom != null 
                                    ? (roomIcons[selectedRoom] ?? Icons.home)
                                    : Icons.home,
                                  onChanged: (value) {
                                    if (value == 'No Rooms') return;
                                    setState(() {
                                      selectedRoom = value;
                                      roomError = null;
                                    });
                                  },
                                  errorText: roomError,
                                  trailing: IconButton(
                                    icon: Container(
                                      padding: EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(Icons.add, size: 20, color: Colors.white),
                                    ),
                                    onPressed: _addRoomDialog,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),

                      // Device Type
                      _buildSectionLabel('Device Type'),
                      _buildModernDropdown(
                        value: deviceType,
                        items: ['Light', 'Socket'],
                        hint: 'Select Type',
                        icon: Icons.category,
                        onChanged: (value) {
                          setState(() {
                            deviceType = value!;
                            if (deviceType == 'Light') {
                              socketError = null;
                            }
                          });
                        },
                      ),
                      SizedBox(height: 20),

                      // Relay
                      _buildSectionLabel('Relay Connection'),
                      _buildModernDropdown(
                        value: selectedRelay,
                        items: _availableRelays,
                        hint: 'Select Relay',
                        icon: Icons.electrical_services,
                        onChanged: (value) {
                          setState(() {
                            selectedRelay = value;
                            socketError = null;
                          });
                        },
                        errorText: socketError,
                      ),
                      SizedBox(height: 30),

                      // Schedule Section
                      _buildSectionLabel('Schedule'),
                      _buildModernCard(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTimeSelector(
                                    label: 'Start Time',
                                    time: startTime,
                                    onTap: _pickStartTime,
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 40,
                                  color: Colors.black.withOpacity(0.1),
                                  margin: EdgeInsets.symmetric(horizontal: 12),
                                ),
                                Expanded(
                                  child: _buildTimeSelector(
                                    label: 'End Time',
                                    time: endTime,
                                    onTap: _pickEndTime,
                                  ),
                                ),
                              ],
                            ),
                            if (timeError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  timeError!,
                                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),

                      // Preset Times
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: BouncingScrollPhysics(),
                        child: Row(
                          children: presetTimes.keys.map((preset) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _buildPresetButton(preset),
                            );
                          }).toList(),
                        ),
                      ),
                      SizedBox(height: 24),

                      // Repeating Days
                    
                    _buildSectionLabel('Repeating Days'),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: BouncingScrollPhysics(),
                      child: Row(
                        children: weekdays.map((day) {
                          final isSelected = selectedDays[day] ?? false;
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: _buildDayChip(day, isSelected),
                          );
                        }).toList(),
                      ),
                    ),
                    SizedBox(height: 30),

                      // Action Buttons
                      Row(
                        children: [
                          if (isEditing)
                            Expanded(
                              child: _buildActionButton(
                                label: 'Delete',
                                onPressed: _deleteDevice,
                                isDestructive: true,
                              ),
                            ),
                          if (isEditing) SizedBox(width: 12),
                          Expanded(
                            flex: isEditing ? 2 : 1,
                            child: _buildActionButton(
                              label: isEditing ? 'Save Changes' : 'Add Device',
                              onPressed: _validateAndSubmitDevice,
                              isPrimary: true,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
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

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.black.withOpacity(0.9),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildModernCard({required Widget child, String? error}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: error != null 
                ? Colors.redAccent.withOpacity(0.5)
                : Colors.black.withOpacity(0.8),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8),
            child: Text(
              error,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.redAccent,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? errorText,
  }) {
    return _buildModernCard(
      error: errorText,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.poppins(
          fontSize: 15,
          color: Colors.black,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.poppins(
            fontSize: 15,
            color: Colors.grey.withOpacity(0.9),
          ),
          prefixIcon: Container(
            margin: EdgeInsets.all(12),
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 24, color: Colors.black),
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildModernDropdown({
    required String? value,
    required List<String> items,
    required String hint,
    required IconData icon,
    required Function(String?) onChanged,
    String? errorText,
    Widget? trailing,
  }) {
    return _buildModernCard(
      error: errorText,
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: ButtonTheme(
                alignedDropdown: true,
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  hint: Text(
                    hint,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: Colors.grey.withOpacity(0.9),
                    ),
                  ),
                  icon: Icon(Icons.keyboard_arrow_down, color: Colors.black),
                  dropdownColor: Colors.white,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    color: Colors.black,
                  ),
                  items: items.map((item) {
                    return DropdownMenuItem(
                      value: item,
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              item == value && value != null && roomIcons.containsKey(value)
                                ? roomIcons[value]!
                                : icon,
                              size: 20,
                              color: Colors.black,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item,
                              style: GoogleFonts.poppins(fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: onChanged,
                  selectedItemBuilder: (BuildContext context) {
                    return items.map((item) {
                      return Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              item == value && value != null && roomIcons.containsKey(value)
                                ? roomIcons[value]!
                                : icon,
                              size: 24,
                              color: Colors.black,
                            ),
                          ),
                          SizedBox(width: 15),
                          Expanded(
                            child: Text(
                              item,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildTimeSelector({
    required String label,
    required TimeOfDay? time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.black.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, color: Colors.black, size: 20),
                SizedBox(width: 8),
                Text(
                  time != null ? time.format(context) : '--:--',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetButton(String preset) {
    return InkWell(
      onTap: () => _applyPresetTime(preset),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
             Colors.black.withOpacity(0.2),
              Colors.black.withOpacity(0.2),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:Colors.black.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              preset == 'Morning' ? Icons.wb_sunny : 
              preset == 'Afternoon' ? Icons.wb_cloudy :
              Icons.nights_stay,
              color: Colors.black,
              size: 18,
            ),
            SizedBox(width: 8),
            Text(
              preset,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayChip(String day, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          selectedDays[day] = !isSelected;
          if (!isSelected) {
            daysError = null;
          }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
            ? LinearGradient(
                colors: [Colors.black, Colors.black],
              )
            : null,
          color: isSelected ? null : Colors.grey[400],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
              ? Colors.black
              : Colors.black.withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color:Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ] : null,
        ),
        child: Text(
          day,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
    bool isDestructive = false,
  }) {
    return Container(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: isPrimary
              ? LinearGradient(
                  colors: [Colors.black, Colors.black],
                )
              : isDestructive
                ? LinearGradient(
                    colors: [Color(0xFFE53935), Color(0xFFC62828)],
                  )
                : null,
            color: isPrimary || isDestructive ? null : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPrimary 
                ? Colors.transparent
                : isDestructive
                  ? Colors.transparent
                  : Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              if (isPrimary || isDestructive)
                BoxShadow(
                  color: (isPrimary ? Colors.black : Color(0xFFE53935)).withOpacity(0.4),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
            ],
          ),
          child: Container(
            alignment: Alignment.center,
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData roomIconSelected = Icons.home;

  void _addRoomDialog() {
    TextEditingController roomInput = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor:Color(0xFFE9E7E6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Add Room',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.black.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      controller: roomInput,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        color: Colors.black,
                      ),
                      decoration: InputDecoration(
                        hintText: "Room name",
                        hintStyle: GoogleFonts.poppins(
                          color: Colors.grey,
                          fontSize: 15,
                        ),
                        prefixIcon: Icon(
                          roomIconSelected,
                          color: Colors.black,
                          size: 24,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Select Icon',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 12),
                  Container(
                    height: 200,
                    width: double.maxFinite,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.black.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      padding: EdgeInsets.all(8),
                      children: const [
                        Icons.living, Icons.bed, Icons.kitchen, Icons.dining,
                        Icons.bathroom, Icons.meeting_room, Icons.garage, Icons.local_library, Icons.stairs,
                      ].map((icon) {
                        final isSelected = roomIconSelected == icon;
                        return Container(
                          margin: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            gradient: isSelected
                              ? LinearGradient(
                                  colors: [Colors.grey, Colors.grey],
                                )
                              : null,
                            color: isSelected ? null : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: IconButton(
                            icon: Icon(
                              icon,
                              color: Colors.black,
                            ),
                            onPressed: () {
                              setDialogState(() {
                                roomIconSelected = icon;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          }
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (roomInput.text.isNotEmpty) {
                _addRoomToFirestore(roomInput.text, roomIconSelected);

                setState(() {
                  rooms.add(roomInput.text);
                  selectedRoom = roomInput.text;
                  roomIcons[roomInput.text] = roomIconSelected;
                  roomError = null;
                });
              }
              Navigator.pop(context);
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.black),
              foregroundColor: WidgetStateProperty.all(Colors.white),
              padding: WidgetStateProperty.all(EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            child: Text(
              'Add',
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addApplianceDialog() {
    TextEditingController modelNameInput = TextEditingController();
    TextEditingController customBrandInput = TextEditingController();
    TextEditingController customApplianceInput = TextEditingController();
    String? selectedBrand;
    String? selectedApplianceType;
    bool showCustomBrand = false;
    bool showCustomAppliance = false;
    bool isApplianceDropdownOpen = false;
    
    final List<String> smartBrands = [
      'Samsung', 'LG', 'Xiaomi', 'Philips', 'Sony', 'Panasonic', 
      'TCL', 'Haier', 'Whirlpool', 'Electrolux', 'Bosch', 'GE',
      'KitchenAid', 'Frigidaire', 'Maytag', 'Fisher & Paykel',
      'Others',
    ];
    
    final List<String> applianceTypes = [
      'TV', 'Air Conditioner', 'Refrigerator', 'Washing Machine',
      'Microwave', 'Dishwasher', 'Coffee Maker', 'Rice Cooker',
      'Electric Fan', 'Heater', 'Speaker', 'Plugs', 'Air Fryers',
      'Light', 'Router', 'Home Hubs', 'Air Purifiers', 'Alarm Clocks',
      'Doorbell', 'CCTV', 'Smoke Alarm', 'Garage Door', 'Lock', 'Vacuums', 'Lamp',
    ];

    showDialog(
      context: context,
      builder: (_) {
        String? brandError;
        String? modelNameError;
        String? applianceTypeError;
        bool showCustomBrand = false;
        bool showCustomAppliance = false;
        bool isApplianceDropdownOpen = false;
        bool isBrandDropdownOpen = false;
        
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFE9E7E6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Add Appliance',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              isApplianceDropdownOpen = !isApplianceDropdownOpen;
                              isBrandDropdownOpen = false;
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: applianceTypeError != null 
                                    ? Colors.redAccent.withOpacity(0.5)
                                    : Colors.black.withOpacity(0.3),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  selectedApplianceType ?? 'Appliance Type',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    color: selectedApplianceType != null 
                                        ? Colors.black
                                        : Colors.black.withOpacity(0.4),
                                  ),
                                ),
                                Icon(
                                  isApplianceDropdownOpen 
                                      ? Icons.arrow_drop_up 
                                      : Icons.arrow_drop_down,
                                  color: Colors.black,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isApplianceDropdownOpen)
                          Container(
                            margin: EdgeInsets.only(top: 8),
                            padding: EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: Colors.black.withOpacity(0.3),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            constraints: BoxConstraints(maxHeight: 250),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ...applianceTypes.where((type) => type != 'Others').map((type) {
                                    return InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedApplianceType = type;
                                          isApplianceDropdownOpen = false;
                                          showCustomAppliance = false;
                                          customApplianceInput.clear();
                                          applianceTypeError = null;
                                        });
                                      },
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        child: Text(
                                          type,
                                          style: GoogleFonts.poppins(
                                            fontSize: 15,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        showCustomAppliance = !showCustomAppliance;
                                      });
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      child: Text(
                                        'Others',
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (showCustomAppliance)
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: Row(
                                        children: [
                                          Text(
                                            'Other: ',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Colors.black,
                                            ),
                                          ),
                                          Expanded(
                                            child: TextField(
                                              controller: customApplianceInput,
                                              autofocus: true,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: "Type Appliance",
                                                hintStyle: GoogleFonts.poppins(
                                                  color: Colors.white.withOpacity(0.4),
                                                  fontSize: 12,
                                                ),
                                                border: UnderlineInputBorder(
                                                  borderSide: BorderSide(color:Colors.black),
                                                ),
                                                enabledBorder: UnderlineInputBorder(
                                                  borderSide: BorderSide(color: Colors.black.withOpacity(0.3)),
                                                ),
                                                focusedBorder: UnderlineInputBorder(
                                                  borderSide: BorderSide(color: Colors.black),
                                                ),
                                                isDense: true,
                                                contentPadding: EdgeInsets.symmetric(vertical: 4),
                                              ),
                                              onSubmitted: (value) {
                                                if (value.trim().isNotEmpty) {
                                                  setDialogState(() {
                                                    selectedApplianceType = value.trim();
                                                    showCustomAppliance = false;
                                                    isApplianceDropdownOpen = false;
                                                    applianceTypeError = null;
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.check, color: Colors.black, size: 20),
                                            padding: EdgeInsets.zero,
                                            constraints: BoxConstraints(minWidth: 30, minHeight: 30),
                                            onPressed: () {
                                              if (customApplianceInput.text.trim().isNotEmpty) {
                                                setDialogState(() {
                                                  selectedApplianceType = customApplianceInput.text.trim();
                                                  showCustomAppliance = false;
                                                  isApplianceDropdownOpen = false;
                                                  applianceTypeError = null;
                                                });
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (applianceTypeError != null)
                          Padding(
                            padding: EdgeInsets.only(left: 16, top: 8),
                            child: Text(
                              applianceTypeError!,
                              style: TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              isBrandDropdownOpen = !isBrandDropdownOpen;
                              isApplianceDropdownOpen = false;
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: brandError != null 
                                    ? Colors.redAccent.withOpacity(0.5)
                                    : Colors.black.withOpacity(0.3),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  selectedBrand ?? 'Brand Name',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    color: selectedBrand != null 
                                        ? Colors.black
                                        : Colors.black.withOpacity(0.4),
                                  ),
                                ),
                                Icon(
                                  isBrandDropdownOpen 
                                      ? Icons.arrow_drop_up 
                                      : Icons.arrow_drop_down,
                                  color: Colors.black,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isBrandDropdownOpen)
                          Container(
                            margin: EdgeInsets.only(top: 8),
                            padding: EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: Colors.black.withOpacity(0.3),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            constraints: BoxConstraints(maxHeight: 250),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ...smartBrands.where((brand) => brand != 'Others').map((brand) {
                                    return InkWell(
                                      onTap: () {
                                        setDialogState(() {
                                          selectedBrand = brand;
                                          isBrandDropdownOpen = false;
                                          showCustomBrand = false;
                                          customBrandInput.clear();
                                          brandError = null;
                                        });
                                      },
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        child: Text(
                                          brand,
                                          style: GoogleFonts.poppins(
                                            fontSize: 15,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  InkWell(
                                    onTap: () {
                                      setDialogState(() {
                                        showCustomBrand = !showCustomBrand;
                                      });
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      child: Text(
                                        'Others',
                                        style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (showCustomBrand)
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: Row(
                                        children: [
                                          Text(
                                            'Other: ',
                                            style: GoogleFonts.poppins(
                                              fontSize: 14,
                                              color: Colors.black,
                                            ),
                                          ),
                                          Expanded(
                                            child: TextField(
                                              controller: customBrandInput,
                                              autofocus: true,
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: "Type brand name",
                                                hintStyle: GoogleFonts.poppins(
                                                  color: Colors.black.withOpacity(0.4),
                                                  fontSize: 12,
                                                ),
                                                border: UnderlineInputBorder(
                                                  borderSide: BorderSide(color: Colors.black),
                                                ),
                                                enabledBorder: UnderlineInputBorder(
                                                  borderSide: BorderSide(color: Colors.black.withOpacity(0.3)),
                                                ),
                                                focusedBorder: UnderlineInputBorder(
                                                  borderSide: BorderSide(color: Colors.black),
                                                ),
                                                isDense: true,
                                                contentPadding: EdgeInsets.symmetric(vertical: 4),
                                              ),
                                              onSubmitted: (value) {
                                                if (value.trim().isNotEmpty) {
                                                  setDialogState(() {
                                                    selectedBrand = value.trim();
                                                    showCustomBrand = false;
                                                    isBrandDropdownOpen = false;
                                                    brandError = null;
                                                  });
                                                }
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.check, color: Colors.black, size: 20),
                                            padding: EdgeInsets.zero,
                                            constraints: BoxConstraints(minWidth: 30, minHeight: 30),
                                            onPressed: () {
                                              if (customBrandInput.text.trim().isNotEmpty) {
                                                setDialogState(() {
                                                  selectedBrand = customBrandInput.text.trim();
                                                  showCustomBrand = false;
                                                  isBrandDropdownOpen = false;
                                                  brandError = null;
                                                });
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (brandError != null)
                          Padding(
                            padding: EdgeInsets.only(left: 16, top: 8),
                            child: Text(
                              brandError!,
                              style: TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: modelNameError != null 
                                ? Colors.redAccent.withOpacity(0.5)
                                : Colors.black.withOpacity(0.3),
                              width: 1.5,
                            ),
                          ),
                          child: TextField(
                            controller: modelNameInput,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              color: Colors.black,
                            ),
                            decoration: InputDecoration(
                              labelText: "Model Name",
                              labelStyle: GoogleFonts.poppins(
                                fontSize: 15,
                                color: Colors.black.withOpacity(0.6),
                              ),
                              hintText: "Enter model name",
                              hintStyle: GoogleFonts.poppins(
                                color: Colors.black.withOpacity(0.4),
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty && modelNameError != null) {
                                setDialogState(() {
                                  modelNameError = null;
                                });
                              }
                            },
                          ),
                        ),
                        if (modelNameError != null)
                          Padding(
                            padding: EdgeInsets.only(left: 16, top: 8),
                            child: Text(
                              modelNameError!,
                              style: TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    bool hasErrors = false;
                    setDialogState(() {
                      if (selectedApplianceType == null || selectedApplianceType == 'Others') {
                        applianceTypeError = "Appliance type is required";
                        hasErrors = true;
                      } else {
                        applianceTypeError = null;
                      }
                      if (selectedBrand == null || selectedBrand == 'Others') {
                        brandError = "Brand name is required";
                        hasErrors = true;
                      } else {
                        brandError = null;
                      }
                      if (modelNameInput.text.trim().isEmpty) {
                        modelNameError = "Model name is required";
                        hasErrors = true;
                      } else {
                        modelNameError = null;
                      }
                    });
                    if (!hasErrors) {
                      String applianceName = '$selectedApplianceType $selectedBrand - ${modelNameInput.text.trim()}';
                      
                      setState(() {
                        applianceNameController.text = applianceName;
                        applianceNameError = null;
                      });
                      
                      Navigator.pop(context);
                    }
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(Colors.black),
                    foregroundColor: WidgetStateProperty.all(Colors.white),
                    padding: WidgetStateProperty.all(EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  child: Text(
                    'Add',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

 void _pickIcon() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Color(0xFFE9E7E6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Choose Icon',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: const [
                  Icons.light, Icons.tv, Icons.power, Icons.kitchen,
                  Icons.speaker, Icons.laptop, Icons.ac_unit, Icons.microwave, Icons.coffee_maker, Icons.radio_button_checked,
                  Icons.thermostat, Icons.doorbell, Icons.camera, Icons.sensor_door, Icons.lock, Icons.door_sliding, Icons.local_laundry_service,
                  Icons.dining, Icons.rice_bowl, Icons.wind_power, Icons.router, Icons.outdoor_grill, Icons.air, Icons.alarm,
                ].map((icon) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.grey,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.black.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: IconButton(
                      icon: Icon(icon, color: Colors.black),
                      onPressed: () {
                        setState(() {
                          selectedIcon = icon;
                        });
                        Navigator.pop(context);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyPresetTime(String preset) {
    if (presetTimes.containsKey(preset)) {
      setState(() {
        startTime = presetTimes[preset]!['start'];
        endTime = presetTimes[preset]!['end'];
        timeError = null;
      });
    }
  }

  void _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: startTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        startTime = picked;
        if (endTime != null) {
          timeError = null;
        }
      });
    }
  }

  void _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: endTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        endTime = picked;
        if (startTime != null) {
          timeError = null;
        }
      });
    }
  }

  void _validateAndSubmitDevice() {
    bool isValid = true;

    if (applianceNameController.text.isEmpty) {
      setState(() {
        applianceNameError = "Appliance name is required";
      });
      isValid = false;
    } else {
      setState(() {
        applianceNameError = null;
      });
    }

    if (wattageController.text.isEmpty) {
      setState(() {
        wattageError = "Wattage is required";
      });
      isValid = false;
    } else {
      setState(() {
        wattageError = null;
      });
    }

    if (selectedRoom == null) {
      setState(() {
        roomError = "Room is required";
      });
      isValid = false;
    } else {
      setState(() {
        roomError = null;
      });
    }

    if (selectedRelay == null || selectedRelay!.isEmpty) {
      setState(() {
        socketError = "Relay is required";
      });
      isValid = false;
    } else {
      setState(() {
        socketError = null;
      });
    }

    setState(() {
      timeError = null;
    });

    setState(() {
      daysError = null;
    });

    if (isValid) {
      if (isEditing) {
        _updateDevice();
      } else {
        _submitDevice();
      }
      Navigator.of(context).pop();
    }
  }

  void _submitDevice() async {
    final DatabaseService dbService = DatabaseService();
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      print("User not authenticated. Cannot add device.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "User not authenticated. Cannot add device.",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          )
        );
      }
      return;
    }

    String presentYear = DateTime.now().year.toString();
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (userDoc.exists) {
        presentYear = (userDoc.data()?['presentYear'] as String?) ?? presentYear;
      }
    } catch (e) {
      print("Error fetching presentYear: $e");
    }

    final Map<String, dynamic> deviceData = {
      "applianceName": applianceNameController.text,
      "deviceType": deviceType,
      "wattage": double.tryParse(wattageController.text) ?? 0.0,
      "roomName": selectedRoom!,
      "icon": selectedIcon.codePoint,
      "startTime": startTime != null ? "${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}" : null,
      "endTime": endTime != null ? "${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}" : null,
      "days": selectedDays.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList(),
      "relay": selectedRelay,
      "applianceStatus": 'OFF',
    };

    print("Attempting to add appliance: $deviceData");

    try {
      final DocumentReference applianceRef = await dbService.addAppliance(applianceData: deviceData);
      print("Device successfully added to Firestore via DatabaseService with ID: ${applianceRef.id}");

      if (selectedRelay != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('relay_states')
              .doc(selectedRelay)
              .set({}, SetOptions(merge: true));
          print("Ensured relay_states document exists for $selectedRelay.");
        } catch (e) {
          print("Error ensuring relay_states document for $selectedRelay: $e");
        }
      }

      final yearlyUsageRef = applianceRef.collection('yearly_usage').doc(presentYear);
      await yearlyUsageRef.set({
        'kwh': 0.0,
        'kwhrcost': 0.0,
      });
      print("Initialized yearly_usage for appliance ${applianceRef.id} with document for year $presentYear");

      final List<String> months = [
        'jan_usage', 'feb_usage', 'mar_usage', 'apr_usage', 'may_usage', 'jun_usage',
        'jul_usage', 'aug_usage', 'sep_usage', 'oct_usage', 'nov_usage', 'dec_usage'
      ];

      for (String month in months) {
        final monthlyUsageRef = yearlyUsageRef.collection('monthly_usage').doc(month);
        await monthlyUsageRef.set({
          'kwh': 0.0,
          'kwhrcost': 0.0,
        });

        final now = DateTime.now();
        final currentYearInt = int.tryParse(presentYear) ?? now.year;
        final monthIndex = months.indexOf(month);
        int numberOfDays;

        if (month == 'feb_usage') {
          numberOfDays = isLeapYear(currentYearInt) ? 29 : 28;
        } else if (month == 'apr_usage' || month == 'jun_usage' || month == 'sep_usage' || month == 'nov_usage') {
          numberOfDays = 30;
        } else {
          numberOfDays = 31;
        }

        int currentDay = 1;
        int weekCounter = 1;
        while (currentDay <= numberOfDays) {
          final weeklyUsageRef = monthlyUsageRef.collection('week_usage').doc('week${weekCounter}_usage');
          await weeklyUsageRef.set({
            'kwh': 0.0,
            'kwhrcost': 0.0,
          });

          for (int day = 0; day < 7 && currentDay <= numberOfDays; day++) {
            final currentDate = DateTime(currentYearInt, monthIndex + 1, currentDay);
            final formattedDate = DateFormat('yyyy-MM-dd').format(currentDate);
            final dailyUsageRef = weeklyUsageRef.collection('day_usage').doc(formattedDate);
            await dailyUsageRef.set({
              'kwh': 0.0,
              'kwhrcost': 0.0,
              'usagetimeon': [],
              'usagetimeoff': [],
            });
            currentDay++;
          }
          weekCounter++;
        }
      }

      print("Initialized monthly, weekly, and daily usage structures with exact dates for appliance ${applianceRef.id}");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${deviceData['applianceName']} added successfully!",
              style: const TextStyle(color: Colors.black),
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          )
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("Error adding device via DatabaseService: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Error adding device: ${e.toString()}",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    }
  }

  void _updateDevice() async {
    final DatabaseService dbService = DatabaseService();
    if (widget.deviceData == null || widget.deviceData!['id'] == null) {
      print("Error: Cannot update device without an ID.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Error: Device ID not found for update.",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          )
        );
      }
      return;
    }
    final String applianceId = widget.deviceData!['id'] as String;

    final Map<String, dynamic> updatedData = {
      "applianceName": applianceNameController.text,
      "deviceType": deviceType,
      "wattage": double.tryParse(wattageController.text) ?? 0.0,
      "roomName": selectedRoom!,
      "icon": selectedIcon.codePoint,
      "startTime": startTime != null ? "${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}" : null,
      "endTime": endTime != null ? "${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}" : null,
      "days": selectedDays.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList(),
      "relay": selectedRelay,
    };

    print("Attempting to update device $applianceId with data: $updatedData");

    try {
      await dbService.updateApplianceData(applianceId: applianceId, dataToUpdate: updatedData);
      print("Device $applianceId successfully updated via DatabaseService.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${updatedData['applianceName']} updated successfully!",
              style: const TextStyle(color: Colors.black),
            ),
            backgroundColor: Colors.white,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          )
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("Error updating device $applianceId via DatabaseService: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Error updating device: ${e.toString()}",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    }
  }

  void _deleteDevice() async {
    final DatabaseService dbService = DatabaseService();
    if (widget.deviceData == null || widget.deviceData!['id'] == null) {
      print("Error: Cannot delete device without an ID.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Error: Device ID not found for deletion.",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          )
        );
      }
      return;
    }
    final String applianceId = widget.deviceData!['id'] as String;
    final String applianceNameToDelete = widget.deviceData!['applianceName'] as String? ?? "Device";

    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Color(0xFF16213E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Confirm Delete',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          content: Text(
            'Are you sure you want to delete "$applianceNameToDelete"? This will erase all associated usage data.',
            style: GoogleFonts.poppins(
              fontSize: 15,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: Text(
                'Delete',
                style: GoogleFonts.poppins(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      try {
        final userId = FirebaseAuth.instance.currentUser?.uid;
        if (userId != null) {
          final yearlyUsageSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('appliances')
              .doc(applianceId)
              .collection('yearly_usage')
              .get();

          for (final doc in yearlyUsageSnapshot.docs) {
            await doc.reference.delete();
          }
          print("Deleted yearly_usage subcollection for appliance $applianceId.");
        }

        await dbService.deleteAppliance(applianceId: applianceId);
        print("Device $applianceId successfully deleted via DatabaseService.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "$applianceNameToDelete deleted successfully!",
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            )
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        print("Error deleting device $applianceId via DatabaseService: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Error deleting device: ${e.toString()}",
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
            )
          );
        }
      }
    }
  }

  Future<void> _fetchRoomsFromFirestore() async {
    try {
      final userId = DatabaseService().getCurrentUserId();
      if (userId == null) {
        print("User not authenticated. Cannot fetch rooms.");
        setState(() {
          rooms = [];
          roomIcons = {};
        });
        return;
      }

      final roomsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('Rooms')
          .get();

      final List<String> fetchedRooms = [];
      final Map<String, IconData> fetchedIcons = {};

      for (final doc in roomsSnapshot.docs) {
        final data = doc.data();
        final roomName = data['roomName'] as String?;
        final iconCodePoint = data['icon'] as int?;

        if (roomName != null && roomName.isNotEmpty) {
          fetchedRooms.add(roomName);
          fetchedIcons[roomName] = iconCodePoint != null
              ? IconData(iconCodePoint, fontFamily: 'MaterialIcons')
              : Icons.home;
        }
      }

      setState(() {
        rooms = fetchedRooms;
        roomIcons = fetchedIcons;

        if (widget.initialRoomName != null && rooms.contains(widget.initialRoomName)) {
          selectedRoom = widget.initialRoomName;
        } else if (rooms.isNotEmpty) {
          selectedRoom = rooms.first;
        }
      });

      print("Fetched ${rooms.length} rooms from user's Rooms subcollection");

    } catch (e) {
      print("Error fetching rooms from user's subcollection: $e");
      setState(() {
        rooms = [];
        roomIcons = {};
      });
    }
  }

  void _addRoomToFirestore(String roomName, IconData icon) async {
    try {
      final userId = DatabaseService().getCurrentUserId();
      if (userId == null) {
        print("User not authenticated. Cannot add room.");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "User not authenticated. Cannot add room.",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          )
        );
        return;
      }

      final roomData = {
        'roomName': roomName,
        'icon': icon.codePoint,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('Rooms')
          .add(roomData);
      print("Added room '$roomName' to user's Rooms subcollection");
    } catch (e) {
      print("Error adding room to user's subcollection: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Room added locally but failed to save to database: ${e.toString()}",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        )
      );
    }
  }
}