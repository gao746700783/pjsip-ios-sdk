import Foundation
import PJSUA2Bridge
import UIKit

/// High-level, thread-safe SIP service facade for iOS, inspired by VoiSmart/pjsip-android's
/// `SipService` + `SipServiceCommand` architecture and backed by `swift-pjsip` (PJSUA2).
///
/// All PJSUA2 calls are automatically dispatched onto a dedicated PJLIB-registered worker thread
/// so the UI/main thread is never blocked. Events are delivered via both `AsyncStream<SipEvent>`
/// (`events()`) and `SipEventDelegate`.
public final class SipService: NSObject, @unchecked Sendable {
    public static let shared = SipService()

    public weak var delegate: SipEventDelegate?
    public let delegateQueue: DispatchQueue
    public let accountStore: SipAccountKeychainStore
    public let audioSessionManager: SipAudioSessionManager

    private let engine = PJBridgeEngine()
    private let worker = SipWorkerThread(name: "com.pjsipios.pjsua2-worker")
    private let broadcaster = SipEventBroadcaster()
    private let networkMonitor = SipNetworkMonitor()
    private let logger: SipLogger

    private let stateLock = NSLock()
    private var _configuration: SipEndpointConfiguration = .init()
    private var _configuredAccounts: [String: SipAccountConfiguration] = [:]

    public var isStarted: Bool {
        engine.isStarted
    }

    public var configuration: SipEndpointConfiguration {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _configuration
    }

    public init(
        delegateQueue: DispatchQueue = .main,
        accountStore: SipAccountKeychainStore = SipAccountKeychainStore(),
        audioSessionManager: SipAudioSessionManager = SipAudioSessionManager(),
        logger: SipLogger = .shared
    ) {
        self.delegateQueue = delegateQueue
        self.accountStore = accountStore
        self.audioSessionManager = audioSessionManager
        self.logger = logger
        super.init()
        self.engine.delegate = self
    }

    deinit {
        networkMonitor.stop()
        worker.stop()
    }

    /// Creates a new `AsyncStream<SipEvent>` subscription for Swift Concurrency / SwiftUI consumers.
    public func events() -> AsyncStream<SipEvent> {
        broadcaster.makeStream()
    }

    // MARK: - Stack Lifecycle

    /// Starts the PJSUA2 stack on the dedicated worker thread and optionally restores
    /// persisted Keychain accounts.
    public func start(
        configuration: SipEndpointConfiguration = .init(),
        restorePersistedAccounts: Bool = false
    ) async throws {
        stateLock.lock()
        _configuration = configuration
        stateLock.unlock()

        try await runOnWorker { [engine] in
            try engine.start(with: configuration.toBridgeConfig())
        }

        if configuration.enableAutoNetworkRecovery {
            startNetworkMonitoring()
        }

        if restorePersistedAccounts {
            let stored = try accountStore.loadAll()
            for account in stored {
                try await setAccount(account, persistToKeychain: false)
            }
        }
    }

    /// Stops the PJSUA2 stack, hangs up all active calls, and releases transports.
    public func stop() async throws {
        networkMonitor.stop()
        try await runOnWorker { [engine] in
            try engine.stop()
        }
    }

    /// Re-initializes transports and updates SIP contact/media after an IP change.
    public func handleIPChange() async throws {
        try await runOnWorker { [engine] in
            try engine.handleIPChange()
        }
    }

    // MARK: - Account Management (mirrors SipServiceCommand account APIs)

    /// Adds or updates a SIP account and triggers registration.
    @discardableResult
    public func setAccount(
        _ account: SipAccountConfiguration,
        persistToKeychain: Bool = true
    ) async throws -> String {
        try account.validate()

        if persistToKeychain {
            try accountStore.save(account)
        }

        stateLock.lock()
        _configuredAccounts[account.idURI] = account
        stateLock.unlock()

        let bridgeConfig = account.toBridgeConfig()
        try await runOnWorker { [engine] in
            try engine.addOrUpdateAccount(bridgeConfig)
        }
        return account.idURI
    }

