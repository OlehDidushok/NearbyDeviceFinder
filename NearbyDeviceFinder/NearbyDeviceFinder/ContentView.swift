import SwiftUI
import NearbyInteraction

struct ContentView: View {
    @StateObject private var multipeer = MultipeerSessionManager()
    @StateObject private var nearbyInteraction = NearbyInteractionManager()
    @StateObject private var bluetooth = BluetoothRSSIManager()

    var body: some View {
        TabView {
            uwbTab
                .tabItem { Label("UWB Precision", systemImage: "location.viewfinder") }

            bluetoothTab
                .tabItem { Label("Bluetooth RSSI", systemImage: "dot.radiowaves.left.and.right") }
        }
        .onAppear {
            // Wire the two managers together: MultipeerSessionManager doesn't
            // know about NearbyInteraction, and vice versa — this closure
            // pairing is the entire "glue" between discovery and ranging.
            multipeer.tokenProvider = { nearbyInteraction.discoveryToken }
            multipeer.onReceiveToken = { token in nearbyInteraction.run(peerToken: token) }
            multipeer.start()
        }
    }

    // MARK: - UWB tab

    private var uwbTab: some View {
        VStack(spacing: 24) {
            Text("Nearby Interaction (UWB)")
                .font(.title2.bold())
                .padding(.top)

            Text(multipeer.connectedPeerName.map { "Connected to \($0)" }
                 ?? "Looking for the other demo phone…")
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 2)
                    .frame(width: 160, height: 160)

                if let direction = nearbyInteraction.direction {
                    // Simplified 2D bearing from the 3D direction vector —
                    // good enough for a flat on-screen arrow demo.
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                        .rotationEffect(.radians(Double(atan2(direction.x, direction.z))))
                        .animation(.easeOut(duration: 0.2), value: direction)
                } else {
                    Image(systemName: "location.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                }
            }

            Group {
                if let distance = nearbyInteraction.distance {
                    Text(String(format: "%.2f m", distance))
                } else {
                    Text("—")
                }
            }
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundStyle(nearbyInteraction.distance == nil ? .tertiary : .primary)

            Text(nearbyInteraction.statusText)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
    }

    // MARK: - Bluetooth RSSI tab

    private var bluetoothTab: some View {
        VStack {
            Text("Bluetooth RSSI Scan")
                .font(.title2.bold())
                .padding(.top)

            Text("Coarse, noisy, no direction — compare this against the UWB tab.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            List(bluetooth.peripherals.sorted(by: { $0.rssi > $1.rssi })) { peripheral in
                HStack {
                    VStack(alignment: .leading) {
                        Text(peripheral.name)
                        Text("~\(String(format: "%.1f", peripheral.estimatedMeters)) m (est.)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(peripheral.rssi) dBm")
                        .font(.system(.body, design: .monospaced))
                }
            }
            .listStyle(.plain)

            Text(bluetooth.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(bluetooth.isScanning ? "Stop Scan" : "Start Scan") {
                bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
