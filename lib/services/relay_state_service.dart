import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RelayStateService {
  final FirebaseFirestore _firestore;

  RelayStateService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Attempts to set the desired state for an appliance by resolving the
  /// appliance -> relayKey mapping and writing to
  /// users/{uid}/relay_states/{relayKey} in a transaction.
  ///
  /// Returns true when the write succeeds. Throws a descriptive exception on
  /// failure (for example when the appliance has no relayKey mapping).
  Future<bool> setApplianceState({required String userId, required String applianceId, required bool turnOn, String source = 'manual'}) async {
    // Resolve relayKey from the appliance document
    final applianceRef = _firestore.collection('users').doc(userId).collection('appliances').doc(applianceId);
    final applianceSnap = await applianceRef.get();

    if (!applianceSnap.exists) {
      throw Exception('Appliance $applianceId not found for user $userId');
    }

    final applianceData = applianceSnap.data() ?? {};
    final relayKey = (applianceData['relayKey'] ?? applianceData['relay_id'] ?? applianceData['relay'])?.toString();

    if (relayKey == null || relayKey.isEmpty) {
      throw Exception('Relay mapping missing for appliance $applianceId (user $userId)');
    }

    final relayRef = _firestore.collection('users').doc(userId).collection('relay_states').doc(relayKey);

    // Prepare payload
    final payload = <String, dynamic>{
      'state': turnOn ? 1 : 0,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
      'lastUpdatedBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
      'source': source,
      'applianceId': applianceId,
    };

    // Run transactionally to avoid races
    try {
      await _firestore.runTransaction((tx) async {
        final relaySnap = await tx.get(relayRef);
        if (relaySnap.exists) {
          tx.update(relayRef, payload);
        } else {
          tx.set(relayRef, payload);
        }

        // Also write a lightweight log entry for audit
        final logsColl = _firestore.collection('users').doc(userId).collection('relay_logs');
        final logDoc = logsColl.doc();
        tx.set(logDoc, {
          'relayKey': relayKey,
          'applianceId': applianceId,
          'state': payload['state'],
          'source': source,
          'createdAt': FieldValue.serverTimestamp(),
          'performedBy': FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
        });
      });

      return true;
    } catch (e) {
      // Bubble up a clear error
      rethrow;
    }
  }

  /// Convenience method to set by current signed-in user, will throw if no
  /// user is signed in.
  Future<bool> setApplianceStateForCurrentUser({required String applianceId, required bool turnOn, String source = 'manual'}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No authenticated user');
    return setApplianceState(userId: user.uid, applianceId: applianceId, turnOn: turnOn, source: source);
  }

  /// Expose a stream for a specific relayKey so UI or background services can
  /// observe changes to the relay state.
  Stream<DocumentSnapshot> relayStateStream({required String userId, required String relayKey}) {
    return _firestore.collection('users').doc(userId).collection('relay_states').doc(relayKey).snapshots();
  }
}
