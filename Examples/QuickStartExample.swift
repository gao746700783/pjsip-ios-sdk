import Foundation
import PJSIPiOS
import UIKit

/// End-to-end Quick Start demonstrating stack startup (with CallKit audio suspension and H.264 tuning),
/// TLS/SRTP account registration, AsyncStream event listening, native UIView video rendering,
/// and automatic camera orientation synchronization.
@MainActor
final class SipQuickStartController {
    private let sip = SipService.shared
    private var callKit: SipCallKitAdapter?
    private var orientationObserver: SipVideoOrientationObserver?
    private var eventTask: Task<Void, Never>?
    private var currentAccountId: String?

    weak var remoteVideoContainer: UIView?
    weak var localPreviewContainer: UIView?

    func startAndRegister() async throws {
        callKit = SipCallKitAdapter(sipService: sip, localizedName: "MyVoIPApp")
        orientationObserver = SipVideoOrientationObserver(sipService: sip)
        orientationObserver?.start()

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in sip.events() {
                await self.handle(event)
            }
        }

        let epConfig = SipEndpointConfiguration(
            userAgent: "MyVoIPApp-iOS/1.0",
            enableVideo: true,
            suspendAudioDeviceOnStart: true,
            preferredVideoCodec: .h264Standard, // H264/97 640x480@15fps, 512kbps, packetization-mode=1
            verifySipServerCert: true,
            enableDnsSrvLookup: false,
            enableSipLogging: true,
            sipLogLevel: .info,
            enableAutoNetworkRecovery: true
        )
        try await sip.start(configuration: epConfig)

        let account = SipAccountConfiguration(
            host: "pbx.example.com",
            port: 5061,
            username: "1001",
            password: "your-sip-password",
            displayName: "Alice",
            transport: .tls,
            srtpMode: .optional,
            srtpSecureSignaling: true,
            enableVideoAutoShow: true,
            enableVideoAutoTransmit: true
        )
        currentAccountId = try await sip.setAccount(account, persistToKeychain: true)
    }

    func placeVideoCall(to destinationURI: String) async throws -> Int32 {
        guard let accountId = currentAccountId else {
            throw SipError.accountNotFound("No registered account")
        }
        try sip.audioSessionManager.configureForCall(isVideo: true)
        let callId = try await sip.makeCall(
            accountId: accountId,
            destinationURI: destinationURI,
            options: SipCallOptions(isVideo: true)
        )
        _ = try await callKit?.startOutgoingCall(
            accountId: accountId,
            callId: callId,
            remoteHandle: destinationURI,
            hasVideo: true
        )
        return callId
    }

    private func handle(_ event: SipEvent) async {
        switch event {
        case .stackStatus(let started):
            SipLogger.shared.info("Demo", "SIP stack started=\(started)")
        case .registration(let accountId, let code, let reason, let isActive):
            SipLogger.shared.info("Demo", "Reg \(accountId): \(code) \(reason) active=\(isActive)")
        case .incomingCall(let info):
            _ = try? await callKit?.reportIncomingCall(
                accountId: info.accountId,
                callId: info.callId,
                remoteHandle: info.remoteURI,
                hasVideo: info.isVideo
            )
        case .videoMediaReady(let views):
            if let remote = views.remoteVideo, let container = remoteVideoContainer {
                remote.frame = container.bounds
                remote.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(remote)
            }
            if let local = views.localPreview, let container = localPreviewContainer {
                local.frame = container.bounds
                local.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(local)
            }
        case .callState(let info):
            if info.state == .disconnected {
                callKit?.reportCallEnded(accountId: info.accountId, callId: info.callId)
            }
        case .callStats(let stats):
            SipLogger.shared.info("Demo", "Stats codec=\(stats.audioCodec) rtt=\(stats.rttMeanMs)ms loss=\(stats.rxPacketLoss)")
        default:
            break
        }
    }
}
