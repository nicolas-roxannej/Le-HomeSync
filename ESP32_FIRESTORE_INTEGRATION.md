ESP32 Firestore integration guide

This document explains how the ESP32 firmware should observe Firestore and act on relay commands.

Expected Firestore structure (per-user):

- users/{uid}/relay_states/{relayKey}
  - state: integer (1 = ON, 0 = OFF)
  - lastUpdated: timestamp
  - irControlled: boolean (optional)
  - wattage: double (optional)

Notes for firmware:
- The ESP32 should authenticate as a service or per-device Firebase user with restricted permissions to only read its assigned relay documents.
- The firmware should subscribe (listen) to the document path `users/{uid}/relay_states/{relayKey}` and apply the `state` change immediately.
- For active-LOW relay wiring: state=1 -> apply LOW signal to GPIO; state=0 -> apply HIGH signal.
- Honor `irControlled` flag: when true, device should not override manual hardware control unless explicitly commanded.

Recommended pseudo-flow (Arduino C++):

- Authenticate to Firebase and obtain a listener for the document.
- On document change, parse `fields/state/integerValue` (or value if using Realtime DB) and write the GPIO pin.
- If the document does not exist, create it with `state:0` and metadata via the mobile app.

Example mapping (app <-> firmware):
- App writes:
  users/{uid}/relay_states/relay1.set({state: 1, lastUpdated: serverTimestamp(), irControlled: false})
- Firmware receives and sets the GPIO pin accordingly.

Security guidance:
- Use Firestore rules to only allow users to write to their own `users/{uid}/relay_states` and restrict device keys to read-only where appropriate.
- Prefer fine-grained service accounts or Cloud Functions for critical commands.

See the repository's `ESP32_SCHEDULER_INTEGRATION.md` for a full example sketch and rules snippet.
