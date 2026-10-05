import Foundation
import Combine
import MultipeerConnectivity
import NearbyInteraction
import UIKit

/// Handles the "handshake" step Nearby Interaction itself deliberately
/// leaves up to you: finding the other phone and exchanging `NIDiscoveryToken`
/// data over some transport. This demo uses Multipeer Connectivity (Bluetooth
/// + local Wi-Fi), which is Apple's own recommended path for phone-to-phone
/// discovery — see "Discovering peers with Multipeer Connectivity" in the
/// NearbyInteraction docs.
///
/// This is intentionally a minimal, "invite anyone we see" implementation —
/// fine for a two-phone demo, not what you'd ship (see README for notes on
/// hardening this for production).
final class MultipeerSessionManager: NSObject, ObservableObject {

    /// Must match the base name used in the Info.plist NSBonjourServices
    /// entries ("_nidemo._tcp" / "_nidemo._udp").
    private let serviceType = "nidemo"

    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    @Published private(set) var connectedPeerName: String?

    /// Fired with the peer's decoded token as soon as it arrives.
    var onReceiveToken: ((NIDiscoveryToken) -> Void)?

    /// Asked for our own token once a peer connects, so it can be sent.
    var tokenProvider: (() -> NIDiscoveryToken?)?

    override init() {
        super.init()
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    private func sendMyToken(to peer: MCPeerID) {
        guard let token = tokenProvider?() else { return }
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }
}

// MARK: - MCSessionDelegate

extension MultipeerSessionManager: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectedPeerName = peerID.displayName
                self.sendMyToken(to: peerID)
            case .notConnected:
                if self.connectedPeerName == peerID.displayName {
                    self.connectedPeerName = nil
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else { return }
        DispatchQueue.main.async {
            self.onReceiveToken?(token)
        }
    }

    // Unused for this demo — required by the protocol.
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerSessionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Demo only: auto-accept every invitation.
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerSessionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Demo only: invite the first peer we see. A real app would filter,
        // show a picker, or use a shared "room code" in discoveryInfo.
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    // Losing the peer's advertisement doesn't mean the session dropped — the
    // browser often reports this while the MCSession stays connected, so
    // connection state is driven only by session(_:peer:didChange:).
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
