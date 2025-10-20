import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:homesync/databaseservice.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Function to check if a year is a leap year
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
                    offset: Offset(-40, -30),
                    child: Text(
                      isEditing ? ' Edit appliance' : ' Add appliance',
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

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.only(bottom: 5, top: 10),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 17),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: applianceNameError != null ? const Color.fromARGB(255, 179, 36, 26) : Colors.black,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.device_hub, size: 30, color: Colors.black),
                                    SizedBox(width: 15),
                                    Expanded(
                                      child: Text(
                                        applianceNameController.text.isEmpty 
                                          ? "Appliance Name" 
                                          : applianceNameController.text,
                                        style: GoogleFonts.jaldi(
                                          textStyle: TextStyle(
                                            fontSize: 18,
                                            color: applianceNameController.text.isEmpty 
                                              ? Colors.grey 
                                              : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.add, size: 30, color: Colors.black),
                            onPressed: _addApplianceDialog,
                          )
                        ],
                      ),
                      if (applianceNameError != null)
                        Padding(
                          padding: EdgeInsets.only(left: 15, top: 2),
                          child: Text(
                            applianceNameError!,
                            style: TextStyle(color: const Color.fromARGB(255, 172, 36, 26), fontSize: 12),
                          ),
                        ),
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

                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white,
                                prefixIcon: Icon(
                                  selectedRoom != null ? (roomIcons[selectedRoom] ?? Icons.home) : Icons.home,
                                  size: 30,
                                  color: Colors.black
                                ),
                                labelText: 'Room',
                                labelStyle: GoogleFonts.jaldi(
                                  textStyle: TextStyle(fontSize: 20),
                                  color: Colors.black,
                                ),
                                border: OutlineInputBorder(),
                                errorText: roomError,
                              ),
                              dropdownColor: Colors.grey[200],
                              style: GoogleFonts.jaldi(
                                textStyle: TextStyle(fontSize: 18, color: Colors.black87),
                              ),
                              value: selectedRoom,
                              items: rooms.isEmpty
                                ? [DropdownMenuItem(value: 'No Rooms', child: Text('No Rooms Available'))]
                                : rooms.map((room) {
                                    return DropdownMenuItem(
                                      value: room,
                                      child: Text(room),
                                    );
                                  }).toList(),
                              onChanged: (value) {
                                if (value == 'No Rooms') return;
                                setState(() {
                                  selectedRoom = value;
                                  roomError = null;
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty || value == 'No Rooms') {
                                  return "Room is required";
                                }
                                return null;
                              },
                            ),
                      ),
                      IconButton(
                        icon: Icon(Icons.add, size: 30, color: Colors.black),
                        onPressed: _addRoomDialog,
                      )
                    ],
                  ),

                  SizedBox(height: 15),

                  DropdownButtonFormField<String>(
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
                    value: deviceType,
                    items: ['Light', 'Socket'].map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        deviceType = value!;

                        if (deviceType == 'Light') {
                          socketError = null;
                        }
                      });
                    },
                  ),

                  SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Icon(Icons.electrical_services, size: 30, color: Colors.black),
                      labelText: "Relay",
                      errorText: socketError,
                      border: OutlineInputBorder(),
                    ),
                    value: selectedRelay,
                    items: _availableRelays.map((relay) {
                      return DropdownMenuItem(
                        value: relay,
                        child: Text(relay),
                      );
                    }).toList(),
                    onChanged: (value) {
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
                        color: timeError != null ? Colors.red : Colors.black
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
                        if (timeError != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 12, bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                timeError!,
                                style: TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ),
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
                                fontSize: 20,
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
                              fontSize: isEditing ? 20 : 24,
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
              titleTextStyle: GoogleFonts.jaldi(
                fontSize: 25,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              title: Text('Add Smart Appliance'),
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
                                                hintText: "Type Appliance",
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
                              textStyle: TextStyle(fontSize: 16,),
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
                    'Add',
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
            backgroundColor: const Color(0xFFE9E7E6),
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
            backgroundColor: const Color(0xFFE9E7E6),
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
          title: Text('Confirm Delete'),
          content: Text('Are you sure you want to delete "$applianceNameToDelete"? This will erase all associated usage data.'),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
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
              backgroundColor: Colors.red,
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