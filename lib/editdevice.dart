import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/databaseservice.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditDeviceScreen extends StatefulWidget {
  final String applianceId;
  const EditDeviceScreen({super.key, required this.applianceId});

  @override
  _EditDeviceScreenState createState() => _EditDeviceScreenState();
}

class _EditDeviceScreenState extends State<EditDeviceScreen> {
  final List<String> _allRelays = List.generate(8, (index) => 'relay${index + 1}');
  List<String> _availableRelays = [];

  bool isEditing = false;
  bool _isLoading = true;

  final TextEditingController applianceNameController = TextEditingController();
  final TextEditingController wattageController = TextEditingController();
  final TextEditingController roomController = TextEditingController();
  final TextEditingController relayController = TextEditingController();

  String? selectedRelay;
  final _formKey = GlobalKey<FormState>();

  String deviceType = 'Light';
  String? selectedRoom;
  List<String> rooms = [];
  Map<String, IconData> roomIcons = {};

  List<String> _roomNames = [];

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
  String? daysError;

  @override
  void initState() {
    super.initState();
    wattageError = null;
    roomError = null;
    socketError = null;
    daysError = null;
    
    // Fetch device data and rooms only when user is authenticated
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _fetchDeviceData();
      _fetchRooms();
    }

    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _fetchDeviceData();
        _fetchRooms();
        _fetchAndFilterRelays();
      }
    });
  }

  void _fetchDeviceData() async {
    try {
      final deviceData = await DatabaseService().getApplianceData(widget.applianceId);
      if (deviceData != null) {
        setState(() {
          isEditing = true;
          applianceNameController.text = deviceData['applianceName'] as String;
          wattageController.text = (deviceData['wattage'] ?? 0.0).toString();
          
          selectedRoom = deviceData['roomName'] as String?;
          if (selectedRoom != null) {
            roomController.text = selectedRoom!;
          }
          
          deviceType = deviceData['deviceType'] as String? ?? 'Light';
          
          selectedRelay = deviceData['relay'] as String?;
          if (selectedRelay != null) {
            relayController.text = selectedRelay!;
          }
          
          selectedIcon = _getIconFromCodePoint(deviceData['icon'] as int? ?? Icons.device_hub.codePoint);

          final startTimeString = deviceData['startTime'] as String?;
          final endTimeString = deviceData['endTime'] as String?;
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

          final daysList = List<String>.from(deviceData['days'] as List? ?? []);
          for (var day in selectedDays.keys) {
            selectedDays[day] = daysList.contains(day);
          }
          
          _isLoading = false;
        });
        await _fetchAndFilterRelays();
      } else {
        print("Device with ID ${widget.applianceId} not found.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Device not found.",
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(
                bottom: MediaQuery.of(context).size.height - 150,
                left: 10,
                right: 10,
              ),
            )
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      print("Error fetching device data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Error loading device data: ${e.toString()}",
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 10,
              right: 10,
            ),
          )
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _fetchRooms() async {
    print("Fetching rooms for EditDeviceScreen...");
    final userId = DatabaseService().getCurrentUserId();
    if (userId == null) {
      print("User not logged in, cannot fetch rooms for EditDeviceScreen.");
      return;
    }
    print("Fetching rooms for user ID: $userId");
    try {
      final roomDocs = await DatabaseService().getCollection(collectionPath: 'users/$userId/Rooms');
      print("Fetched ${roomDocs.docs.length} room documents.");
      
      final Set<String> roomNamesSet = <String>{};
      final Map<String, IconData> fetchedIcons = {};
      
      for (final doc in roomDocs.docs) {
        final data = doc.data();
        final roomName = data['roomName'];
        
        if (roomName != null && roomName is String && roomName.trim().isNotEmpty) {
          final cleanRoomName = roomName.trim();
          roomNamesSet.add(cleanRoomName);
          
          final iconCodePoint = data['icon'] as int?;
          fetchedIcons[cleanRoomName] = iconCodePoint != null
              ? _getIconFromCodePoint(iconCodePoint)
              : Icons.home;
        }
      }
      
      final roomNames = roomNamesSet.toList();
      roomNames.sort();
          
      if (mounted) {
        setState(() {
          _roomNames = roomNames;
          roomIcons = fetchedIcons;
          
          if (selectedRoom != null && !roomNames.contains(selectedRoom!.trim())) {
            print("Current selectedRoom '$selectedRoom' not found in fetched rooms, clearing selection");
            selectedRoom = null;
            roomController.text = '';
          }
        });
      }
      print("Fetched and cleaned rooms: $roomNames");
    } catch (e) {
      print("Error fetching rooms for EditDeviceScreen: $e");
      if (mounted) {
        setState(() {
          _roomNames = [];
          roomIcons = {};
        });
      }
    }
  }

  Future<void> _fetchAndFilterRelays() async {
    final userId = DatabaseService().getCurrentUserId();
    if (userId == null) {
      print("User not authenticated. Cannot fetch relay states.");
      setState(() {
        _availableRelays = [];
      });
      return;
    }

    try {
      final relayStatesSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('relay_states')
          .get();

      final occupiedRelays = <String>{};
      for (final doc in relayStatesSnapshot.docs) {
        if (isEditing && selectedRelay != null && doc.id == selectedRelay) {
            continue;
        }
        occupiedRelays.add(doc.id);
      }

      setState(() {
        _availableRelays = _allRelays.where((relay) => !occupiedRelays.contains(relay)).toList();
        if (isEditing && selectedRelay != null && !_availableRelays.contains(selectedRelay)) {
           _availableRelays.add(selectedRelay!);
           _availableRelays.sort();
        }
      });

      print("Fetched and filtered relays. Available: ${_availableRelays.length}");

    } catch (e) {
      print("Error fetching and filtering relay states: $e");
      setState(() {
        _availableRelays = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFE9E7E6),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFFE9E7E6),
      appBar: null,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: Transform.translate(
                      offset: Offset(0.0, 20),
                      child: IconButton(
                        icon: Icon(Icons.arrow_back, size: 50, color: Colors.black),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),

                  Transform.translate(
                    offset: Offset(-50, -30),
                    child: Text(
                      isEditing ? ' Edit device' : ' Add device',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jaldi(
                        textStyle: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                        color: Colors.black,
                      ),
                    ),
                  ),
      
                  SizedBox(height: 5),
                  Transform.translate(
                    offset: Offset(0,-15),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[400],
                      ),
                      child: IconButton(
                        color: Colors.black,
                        iconSize: 60,
                        icon: Icon(selectedIcon),
                        onPressed: () => _pickIcon(),
                      ),
                    ),
                  ),
                  
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 5, top: 10),
                          child: TextFormField(
                            controller: applianceNameController,
                            readOnly: true,
                            enabled: false,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.grey[100],
                              prefixIcon: Icon(Icons.device_hub, size: 30, color: Colors.black),
                              labelText: "Appliance Name",
                              labelStyle: GoogleFonts.jaldi(
                                textStyle: TextStyle(fontSize: 20),
                                color: Colors.black,
                              ),
                              border: OutlineInputBorder(),
                              disabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.black),
                              ),
                              errorText: applianceNameError,
                            ),
                            style: GoogleFonts.jaldi(
                              textStyle: TextStyle(
                                fontSize: 18,
                                color: Colors.black,
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return "Appliance Name is required";
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.edit, size: 30, color: Colors.black),
                        onPressed: _addApplianceDialog,
                      )
                    ],
                  ),

                  _buildRequiredTextField(
                    wattageController,
                    "Wattage",
                    Icons.energy_savings_leaf,
                    keyboardType: TextInputType.number,
                    errorText: wattageError
                  ),
                  SizedBox(height: 10),
                  
                  _buildRoomDropdown(),
                  
                  SizedBox(height: 15),
                  
                  DropdownButtonFormField<String>(
                    key: ValueKey('device_type_dropdown'),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      labelText: 'Device Type',
                      labelStyle: GoogleFonts.jaldi(
                        textStyle: TextStyle(fontSize: 20),
                        color: Colors.black,
                      ),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 17),
                    ),
                    dropdownColor: Colors.grey[200], 
                    style: GoogleFonts.jaldi(
                      textStyle: TextStyle(fontSize: 18, color: Colors.black87),
                    ),
                    value: ['Light', 'Socket'].contains(deviceType) ? deviceType : 'Light',
                    items: ['Light', 'Socket'].map((String type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                    onChanged: (String? value) {
                      setState(() {
                        deviceType = value ?? 'Light';
                      });
                    },
                  ),
                  
                  SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    key: ValueKey('relay_dropdown_${_availableRelays.length}'),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.electrical_services, size: 30, color: Colors.black),
                      labelText: "Relay",
                      errorText: socketError,
                      border: OutlineInputBorder(),
                    ),
                    value: (_availableRelays.contains(selectedRelay)) ? selectedRelay : null,
                    items: _availableRelays.map((String relay) {
                      return DropdownMenuItem<String>(
                        value: relay,
                        child: Text(relay),
                      );
                    }).toList(),
                    onChanged: (String? value) {
                      setState(() {
                        selectedRelay = value;
                        socketError = null;
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return "Relay is required";
                      }
                      return null;
                    },
                  ),

                  SizedBox(height: 10),
                  
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white, 
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: socketError != null ? Colors.red : Colors.black
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: ListTile(
                                leading: Icon(Icons.access_time, color: Colors.black),
                                contentPadding: EdgeInsets.symmetric(horizontal: 25, vertical: 5),
                                title: Text(
                                  startTime != null
                                      ? 'Start: \n${startTime!.format(context)}'
                                      : 'Set Start Time',
                                ),
                                onTap: () => _pickStartTime(),
                              ),
                            ),
                            Expanded(
                              child: ListTile(
                                leading: Icon(Icons.access_time, color: Colors.black),
                                contentPadding: EdgeInsets.symmetric(horizontal: 25, vertical: 5),
                                title: Text(
                                  endTime != null
                                      ? 'End: \n${endTime!.format(context)}'
                                      : 'Set End Time',
                                ),
                                onTap: () => _pickEndTime(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Transform.translate( 
                    offset: Offset(-90, 13),
                    child: Text(
                      ' Automatic alarm set',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        textStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        color: Colors.black,
                      ),
                    ),
                  ),
                  
                  Transform.translate( 
                    offset: Offset(-0, 10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (final preset in presetTimes.keys)
                            ElevatedButton(
                              onPressed: () => _applyPresetTime(preset),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.grey, width: 1),
                              ),
                              child: Text(preset),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Repeating Days',
                              style: TextStyle(
                                fontSize: 16, 
                                fontWeight: FontWeight.bold
                              ),
                            ),
                            if (daysError != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                              ),
                          ],
                        ),
                        SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: weekdays.map((day) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: FilterChip(
                                  label: Text(day),
                                  labelStyle: TextStyle(
                                    color: selectedDays[day] ?? false ? Colors.white : Colors.white,
                                  ),
                                  selected: selectedDays[day] ?? false,
                                  onSelected: (selected) {
                                    setState(() {
                                      selectedDays[day] = selected;
                                      if (selected) {
                                        daysError = null;
                                      }
                                    });
                                  },
                                  backgroundColor: Colors.black,
                                  side: BorderSide(
                                    color: daysError != null ? Colors.red : Colors.grey, 
                                    width: 1
                                  ),
                                  selectedColor: Theme.of(context).colorScheme.secondary,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 10),
                  
                  Row(
                    children: [
                      if (isEditing)
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _deleteDevice,
                            style: ElevatedButton.styleFrom(
                              minimumSize: Size(double.infinity, 60),
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(0),
                                side: BorderSide(color: Colors.black, width: 1),
                              ),
                              elevation: 5,
                              shadowColor: Colors.black.withOpacity(0.5),
                            ),
                            child: Text(
                              'Delete Device',
                              style: GoogleFonts.judson(
                                fontSize: 19,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      SizedBox(width: isEditing ? 10 : 0),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _validateAndSubmitDevice,
                          style: ElevatedButton.styleFrom(
                            minimumSize: Size(double.infinity, 60),
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(0),
                              side: BorderSide(color: Colors.black, width: 1),
                            ),
                            elevation: 5,
                            shadowColor: Colors.black.withOpacity(0.5),
                          ),
                          child: Text(
                            isEditing ? 'Save Changes' : 'Add Device',
                            style: GoogleFonts.judson(
                              fontSize: isEditing ? 19 : 19,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _showRoomSelectionDialog(),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 15, vertical: 17),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: roomError != null ? Colors.red : Colors.grey,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selectedRoom != null ? (roomIcons[selectedRoom] ?? Icons.home) : Icons.home,
                        size: 30,
                        color: Colors.black
                      ),
                      SizedBox(width: 15),
                      Expanded(
                        child: Text(
                          selectedRoom ?? 'Select a room',
                          style: GoogleFonts.jaldi(
                            textStyle: TextStyle(
                              fontSize: 18, 
                              color: selectedRoom != null ? Colors.black87 : Colors.grey
                            ),
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.add, size: 30, color: Colors.black),
              onPressed: _addRoomDialog,
            ),
          ],
        ),
        if (roomError != null)
          Padding(
            padding: EdgeInsets.only(top: 5, left: 15),
            child: Text(
              roomError!,
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  void _showRoomSelectionDialog() {
  final uniqueRoomNames = _roomNames
    .where((name) => name.toString().trim().isNotEmpty)
        .map((name) => name.toString().trim())
        .toSet()
        .toList();
    
    uniqueRoomNames.sort();
    
    if (uniqueRoomNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "No rooms available. Please add a room first.",
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 150,
            left: 10,
            right: 10,
          ),
        )
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFE9E7E6),
          title: Text(
            'Select Room',
            style: GoogleFonts.jaldi(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: uniqueRoomNames.length,
              itemBuilder: (context, index) {
                final roomName = uniqueRoomNames[index];
                final isSelected = selectedRoom == roomName;
                
                return ListTile(
                  leading: Icon(
                    roomIcons[roomName] ?? Icons.home,
                    color: isSelected ? Colors.blue : Colors.black,
                  ),
                  title: Text(
                    roomName,
                    style: GoogleFonts.jaldi(
                      textStyle: TextStyle(
                        fontSize: 18,
                        color: isSelected ? Colors.blue : Colors.black,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  trailing: isSelected ? Icon(Icons.check, color: Colors.blue) : null,
                  onTap: () {
                    setState(() {
                      selectedRoom = roomName;
                      roomController.text = roomName;
                      roomError = null;
                    });
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.black),
                foregroundColor: WidgetStateProperty.all(Colors.white),
              ),
              child: Text(
                'Cancel',
                style: GoogleFonts.jaldi(
                  textStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRequiredTextField(
    TextEditingController controller, 
    String label, 
    IconData icon, 
    {TextInputType keyboardType = TextInputType.text, 
    String? hint,
    String? errorText}
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5, top: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          prefixIcon: Icon(icon, size: 30, color: Colors.black), 
          labelText: label,  
          labelStyle: GoogleFonts.jaldi(
            textStyle: TextStyle(fontSize: 20),
            color: Colors.grey,
          ),
          hintText: hint,
          border: OutlineInputBorder(),
          errorText: errorText,
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return "$label is required";
          }
          return null;
        },
      ),
    );
  }
 
  static IconData roomIconSelected = Icons.home;

  void _addRoomDialog() {
    TextEditingController roomInput = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFE9E7E6),
        titleTextStyle: GoogleFonts.jaldi(
          fontSize: 25,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        title: Text('Add Room'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: roomInput,
                    style: GoogleFonts.inter(
                      textStyle: TextStyle(fontSize: 17),
                      color: Colors.black,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(),
                      hintText: "Room name",
                      hintStyle: GoogleFonts.inter(
                        color: Colors.grey,
                        fontSize: 15,
                      ),
                      prefixIcon: Icon(
                        roomIconSelected,
                        color: Colors.black,
                        size: 24,
                      ),
                    ),
                  ),
                  SizedBox(height: 15),
                  Text(
                    'Select Icon',
                    style: GoogleFonts.jaldi(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 5),
                  Container(
                    height: 200,
                    width: double.maxFinite,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      children: const [
                        Icons.living, Icons.bed, Icons.kitchen, Icons.dining,
                        Icons.bathroom, Icons.meeting_room,Icons.garage, Icons.local_library, Icons.stairs,
                      ].map((icon) {
                        return IconButton(
                          icon: Icon(
                            icon,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              roomIconSelected = icon;
                            });
                          },
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
                  _roomNames.add(roomInput.text);
                  selectedRoom = roomInput.text;
                  roomIcons[roomInput.text] = roomIconSelected;
                  roomController.text = roomInput.text;
                  roomError = null;
                });
              }
              Navigator.pop(context);
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.black),
              foregroundColor: WidgetStateProperty.all(Colors.white),
            ),
            child: Text(
              'Add',
              style: GoogleFonts.jaldi(
                textStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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

    final currentName = applianceNameController.text;
    if (currentName.isNotEmpty) {
      final parts = currentName.split(' - ');
      if (parts.length == 2) {
        modelNameInput.text = parts[1];
        final typeAndBrand = parts[0].split(' ');
        if (typeAndBrand.length >= 2) {
          selectedApplianceType = typeAndBrand[0];
          selectedBrand = typeAndBrand.sublist(1).join(' ');
        }
      }
    }

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
      'Others',
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
              titleTextStyle: GoogleFonts.jaldi(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              title: Text('Edit Smart Appliance'),
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
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: applianceTypeError != null 
                                    ? const Color.fromARGB(255, 131, 24, 16) 
                                    : Colors.grey,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  selectedApplianceType ?? 'Appliance Type',
                                  style: GoogleFonts.jaldi(
                                    textStyle: TextStyle(
                                      fontSize: 16,
                                      color: selectedApplianceType != null 
                                          ? Colors.black87 
                                          : Colors.grey,
                                    ),
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
                            margin: EdgeInsets.only(top: 4),
                            padding: EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
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
                                          style: GoogleFonts.jaldi(
                                            textStyle: TextStyle(fontSize: 16, color: Colors.black87),
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
                                        style: GoogleFonts.jaldi(
                                          textStyle: TextStyle(fontSize: 16, color: Colors.black87),
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
                                            style: GoogleFonts.jaldi(
                                              fontSize: 14,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          Expanded(
                                            child: TextField(
                                              controller: customApplianceInput,
                                              autofocus: true,
                                              style: GoogleFonts.inter(
                                                textStyle: TextStyle(fontSize: 14),
                                                color: Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: "Type appliance type",
                                                hintStyle: GoogleFonts.inter(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                                border: UnderlineInputBorder(),
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
                            padding: EdgeInsets.only(left: 12, top: 5),
                            child: Text(
                              applianceTypeError!,
                              style: TextStyle(color: const Color.fromARGB(255, 136, 27, 19), fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 15),
                    
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
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: brandError != null 
                                    ? const Color.fromARGB(255, 161, 34, 25) 
                                    : Colors.grey,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  selectedBrand ?? 'Brand Name',
                                  style: GoogleFonts.jaldi(
                                    textStyle: TextStyle(
                                      fontSize: 16,
                                      color: selectedBrand != null 
                                          ? Colors.black87 
                                          : Colors.grey,
                                    ),
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
                            margin: EdgeInsets.only(top: 4),
                            padding: EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
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
                                          style: GoogleFonts.jaldi(
                                            textStyle: TextStyle(fontSize: 16, color: Colors.black87),
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
                                        style: GoogleFonts.jaldi(
                                          textStyle: TextStyle(fontSize: 16, color: Colors.black87),
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
                                            style: GoogleFonts.jaldi(
                                              fontSize: 14,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          Expanded(
                                            child: TextField(
                                              controller: customBrandInput,
                                              autofocus: true,
                                              style: GoogleFonts.inter(
                                                textStyle: TextStyle(fontSize: 14),
                                                color: Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: "Type brand name",
                                                hintStyle: GoogleFonts.inter(
                                                  color: Colors.grey,
                                                  fontSize: 12,
                                                ),
                                                border: UnderlineInputBorder(),
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
                            padding: EdgeInsets.only(left: 12, top: 5),
                            child: Text(
                              brandError!,
                              style: TextStyle(color: const Color.fromARGB(255, 136, 32, 24), fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 15),
                    
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: modelNameInput,
                          style: GoogleFonts.inter(
                            textStyle: TextStyle(fontSize: 17),
                            color: Colors.black,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: modelNameError != null ? const Color.fromARGB(255, 153, 35, 27) : Colors.grey,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: modelNameError != null ? const Color.fromARGB(255, 148, 32, 24) : Colors.grey,
                              ),
                            ),
                            labelText: "Model Name",
                            labelStyle: GoogleFonts.jaldi(
                              textStyle: TextStyle(fontSize: 18),
                              color: Colors.grey,
                            ),
                            hintText: "Enter model name",
                            hintStyle: GoogleFonts.inter(
                              color: Colors.grey,
                              fontSize: 15,
                            ),
                          ),
                          onChanged: (value) {
                            if (value.isNotEmpty && modelNameError != null) {
                              setDialogState(() {
                                modelNameError = null;
                              });
                            }
                          },
                        ),
                        if (modelNameError != null)
                          Padding(
                            padding: EdgeInsets.only(left: 12, top: 5),
                            child: Text(
                              modelNameError!,
                              style: TextStyle(color: const Color.fromARGB(255, 136, 29, 22), fontSize: 12),
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
                  ),
                  child: Text(
                    'Update',
                    style: GoogleFonts.jaldi(
                      textStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
      backgroundColor: const Color(0xFFE9E7E6),
      builder: (_) => GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        children: const [
          Icons.light, Icons.tv, Icons.power, Icons.kitchen,
          Icons.speaker, Icons.laptop, Icons.ac_unit, Icons.microwave,Icons.coffee_maker,Icons.radio_button_checked,
          Icons.thermostat,Icons.doorbell,Icons.camera,Icons.sensor_door,Icons.lock,Icons.door_sliding,Icons.local_laundry_service,
          Icons.dining,Icons.rice_bowl,Icons.wind_power,Icons.router,Icons.outdoor_grill,Icons.air,Icons.alarm,
        ].map((icon) {
          return IconButton(
            icon: Icon(icon, color: Colors.black),
            onPressed: () {
              setState(() {
                selectedIcon = icon;
              });
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }

  void _applyPresetTime(String preset) {
    if (presetTimes.containsKey(preset)) {
      setState(() {
        startTime = presetTimes[preset]!['start'];
        endTime = presetTimes[preset]!['end'];
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
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 10,
              right: 10,
            ),
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
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height - 150,
            left: 10,
            right: 10,
          ),
        )
      );
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

    if (roomController.text.isEmpty) {
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

    if (isValid) {
      if (isEditing) {
        _updateDevice();
      } else {
        _submitDevice();
      }
    }
  }

  void _submitDevice() async {
    final DatabaseService dbService = DatabaseService();
    
    final roomName = roomController.text.trim();
    
    final Map<String, dynamic> deviceData = {
      "applianceName": applianceNameController.text.trim(),
      "deviceType": deviceType,
      "wattage": double.tryParse(wattageController.text) ?? 0.0,
      "roomName": roomName,
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

    try {
      await dbService.addAppliance(applianceData: deviceData);
      print("Device successfully added to Firestore.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${deviceData['applianceName']} added successfully!",
              style: const TextStyle(color: Colors.black),
            ),
            backgroundColor: const Color(0xFFE9E7E6),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height -150,
              left: 10,
              right: 10,
            ),
          )
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("Error adding device: $e");
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
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 10,
              right: 10,
            ),
          )
        );
      }
    }
  }

  void _updateDevice() async {
    final DatabaseService dbService = DatabaseService();
    final String applianceId = widget.applianceId;

    final roomName = roomController.text.trim();
    
    final Map<String, dynamic> updatedData = {
      "applianceName": applianceNameController.text.trim(),
      "deviceType": deviceType,
      "wattage": double.tryParse(wattageController.text) ?? 0.0,
      "roomName": roomName,
      "icon": selectedIcon.codePoint,
      "startTime": startTime != null ? "${startTime!.hour.toString().padLeft(2, '0')}:${startTime!.minute.toString().padLeft(2, '0')}" : null,
      "endTime": endTime != null ? "${endTime!.hour.toString().padLeft(2, '0')}:${endTime!.minute.toString().padLeft(2, '0')}" : null,
      "days": selectedDays.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toList(),
      "relay": selectedRelay,
    };

    try {
      await dbService.updateApplianceData(applianceId: applianceId, dataToUpdate: updatedData);
      print("Device $applianceId successfully updated.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${updatedData['applianceName']} updated successfully!",
              style: const TextStyle(color: Colors.black),
            ),
            backgroundColor: const Color(0xFFE9E7E6),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 10,
              right: 10,
            ),
          )
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      print("Error updating device: $e");
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
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 10,
              right: 10,
            ),
          )
        );
      }
    }
  }

  void _deleteDevice() async {
    final DatabaseService dbService = DatabaseService();
    final String applianceId = widget.applianceId;
    
    final String applianceNameToDelete = applianceNameController.text.trim();

    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFE9E7E6),
          title: Text('Confirm Delete'),
          titleTextStyle: GoogleFonts.jaldi(
            fontSize: 23, 
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),   
          content: Text('Are you sure you want to delete "$applianceNameToDelete"?',
            style:GoogleFonts.inter(
              color: Colors.black,
              fontSize: 15,
            ),   
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel',
                style:GoogleFonts.inter(
                  color: Colors.black,
                  fontSize: 15,
                ),   
              ),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: Text('Delete', style: TextStyle(color: Colors.red)),
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
        await dbService.deleteAppliance(applianceId: applianceId);
        print("Device $applianceId successfully deleted.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "$applianceNameToDelete deleted successfully!",
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              margin: EdgeInsets.only(
                bottom: MediaQuery.of(context).size.height - 150,
                left: 10,
                right: 10,
              ),
            )
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        print("Error deleting device: $e");
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
              margin: EdgeInsets.only(
                bottom: MediaQuery.of(context).size.height - 150,
                left: 10,
                right: 10,
              ),
            )
          );
        }
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