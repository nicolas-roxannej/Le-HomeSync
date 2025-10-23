class RelayState {
  // Relay states for 5 relays: 1, 3, 4, 7, 8 (NO relay8 as master power)
  static Map<String, int> relayStates = {
    'relay1': 0, // Light with LDR
    'relay3': 0, // Socket with IR
    'relay4': 0, // Socket with IR
    'relay7': 0, // Light with LDR
    'relay8': 0, // Light with LDR
  };

  // Track if relay is controlled by IR sensor
  static Map<String, bool> irControlledStates = {
    'relay1': false,
    'relay3': false,
    'relay4': false,
    'relay7': false,
    'relay8': false,
  };

  // Track if relay is controlled by LDR sensor (wall switch)
  static Map<String, bool> ldrControlledStates = {
    'relay1': false,
    'relay3': false,
    'relay4': false,
    'relay7': false,
    'relay8': false,
  };

  // Master power state (APP ONLY - not in hardware/Firebase)
  static bool masterPowerOn = true;

  static void reset() {
    relayStates = {
      'relay1': 0,
      'relay3': 0,
      'relay4': 0,
      'relay7': 0,
      'relay8': 0,
    };

    irControlledStates = {
      'relay1': false,
      'relay3': false,
      'relay4': false,
      'relay7': false,
      'relay8': false,
    };

    ldrControlledStates = {
      'relay1': false,
      'relay3': false,
      'relay4': false,
      'relay7': false,
      'relay8': false,
    };

    masterPowerOn = true;
  }
}
