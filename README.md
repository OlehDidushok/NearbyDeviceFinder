# NearbyDeviceFinder — demo app

A small two-tab SwiftUI app built for a tech talk on iOS device-discovery and
proximity APIs. It's meant to be read alongside the talk, not shipped.

- **UWB Precision tab** — uses `NearbyInteraction` (Ultra Wideband) to show
  live distance + direction to a second phone running the same app.
- **Bluetooth RSSI tab** — scans nearby BLE advertisers and shows raw signal
  strength plus a rough, illustrative distance estimate, for contrast.

Peer discovery and the handshake that hands Nearby Interaction its
`NIDiscoveryToken` are done with `MultipeerConnectivity` (Apple's own
recommended path — see "Discovering peers with Multipeer Connectivity" in
the NearbyInteraction docs).

## Requirements

- A Mac with Xcode 27 or later (the project targets iOS 27).
- **Two physical iPhones with a U1 or U2 chip** for the live UWB demo — the
  Simulator cannot do Nearby Interaction ranging at all. iPhone 12 Pro (U1)
  works fine; you said you have two of these, so you're set. Both phones
  need to be on the same Wi-Fi network (or have Bluetooth on) for Multipeer
  Connectivity to find each other, and both need Bluetooth + Local Network
  permission granted.
- An Apple ID / development team to code-sign onto a real device (free
  personal team is enough for a demo build).

## Build & run

```bash
open NearbyDeviceFinder/NearbyDeviceFinder.xcodeproj
```

The permission strings and Bonjour service types live in
`NearbyDeviceFinder/Info.plist`, which Xcode merges into the generated
Info.plist at build time.

In Xcode:
1. Select the `NearbyDeviceFinder` target → Signing & Capabilities → set
   your Team.
2. Plug in both iPhones, select one as the run destination, Cmd+R. Repeat
   for the second phone (or use Xcode's "run on multiple devices").
3. On first launch each phone will prompt for **Local Network**,
   **Nearby Interactions**, and **Bluetooth** permission — accept all three
   on both phones, or the demo won't connect.

## Demo script (suggested)

1. **Bluetooth RSSI tab first.** Start a scan on one phone. Point out the
   dBm numbers jumping around and the "estimated meters" column drifting
   even when the phone isn't moving — this is the "old way," and it has no
   sense of direction at all.
2. **Switch to the UWB tab** on both phones. Within a few seconds they
   should find each other over Multipeer Connectivity and Nearby
   Interaction will start ranging — point out the arrow and the distance
   number updating live as you walk around.
3. Turn one phone 90° or put an obstacle between them — show the arrow
   disappear ("out of line of sight") while distance is still reported,
   then reappear once you face the back cameras at each other again. This
   is the "narrow cone" constraint worth calling out explicitly.
4. Compare: UWB gives centimeter-ish accuracy *and* a bearing; BLE RSSI
   gives a noisy number and nothing else. That contrast is the whole point
   of the talk.

## Code map

| File | Responsibility |
|---|---|
| `NearbyInteractionManager.swift` | Owns the `NISession`, publishes `distance`/`direction`, implements `NISessionDelegate`. |
| `MultipeerSessionManager.swift` | Finds the other phone (MCNearbyServiceAdvertiser/Browser) and ships the `NIDiscoveryToken` back and forth once connected. |
| `BluetoothRSSIManager.swift` | `CBCentralManager` scan + a simple log-distance RSSI→meters estimate, for the comparison tab. |
| `ContentView.swift` | Wires the three managers together and renders both tabs. |

## Known simplifications (worth saying out loud in the talk)

- The Multipeer discovery policy auto-invites the first peer it sees — fine
  for a two-phone demo, not something you'd ship as-is (a real app would
  filter by a room code, show a picker, or require explicit pairing).
- The on-screen arrow uses a simplified 2D bearing (`atan2(x, z)`) from the
  3D direction vector — good enough for a flat UI arrow, not a full 3D
  compass.
- The RSSI→distance formula (`10 ^ ((measuredPower - RSSI) / (10 × n))`) is
  the standard log-distance path-loss model, but `measuredPower` and the
  path-loss exponent are guesses here — real RSSI distance estimation needs
  per-device calibration and is still only approximate. That imprecision is
  itself the teaching point against UWB's approach (time-of-flight instead
  of signal-strength guessing).
- Background ranging, Camera Assistance (iOS 16+, widens the "line of
  sight" cone using ARKit), and third-party UWB accessories are all real
  NearbyInteraction features not implemented here — flagged in the deck as
  "where to go next" rather than built into the demo, to keep the two-phone
  build simple and reliable.

## Sources

Built against Apple's current NearbyInteraction documentation
(developer.apple.com/documentation/nearbyinteraction), specifically
"Initiating and maintaining a session" and "Discovering peers with
Multipeer Connectivity."
