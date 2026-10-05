import Foundation
import NearbyInteraction
import Combine

/// Wraps a single `NISession` and publishes the connected peer's live
/// distance and direction so SwiftUI can bind to it directly.
///
/// This class does NOT do peer discovery itself — see `MultipeerSessionManager`,
/// which is responsible for finding the other phone and exchanging the
/// `NIDiscoveryToken` values both sides need before a session can `run(_:)`.
final class NearbyInteractionManager: NSObject, ObservableObject {

    /// Distance to the peer, in meters. `nil` when the peer is out of UWB range.
    @Published private(set) var distance: Float?

    /// Unit vector pointing at the peer, in the device's own coordinate space.
    /// `nil` when the peer is in range but outside the narrow "line of sight"
    /// cone (see Apple's guidance: devices should be within ~9m, facing each
    /// other, held in portrait with their back cameras pointed at one another).
    @Published private(set) var direction: SIMD3<Float>?

    @Published private(set) var statusText = "Starting session…"

    private var session: NISession?
    private var lastConfiguration: NINearbyPeerConfiguration?

    /// Our own token — hand this to `MultipeerSessionManager` so it can be
    /// serialized and sent to the peer as soon as a connection is made.
    var discoveryToken: NIDiscoveryToken? {
        session?.discoveryToken
    }

    override init() {
        super.init()
        startSession()
    }

    private func startSession() {
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            statusText = "This device has no U1/U2 chip — Nearby Interaction isn't supported here."
            return
        }
        session = NISession()
        session?.delegate = self
        statusText = "Waiting for a peer…"
    }

    /// Call this once the peer's token has arrived over Multipeer Connectivity.
    func run(peerToken: NIDiscoveryToken) {
        let config = NINearbyPeerConfiguration(peerToken: peerToken)
        lastConfiguration = config
        session?.run(config)
        statusText = "Ranging…"
    }

    func invalidate() {
        session?.invalidate()
        session = nil
    }
}

extension NearbyInteractionManager: NISessionDelegate {

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peer = nearbyObjects.first else { return }
        distance = peer.distance
        direction = peer.direction

        if peer.direction == nil, peer.distance != nil {
            statusText = "Distance only — out of line of sight. Point the back cameras at each other to get direction."
        } else if peer.direction != nil {
            statusText = "Tracking peer"
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        distance = nil
        direction = nil
        switch reason {
        case .timeout:
            statusText = "Peer lost (timeout) — move closer or back into view."
        case .peerEnded:
            statusText = "Peer ended the session."
        @unknown default:
            statusText = "Peer disconnected."
        }
    }

    func sessionWasSuspended(_ session: NISession) {
        statusText = "Session suspended (app moved to background)."
    }

    func sessionSuspensionEnded(_ session: NISession) {
        // Resume ranging with the configuration we last used.
        if let config = lastConfiguration {
            session.run(config)
            statusText = "Ranging…"
        }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        statusText = "Session ended: \(error.localizedDescription)"
    }
}
