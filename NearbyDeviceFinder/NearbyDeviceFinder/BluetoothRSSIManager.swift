import Foundation
import CoreBluetooth
import Combine
import UIKit

/// The "old school" way of estimating proximity: scan for BLE advertisements
/// and use signal strength (RSSI) as a crude, noisy stand-in for distance.
///
/// This exists purely as a teaching contrast against the UWB tab — no
/// direction, and the distance estimate below can easily be off by 2-3x
/// depending on antenna orientation, obstacles, and the specific radio.
///
/// Each phone also advertises a service UUID of its own, so the scan can pick
/// the other demo phone out of the crowd of unrelated BLE devices nearby.
final class BluetoothRSSIManager: NSObject, ObservableObject {

    /// Rough buckets, in the spirit of iBeacon's immediate/near/far — RSSI
    /// can't honestly support anything finer.
    enum Proximity: String {
        case veryClose = "Very close"
        case near = "Near"
        case far = "Far"
    }

    struct DiscoveredPeripheral: Identifiable {
        let id: UUID
        var name: String
        /// True when the peripheral advertises this app's demo service.
        var isDemoPhone: Bool
        /// Latest raw reading — deliberately left jumpy.
        var rssi: Int
        /// Moving average of `rssi`; this is what the estimate is based on.
        var smoothedRSSI: Double
        var estimatedMeters: Double
        var lastSeen: Date

        var proximity: Proximity {
            switch estimatedMeters {
            case ..<0.5: return .veryClose
            case ..<3: return .near
            default: return .far
            }
        }
    }

    @Published private(set) var peripherals: [DiscoveredPeripheral] = []
    @Published private(set) var isScanning = false
    @Published private(set) var statusText = "Bluetooth idle"

    /// Off: list only phones running this app. On: every BLE advertiser in range.
    @Published var showAllDevices = false {
        didSet {
            guard showAllDevices != oldValue, isScanning else { return }
            startScan()
        }
    }

    /// Demo phones first, then strongest signal. RSSI is compared in 5 dB
    /// steps so rows don't swap places on every packet.
    var sortedPeripherals: [DiscoveredPeripheral] {
        peripherals.sorted { a, b in
            if a.isDemoPhone != b.isDemoPhone { return a.isDemoPhone }
            let stepA = (a.smoothedRSSI / 5).rounded()
            let stepB = (b.smoothedRSSI / 5).rounded()
            if stepA != stepB { return stepA > stepB }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// Arbitrary UUID that identifies this demo; every phone running the app
    /// advertises it and (by default) scans only for it.
    private static let demoServiceUUID = CBUUID(string: "7C1E3B52-9A64-4F0E-8D2B-5A1C6E9F0D31")

    /// Weight of each new reading in the moving average (lower = smoother).
    private static let smoothingFactor = 0.2

    /// Rows not heard from for this long are dropped from the list.
    private static let staleInterval: TimeInterval = 10

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var pruneTimer: AnyCancellable?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            statusText = "Bluetooth isn't powered on."
            return
        }
        peripherals.removeAll()
        centralManager.scanForPeripherals(
            withServices: showAllDevices ? nil : [Self.demoServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        statusText = showAllDevices ? "Scanning for all devices…" : "Scanning for the other demo phone…"
        pruneTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.pruneStalePeripherals() }
    }

    func stopScan() {
        centralManager.stopScan()
        pruneTimer = nil
        isScanning = false
        statusText = "Stopped"
    }

    private func record(id: UUID, name: String?, isDemoPhone: Bool, rssi: Int) {
        guard isScanning else { return }
        // A filtered scan only ever returns phones advertising the demo service.
        let isDemoPhone = isDemoPhone || !showAllDevices
        if let index = peripherals.firstIndex(where: { $0.id == id }) {
            var peripheral = peripherals[index]
            peripheral.rssi = rssi
            peripheral.smoothedRSSI += Self.smoothingFactor * (Double(rssi) - peripheral.smoothedRSSI)
            peripheral.estimatedMeters = estimateDistance(rssi: peripheral.smoothedRSSI)
            peripheral.lastSeen = Date()
            // Not every packet carries the name or the service list, so only
            // ever upgrade these — never fall back to "Unnamed device".
            if let name { peripheral.name = name }
            if isDemoPhone { peripheral.isDemoPhone = true }
            peripherals[index] = peripheral
        } else {
            peripherals.append(
                DiscoveredPeripheral(
                    id: id,
                    name: name ?? "Unnamed device",
                    isDemoPhone: isDemoPhone,
                    rssi: rssi,
                    smoothedRSSI: Double(rssi),
                    estimatedMeters: estimateDistance(rssi: Double(rssi)),
                    lastSeen: Date()
                )
            )
        }
    }

    private func pruneStalePeripherals() {
        let cutoff = Date().addingTimeInterval(-Self.staleInterval)
        guard peripherals.contains(where: { $0.lastSeen < cutoff }) else { return }
        peripherals.removeAll { $0.lastSeen < cutoff }
    }

    /// Classic log-distance path-loss model:
    ///   distance = 10 ^ ((measuredPower - RSSI) / (10 * pathLossExponent))
    /// `measuredPower` is the RSSI you'd expect at 1 meter for a typical BLE
    /// radio (device-specific in reality); `pathLossExponent` models how fast
    /// signal decays in the environment (2.0 = free space, higher indoors).
    /// This is illustrative only — do not treat it as accurate.
    private func estimateDistance(rssi: Double, measuredPower: Double = -59, pathLossExponent: Double = 2.0) -> Double {
        let ratio = (measuredPower - rssi) / (10 * pathLossExponent)
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
            pruneTimer = nil
            isScanning = false
            statusText = "Bluetooth unavailable"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let rssi = RSSI.intValue
        // CoreBluetooth reports 127 when it has no reading; real values are negative.
        guard rssi < 0 else { return }

        let id = peripheral.identifier
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let isDemoPhone = services.contains(Self.demoServiceUUID)

        DispatchQueue.main.async {
            self.record(id: id, name: name, isDemoPhone: isDemoPhone, rssi: rssi)
        }
    }
}

extension BluetoothRSSIManager: CBPeripheralManagerDelegate {

    /// Advertise for as long as the app is open, so the other phone can find
    /// this one whether or not this phone is scanning.
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn, !peripheral.isAdvertising else { return }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.demoServiceUUID],
            CBAdvertisementDataLocalNameKey: UIDevice.current.name
        ])
    }
}
