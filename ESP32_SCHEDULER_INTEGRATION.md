# ESP32 Scheduler Integration (C++)

This document shows a minimal, secure pattern to integrate an ESP32 device with the Firestore-based scheduling system used by this project. The ESP32 will watch `users/{uid}/relay_states/{relayKey}` for state changes and toggle a GPIO pin accordingly.

Important design notes
- Direct credentials (service account keys) must not be embedded in the ESP32 firmware. Instead, use one of these approaches:
  - A short-lived device token obtained from a secure server (recommended). The server authenticates the device and issues a short-lived token the device uses to call a Cloud Function or Firestore REST endpoint.
  - Use the Firebase Realtime Database with rules and the Firebase Embedded C++ client if you prefer. Firestore REST access directly from embedded devices is possible but requires careful auth.
- This example uses the Firestore REST API with an ID token (from Firebase Authentication) or a device token from a secure backend.

What this code does
- Connect to Wi-Fi
- Periodically poll a secure HTTPS endpoint (recommended: Cloud Function that returns the relay state for the device's assigned relay and verifies the device's token)
- Parse the JSON response and toggle a GPIO pin when `state` changes (1 = ON, 0 = OFF)
- If the response contains `irControlled: true`, we still toggle the GPIO but include comments where IR-specific code can run instead.

Hardware assumptions
- Relay module controlled through a GPIO pin (HIGH/LOW) on the ESP32
- Example uses GPIO pin 2 for relay control (change as needed)

Security note
- Use HTTPS and short-lived tokens. Do not embed long-lived secrets in firmware.

---

Example C++ code (ESP32, Arduino core)

```cpp
// ESP32 Scheduler Integration Example
// Purpose: poll a secure endpoint that returns relay state for this device and toggle a GPIO.

#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// Replace these with your Wi-Fi credentials
const char* ssid = "YOUR_SSID";
const char* password = "YOUR_WIFI_PASSWORD";

// Endpoint on your server or Cloud Function that returns JSON like:
// { "relayKey": "light3", "state": 1, "irControlled": false, "wattage": 5 }
const char* endpoint = "https://your-secure-backend.example.com/getRelayState?deviceId=ESP32-001";

// Device auth token (obtain securely from your backend or via Firebase Auth flow)
String deviceToken = "REPLACE_WITH_SHORT_LIVED_TOKEN";

// Relay GPIO pin
const int RELAY_PIN = 2;

// Keep the last state to avoid unnecessary toggles
int lastState = -1;

void setup() {
  Serial.begin(115200);
  delay(1000);

  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW); // default OFF

  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print('.');
  }
  Serial.println("\nWiFi connected");
}

void loop() {
  if (WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(endpoint);
    http.addHeader("Authorization", "Bearer " + deviceToken);
    http.addHeader("Accept", "application/json");

    int httpCode = http.GET();
    if (httpCode == HTTP_CODE_OK) {
      String payload = http.getString();
      Serial.println("Received payload: " + payload);

      StaticJsonDocument<256> doc;
      DeserializationError err = deserializeJson(doc, payload);
      if (!err) {
        int state = doc["state"] | 0;
        bool irControlled = doc["irControlled"] | false;
        int wattage = doc["wattage"] | 0;

        // Print for debugging
        Serial.printf("Parsed state=%d, irControlled=%s, wattage=%d\n", state, irControlled ? "true" : "false", wattage);

        // If the state changed, toggle the GPIO
        if (state != lastState) {
          lastState = state;
          if (irControlled) {
            // If IR is required, run IR-specific routine here instead of toggling GPIO
            // e.g., send IR command via IR LED driver library
            Serial.println("Device is IR-controlled: call IR transmission routine here");
            // sendIRCommand(...);
          } else {
            // Toggle relay GPIO: assume HIGH = ON
            digitalWrite(RELAY_PIN, state == 1 ? HIGH : LOW);
            Serial.printf("Set RELAY_PIN to %s\n", state == 1 ? "HIGH" : "LOW");
          }
        }
      } else {
        Serial.println("Failed to parse JSON");
      }
    } else {
      Serial.printf("HTTP GET failed, code: %d\n", httpCode);
    }
    http.end();
  } else {
    Serial.println("WiFi not connected");
  }

  // Poll every 5 seconds (adjust as needed). Consider long-polling or websockets for lower latency.
  delay(5000);
}
```

Server-side recommendations
- Provide a Cloud Function or simple HTTPS endpoint `/getRelayState` that:
  - Authenticates the device token
  - Fetches the correct `users/{uid}/relay_states/{relayKey}` document
  - Returns the state, irControlled, wattage and optionally a `commandId` or `timestamp`

Firestore rules (example)
- Ensure only authorized systems can edit relay state. For example, restrict writes to a server-managed service account or Cloud Function. Allow devices to read their assigned relay doc only after authentication.

Example security rule fragment (conceptual):
```
// This is conceptual — adapt to your auth model
match /users/{userId}/relay_states/{relayKey} {
  allow read: if request.auth != null && request.auth.uid == userId; // device reads allowed when associated with user
  allow write: if request.auth.token.admin == true || request.auth.uid == "cloud-function-service-account";
}
```

Notes
- Polling Firestore directly from the ESP32 is possible via REST API, but requires using Firebase Authentication tokens and careful handling of refresh.
- A simpler approach is to have the ESP32 poll a secure server endpoint that the backend keeps minimal logic for (recommended). The backend queries Firestore and returns the relay doc.

Troubleshooting
- If relays don't toggle, check the backend logs to confirm it returns correct JSON and that the device token is valid.
- Confirm `relay_states/{relayKey}.state` is 1/0 and `irControlled` is present as boolean.

---

If you want, I can also:
- Add a debug screen inside the Flutter app to send commands to specific relays for immediate testing.
- Provide a sample Cloud Function (Node.js) that returns the relay state for a device (with token verification).

