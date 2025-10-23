Scheduling helper and quick test instructions

This short README explains the developer helper I added to quickly create sample schedules and how to validate scheduling and relay-state behavior in Firestore.

Helper location
- `lib/debug/create_sample_schedules.dart`

Functions
- `createSamplePerApplianceSchedule({applianceId, relayKey, wattage, startTime, endTime, days})`:
  - Writes a per-appliance document under `users/{uid}/appliances/{applianceId}` with schedule fields (`startTime`,`endTime`,`days`, etc.).

- `createSampleGroupSchedule({scheduleId, name, applianceIds, startTime, endTime, days})`:
  - Writes a group schedule document under `users/{uid}/schedules/{scheduleId}`.

- `clearSampleGroupSchedule({scheduleId})`:
  - Deletes the sample group schedule document.

How to use (quick manual steps)
1. Run the app and sign in with a test user.
2. In Dart debug console (or by adding a temporary debug button/screen), call the helper functions. Example (pseudo):

   await createSamplePerApplianceSchedule(
     applianceId: 'light1',
     relayKey: 'relay2',
     wattage: 60.0,
     startTime: '14:00',
     endTime: '15:00',
     days: ['Mon','Tue','Wed'],
   );

   await createSampleGroupSchedule(
     scheduleId: 'afternoon-group',
     name: 'Afternoon group',
     applianceIds: ['light1','socket2'],
     startTime: '14:00',
     endTime: '15:00',
     days: ['Mon','Tue','Wed'],
   );

3. Observe Firestore paths:
   - `users/{uid}/appliances/{applianceId}` should contain `startTime`, `endTime`, `days`, and `relay`.
   - `users/{uid}/schedules/{scheduleId}` should contain the group schedule document.
   - `users/{uid}/relay_states/{relayKey}` will be updated by the scheduler when it activates/deactivates relays. The scheduler writes `{'state':1}` for ON and `{'state':0}` for OFF.

Relay-state troubleshooting
- The app expects relay documents under `users/{uid}/relay_states/{relayKey}`. If you have legacy top-level `relay_states/{relayKey}`, move them into the user-scoped path or ensure both are kept in sync.
- Each relay doc typically contains these fields:
  - `state` (number): 1 = ON, 0 = OFF
  - `irControlled` (bool) - optional
  - `wattage` (number) - optional
  - `lastUpdated` (timestamp) - optional

Notes
- I updated the scheduling service to persist manual OFF overrides to `users/{uid}/appliances/{applianceId}.manualOffOverrideUntil` as a Firestore Timestamp. The service loads this on startup.
- No UI files were altered (other than initialization hooks already added earlier). If you want a debug button that calls the helper functions from the app UI, tell me and I'll add a temporary debug screen.

Next steps I can do for you
- Add a debug route that calls the helper functions by tapping a button in-app.
- Migrate any legacy top-level `relay_states` documents into the per-user `users/{uid}/relay_states` collection automatically.
- Add overnight-schedule handling for manual-off expiry calculation.

If you want me to migrate existing top-level relay docs into user-specific docs automatically, confirm and I'll implement a safe migration helper that preserves assigned/wattage/state fields.
