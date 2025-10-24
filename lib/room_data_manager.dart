import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RoomDataManager {
  static final RoomDataManager _instance = RoomDataManager._internal();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  factory RoomDataManager() {
    return _instance;
  }
  
  RoomDataManager._internal();

  // Fetch devices from user-specific Firestore collection
  Future<Map<String, List<Map<String, dynamic>>>> fetchDevices() async {
    final Map<String, List<Map<String, dynamic>>> fetchedRoomDevices = {};

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        print("User not authenticated. Cannot fetch devices.");
        return fetchedRoomDevices;
      }

      // Query from user-specific appliances subcollection
      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .get();
      
      print('Fetched ${querySnapshot.docs.length} devices from Firestore for user $userId');

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final roomName = data['roomName'] as String? ?? 'Unknown Room';
        final deviceType = data['deviceType'] as String? ?? 'Unknown Type';
        final applianceName = data['applianceName'] as String? ?? 'Unknown Device';

        if (!fetchedRoomDevices.containsKey(roomName)) {
          fetchedRoomDevices[roomName] = [];
        }

        // Create a map with all the device data, including the document ID
        final deviceData = {
          'id': doc.id,
          'applianceName': applianceName,
          'roomName': roomName,
          'deviceType': deviceType,
          'relay': data['relay'] as String? ?? '',
          'icon': data['icon'] is int ? data['icon'] as int : 0xe333,
          'wattage': data['wattage'] is num ? (data['wattage'] as num).toDouble() : 0.0,
          'startTime': data['startTime'] as String? ?? '',
          'endTime': data['endTime'] as String? ?? '',
          'days': data['days'] is List ? List<String>.from(data['days'] as List) : <String>[],
          'applianceStatus': data['applianceStatus'] as String? ?? 'OFF',
          'presentHourlyusage': data['presentHourlyusage'] is num ? (data['presentHourlyusage'] as num).toDouble() : 0.0,
        };

        fetchedRoomDevices[roomName]!.add(deviceData);
        print('Added device: ${deviceData['applianceName']} to room: $roomName');
      }
    } catch (e) {
      print('Error fetching devices: $e');
    }

    return fetchedRoomDevices;
  }

  // Fetch devices for a specific room
  Future<List<Map<String, dynamic>>> fetchDevicesForRoom(String roomName) async {
    final List<Map<String, dynamic>> devices = [];

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        print("User not authenticated. Cannot fetch devices.");
        return devices;
      }

      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .where('roomName', isEqualTo: roomName)
          .get();
      
      print('Fetched ${querySnapshot.docs.length} devices for room: $roomName');

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final deviceData = {
          'id': doc.id,
          'applianceName': data['applianceName'] as String? ?? 'Unknown Device',
          'roomName': data['roomName'] as String? ?? roomName,
          'deviceType': data['deviceType'] as String? ?? 'Unknown Type',
          'relay': data['relay'] as String? ?? '',
          'icon': data['icon'] is int ? data['icon'] as int : 0xe333,
          'wattage': data['wattage'] is num ? (data['wattage'] as num).toDouble() : 0.0,
          'startTime': data['startTime'] as String? ?? '',
          'endTime': data['endTime'] as String? ?? '',
          'days': data['days'] is List ? List<String>.from(data['days'] as List) : <String>[],
          'applianceStatus': data['applianceStatus'] as String? ?? 'OFF',
          'presentHourlyusage': data['presentHourlyusage'] is num ? (data['presentHourlyusage'] as num).toDouble() : 0.0,
        };

        devices.add(deviceData);
      }
    } catch (e) {
      print('Error fetching devices for room $roomName: $e');
    }

    return devices;
  }

  // Add a new device to user-specific Firestore
  Future<void> addDevice(Map<String, dynamic> deviceData) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        print("User not authenticated. Cannot add device.");
        return;
      }

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .add(deviceData);
          
      print('Successfully added device: ${deviceData['applianceName']}');
    } catch (e) {
      print('Error adding device: $e');
    }
  }

  // Update an existing device in user-specific Firestore
  Future<void> updateDevice(String deviceId, Map<String, dynamic> updatedData) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        print("User not authenticated. Cannot update device.");
        return;
      }

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .doc(deviceId)
          .update(updatedData);
          
      print('Successfully updated device: $deviceId');
    } catch (e) {
      print('Error updating device: $e');
    }
  }

  // Delete a device from user-specific Firestore
  Future<void> deleteDevice(String deviceId) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        print("User not authenticated. Cannot delete device.");
        return;
      }

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .doc(deviceId)
          .delete();
          
      print('Successfully deleted device: $deviceId');
    } catch (e) {
      print('Error deleting device: $e');
    }
  }

  // Fetch room details by room name
  Future<Map<String, dynamic>?> fetchRoomDetails(String roomName) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        print("User not authenticated. Cannot fetch room details.");
        return null;
      }

      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('Rooms')
          .where('roomName', isEqualTo: roomName)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.data();
      } else {
        return null;
      }
    } catch (e) {
      print('Error fetching room details for $roomName: $e');
      return null;
    }
  }

  // Update room name in both Rooms and appliances collections
  Future<void> updateRoomName(String oldName, String newName) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        print("User not authenticated. Cannot update room name.");
        return;
      }

      // Update appliances with the old room name
      final appliancesSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('appliances')
          .where('roomName', isEqualTo: oldName)
          .get();

      print('Found ${appliancesSnapshot.docs.length} devices to update from room $oldName to $newName');

      // Use a batched write for efficiency
      final batch = _firestore.batch();

      for (final doc in appliancesSnapshot.docs) {
        batch.update(doc.reference, {'roomName': newName});
        print('Updating device ${doc.id} to new room name: $newName');
      }

      // Update the room document
      final roomQuerySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('Rooms')
          .where('roomName', isEqualTo: oldName)
          .get();
          
      for (final roomDoc in roomQuerySnapshot.docs) {
        batch.update(roomDoc.reference, {'roomName': newName});
        print('Updating room document ${roomDoc.id} to new name: $newName');
      }

      // Commit the batched write
      await batch.commit();
      print('Successfully updated room name from $oldName to $newName');

    } catch (e) {
      print('Error updating room name: $e');
    }
  }
  
  // Get stream of devices for a room (for real-time updates)
  Stream<List<Map<String, dynamic>>> getDevicesStreamForRoom(String roomName) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('users')
        .doc(userId)
        .collection('appliances')
        .where('roomName', isEqualTo: roomName)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'applianceName': data['applianceName'] as String? ?? 'Unknown Device',
          'roomName': data['roomName'] as String? ?? roomName,
          'deviceType': data['deviceType'] as String? ?? 'Unknown Type',
          'relay': data['relay'] as String? ?? '',
          'icon': data['icon'] is int ? data['icon'] as int : 0xe333,
          'wattage': data['wattage'] is num ? (data['wattage'] as num).toDouble() : 0.0,
          'startTime': data['startTime'] as String? ?? '',
          'endTime': data['endTime'] as String? ?? '',
          'days': data['days'] is List ? List<String>.from(data['days'] as List) : <String>[],
          'applianceStatus': data['applianceStatus'] as String? ?? 'OFF',
          'presentHourlyusage': data['presentHourlyusage'] is num ? (data['presentHourlyusage'] as num).toDouble() : 0.0,
        };
      }).toList();
    });
  }
}