    /// Removes an account from the stack and optionally deletes its Keychain credentials.
    public func removeAccount(
        accountId: String,
        deleteFromKeychain: Bool = true
    ) async throws {
        stateLock.lock()
        _configuredAccounts.removeValue(forKey: accountId)
        stateLock.unlock()

        if deleteFromKeychain {
            try accountStore.delete(accountIdURI: accountId)
        }

        try await runOnWorker { [engine] in
            try engine.removeAccount(accountId)
        }
    }

    /// Re-registers (`renew: true`) or unregisters (`renew: false`) an existing account.
    public func setRegistration(accountId: String, renew: Bool) async throws {
        try await runOnWorker { [engine] in
            try engine.setRegistration(renew, forAccount: accountId)
        }
    }

    /// Returns all currently configured accounts in memory.
    public func activeAccounts() -> [SipAccountConfiguration] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Array(_configuredAccounts.values)
    }

    // MARK: - Call Initiation (mirrors makeCall / makeDirectCall)

    /// Places an outgoing audio or video call from a registered account.
    @discardableResult
    public func makeCall(
        accountId: String,
        destinationURI: String,
        options: SipCallOptions = .init()
    ) async throws -> Int32 {
        try await runOnWorker { [engine] in
            var error: NSError?
            let callId = engine.makeCall(
                fromAccount: accountId,
                destination: destinationURI,
                isVideo: options.isVideo,
                isVideoMuteInit: options.isVideoMutedInitially,
                isSilentCall: options.isSilentCall,
                customHeaders: options.customHeaders.isEmpty ? nil : options.customHeaders,
                fixedCallId: options.fixedCallId,
                error: &error
            )
            if let error {
                throw SipError.from(error)
            }
            if callId < 0 {
                throw SipError.bridgeError(code: -1, message: "Failed to initiate outgoing call.", reason: nil)
            }
            return callId
        }
    }

    /// Places a direct SIP call without prior account registration (mirrors `makeDirectCall`).
    @discardableResult
    public func makeDirectCall(
        destinationURI: String,
        transport: SipTransport = .udp,
        isVideo: Bool = false,
        customHeaders: [String: String] = [:]
    ) async throws -> Int32 {
        try await runOnWorker { [engine] in
            var error: NSError?
            let callId = engine.makeDirectCall(
                to: destinationURI,
                transport: transport.bridgeValue,
                isVideo: isVideo,
                customHeaders: customHeaders.isEmpty ? nil : customHeaders,
                error: &error
            )
            if let error {
                throw SipError.from(error)
            }
            if callId < 0 {
                throw SipError.bridgeError(code: -1, message: "Failed to initiate direct call.", reason: nil)
            }
            return callId
        }
    }

    // MARK: - In-Call Operations (mirrors SipServiceCommand call APIs)

    public func answerIncomingCall(
        accountId: String,
        callId: Int32,
        isVideo: Bool = false,
        isVideoMutedInitially: Bool = false
    ) async throws {
        try await runOnWorker { [engine] in
            try engine.answerCall(
                callId,
                inAccount: accountId,
                isVideo: isVideo,
                isVideoMuteInit: isVideoMutedInitially
            )
        }
    }

    public func declineIncomingCall(
        accountId: String,
        callId: Int32,
        statusCode: Int32 = 603
    ) async throws {
        try await runOnWorker { [engine] in
            try engine.declineCall(callId, inAccount: accountId, statusCode: statusCode)
        }
    }

    public func hangupCall(accountId: String, callId: Int32) async throws {
        try await runOnWorker { [engine] in
            try engine.hangupCall(callId, inAccount: accountId)
        }
    }

    public func hangupAllCalls() async throws {
        try await runOnWorker { [engine] in
            try engine.hangupAllCalls()
        }
    }

    public func setCallMute(accountId: String, callId: Int32, muted: Bool) async throws {
        try await runOnWorker { [engine] in
            try engine.setMute(muted, forCall: callId, inAccount: accountId)
        }
    }

    public func setCallHold(accountId: String, callId: Int32, hold: Bool) async throws {
        try await runOnWorker { [engine] in
            try engine.setHold(hold, forCall: callId, inAccount: accountId)
        }
    }

    public func holdAllCalls() async throws {
        try await runOnWorker { [engine] in
            try engine.holdAllCalls()
        }
    }

    /// Reconnects an active call with updated contact/media after network transitions.
    public func reconnectCall(accountId: String, callId: Int32) async throws {
        try await runOnWorker { [engine] in
            try engine.reconnectCall(callId, inAccount: accountId)
        }
    }

    public func blindTransferCall(
        accountId: String,
        callId: Int32,
        destinationURI: String
    ) async throws {
        try await runOnWorker { [engine] in
            try engine.blindTransferCall(callId, inAccount: accountId, toDestination: destinationURI)
        }
    }

    public func attendedTransferCall(
        accountId: String,
        callId: Int32,
        targetCallId: Int32
    ) async throws {
        try await runOnWorker { [engine] in
            try engine.attendedTransferCall(callId, inAccount: accountId, toTargetCallId: targetCallId)
        }
    }

    public func sendDTMF(accountId: String, callId: Int32, digits: String) async throws {
        try await runOnWorker { [engine] in
            try engine.sendDTMF(digits, forCall: callId, inAccount: accountId)
        }
    }

    // MARK: - Video, Codec Tuning & Audio Device Control

    public func setVideoMute(accountId: String, callId: Int32, muted: Bool) async throws {
        try await runOnWorker { [engine] in
            try engine.setVideoMute(muted, forCall: callId, inAccount: accountId)
        }
    }

    public func switchCamera(accountId: String, callId: Int32) async throws {
        try await runOnWorker { [engine] in
            try engine.switchCamera(forCall: callId, inAccount: accountId)
        }
    }

    /// Updates video codec priority and encoder parameters (e.g., H.264 640x480@15fps, packetization-mode=1).
    public func setVideoCodecParameters(_ parameters: SipVideoCodecParameters) async throws {
        let bridged = parameters.toBridge()
        try await runOnWorker { [engine] in
            try engine.setVideoCodecParam(bridged)
        }
    }

    /// Sets camera capture orientation (`captureDeviceId: -1` uses the default capture device).
    public func setVideoCaptureOrientation(
        _ orientation: SipVideoOrientation,
        captureDeviceId: Int32 = -1
    ) async throws {
        try await runOnWorker { [engine] in
            try engine.setVideoCaptureOrientation(orientation.bridgeValue, captureDeviceId: captureDeviceId)
        }
    }

    /// Activates or suspends PJSIP's CoreAudio sound device (`setNullDev` when inactive for CallKit handoff).
    public func setAudioDeviceActive(_ active: Bool) async throws {
        try await runOnWorker { [engine] in
            try engine.setAudioDeviceActive(active)
        }
    }

    public func callInfo(accountId: String, callId: Int32) async throws -> SipCallInfo? {
        try await runOnWorker { [engine] in
            guard let bridgeInfo = engine.callInfo(forCall: callId, inAccount: accountId) else {
                return nil
            }
            return SipCallInfo(bridge: bridgeInfo)
        }
    }

    // MARK: - Codec Priority Management

    public func getCodecPriorities() async throws -> [CodecPriority] {
        try await runOnWorker { [engine] in
            let list = try engine.codecPriorities()
            return list.map(CodecPriority.init(bridge:))
        }
    }

    public func setCodecPriorities(_ priorities: [CodecPriority]) async throws {
        let bridged = priorities.map { $0.toBridge() }
        try await runOnWorker { [engine] in
            try engine.setCodecPriorities(bridged)
        }
    }

    // MARK: - Private Helpers

    private func runOnWorker<T: Sendable>(_ work: @escaping () throws -> T) async throws -> T {
        try await worker.execute { [engine] in
            do {
                try engine.registerCurrentThread(withName: "com.pjsipios.pjsua2-worker")
                return try work()
            } catch {
                throw SipError.from(error)
            }
        }
    }

    private func startNetworkMonitoring() {
        networkMonitor.start { [weak self] status in
            guard let self else { return }
            self.logger.info("Network", "Path changed reachable=\(status.isReachable) expensive=\(status.isExpensive)")
            self.emitEvent(.networkChanged(isReachable: status.isReachable, isExpensive: status.isExpensive))

            if status.isReachable && self.isStarted {
                Task { [weak self] in
                    do {
                        try await self?.handleIPChange()
                    } catch {
                        self?.logger.error("Network", "handleIPChange failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func emitEvent(_ event: SipEvent) {
        broadcaster.emit(event)

        delegateQueue.async { [weak self] in
            guard let self, let delegate = self.delegate else { return }
            switch event {
            case .stackStatus(let started):
                delegate.sipService(self, didChangeStackStatus: started)
            case .registration(let accountId, let statusCode, let reason, let isActive):
                delegate.sipService(self, didChangeRegistration: accountId, statusCode: statusCode, reason: reason, isActive: isActive)
            case .incomingCall(let info):
                delegate.sipService(self, didReceiveIncomingCall: info)
            case .callState(let info):
                delegate.sipService(self, didChangeCallState: info)
            case .callMediaState(let media):
                delegate.sipService(self, didChangeCallMediaState: media)
            case .videoMediaReady(let views):
                delegate.sipService(self, didPrepareVideoViews: views)
            case .callStats(let stats):
                delegate.sipService(self, didReceiveCallStats: stats)
            case .dtmfDigit(let accountId, let callId, let digit):
                delegate.sipService(self, didReceiveDTMF: digit, accountId: accountId, callId: callId)
            case .transferStatus(let accountId, let callId, let statusCode, let reason, let isFinal):
                delegate.sipService(self, didChangeTransferStatus: accountId, callId: callId, statusCode: statusCode, reason: reason, isFinal: isFinal)
            case .networkChanged(let isReachable, let isExpensive):
                delegate.sipService(self, didDetectNetworkChange: isReachable, isExpensive: isExpensive)
            }
        }
    }
}

// MARK: - PJBridgeDelegate

extension SipService: PJBridgeDelegate {
    public func bridgeDidChangeStackStatus(_ started: Bool) {
        emitEvent(.stackStatus(started: started))
    }

    public func bridgeAccount(_ accountIdURI: String, didChangeRegStatus statusCode: Int32, reason: String, isActive: Bool) {
        emitEvent(.registration(accountId: accountIdURI, statusCode: statusCode, reason: reason, isActive: isActive))
    }

    public func bridgeAccount(_ accountIdURI: String, didReceive callInfo: PJBridgeCallInfo) {
        emitEvent(.incomingCall(SipCallInfo(bridge: callInfo)))
    }

    public func bridgeAccount(_ accountIdURI: String, didChangeCallState callInfo: PJBridgeCallInfo) {
        emitEvent(.callState(SipCallInfo(bridge: callInfo)))
    }

    public func bridgeAccount(
        _ accountIdURI: String,
        didChangeMediaForCall callId: Int32,
        isLocalHold: Bool,
        isLocalMuted: Bool,
        isVideoMuted: Bool,
        isVideo: Bool
    ) {
        let state = SipCallMediaState(
            accountId: accountIdURI,
            callId: callId,
            isLocalHold: isLocalHold,
            isLocalMuted: isLocalMuted,
            isVideoMuted: isVideoMuted,
            isVideo: isVideo
        )
        emitEvent(.callMediaState(state))
    }

    public func bridgeAccount(
        _ accountIdURI: String,
        didPrepareVideoForCall callId: Int32,
        localPreview localView: UIView?,
        remoteVideo remoteView: UIView?
    ) {
        let views = SipVideoViews(
            accountId: accountIdURI,
            callId: callId,
            localPreview: localView,
            remoteVideo: remoteView
        )
        emitEvent(.videoMediaReady(views))
    }

    public func bridgeAccount(_ accountIdURI: String, didReceive callStats: PJBridgeCallStats) {
        emitEvent(.callStats(SipCallStats(bridge: callStats)))
    }

    public func bridgeAccount(_ accountIdURI: String, didReceiveDtmfDigit digit: String, forCall callId: Int32) {
        emitEvent(.dtmfDigit(accountId: accountIdURI, callId: callId, digit: digit))
    }

    public func bridgeAccount(_ accountIdURI: String, didChangeTransferStatus statusCode: Int32, reason: String, isFinal: Bool, forCall callId: Int32) {
        emitEvent(.transferStatus(accountId: accountIdURI, callId: callId, statusCode: statusCode, reason: reason, isFinal: isFinal))
    }

    public func bridgeDidReceiveLogMessage(_ message: String, level: PJBridgeLogLevel) {
        logger.log(SipLogLevel(bridgeValue: level), tag: "PJSIP", message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
