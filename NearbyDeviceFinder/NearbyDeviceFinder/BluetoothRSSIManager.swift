import Foundation
import CoreBluetooth
import Combine

/// The "old school" way of estimating proximity: scan for BLE advertisements
/// and use signal strength (RSSI) as a crude, noisy stand-in for distance.
///
/// This exists purely as a teaching contrast against the UWB tab — no
/// direction, and the distance estimate below can easily be off by 2-3x
/// depending on antenna orientation, obstacles, and the specific radio.
final class BluetoothRSSIManager: NSObject, ObservableObject {

    struct DiscoveredPeripheral: Identifiable {
        let id: UUID
        var name: String
        var rssi: Int
        var estimatedMeters: Double
    }

    @Published private(set) var peripherals: [DiscoveredPeripheral] = []
    @Published private(set) var isScanning = false
    @Published private(set) var statusText = "Bluetooth idle"

    private var centralManager: CBCentralManager!

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            statusText = "Bluetooth isn't powered on."
            return
        }
        peripherals.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        statusText = "Scanning…"
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        statusText = "Stopped"
    }

    /// Classic log-distance path-loss model:
    ///   distance = 10 ^ ((measuredPower - RSSI) / (10 * pathLossExponent))
    /// `measuredPower` is the RSSI you'd expect at 1 meter for a typical BLE
    /// radio (device-specific in reality); `pathLossExponent` models how fast
    /// signal decays in the environment (2.0 = free space, higher indoors).
    /// This is illustrative only — do not treat it as accurate.
    private func estimateDistance(rssi: Int, measuredPower: Int = -59, pathLossExponent: Double = 2.0) -> Double {
        guard rssi != 0 else { return -1 }
        let ratio = Double(measuredPower - rssi) / (10 * pathLossExponent)
        return pow(10, ratio)
    }
}

extension BluetoothRSSIManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusText = "Bluetooth ready"
        case .unauthorized:
            statusText = "Bluetooth permission denied — enable it in Settings."
        default:
            isScanning = false
            statusText = "Bluetooth unavailable"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unnamed device"
        let estimated = estimateDistance(rssi: RSSI.intValue)

        DispatchQueue.main.async {
            if let index = self.peripherals.firstIndex(where: { $0.id == peripheral.identifier }) {
                self.peripherals[index].rssi = RSSI.intValue
                self.peripherals[index].estimatedMeters = estimated
                self.peripherals[index].name = name
            } else {
                self.peripherals.append(
                    DiscoveredPeripheral(id: peripheral.identifier, name: name, rssi: RSSI.intValue, estimatedMeters: estimated)
                )
            }
        }
    }
}
