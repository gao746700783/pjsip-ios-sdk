import AVFoundation
import CallKit
import Foundation

/// Optional CallKit adapter bridging `SipService` calls with Apple's `CXProvider` and `CXCallController`.
/// Apps that do not use CallKit (e.g., internal PTT/intercom clients) can ignore this class completely.
public final class SipCallKitAdapter: NSObject, @unchecked Sendable {
    public struct CallMapping: Sendable {
        public let uuid: UUID
        public let accountId: String
        public let callId: Int32
        public let isVideo: Bool
    }

    private unowned let sipService: SipService
    private let provider: CXProvider
    private let callController = CXCallController()
    private let lock = NSLock()
    private var uuidToCall: [UUID: CallMapping] = [:]
    private var callKeyToUUID: [String: UUID] = [:]
    private let logger: SipLogger

    public init(
        sipService: SipService,
        localizedName: String,
        supportsVideo: Bool = true,
        maximumCallGroups: Int = 2,
        maximumCallsPerCallGroup: Int = 1,
        logger: SipLogger = .shared
    ) {
        self.sipService = sipService
        self.logger = logger

        let config = CXProviderConfiguration(localizedName: localizedName)
        config.supportsVideo = supportsVideo
        config.maximumCallGroups = maximumCallGroups
        config.maximumCallsPerCallGroup = maximumCallsPerCallGroup
        config.supportedHandleTypes = [.generic, .phoneNumber]

        self.provider = CXProvider(configuration: config)
        super.init()
        self.provider.setDelegate(self, queue: nil)
    }

    /// Reports an incoming SIP call (e.g., from PushKit or `didReceiveIncomingCall`) to CallKit.
    public func reportIncomingCall(
        uuid: UUID = UUID(),
        accountId: String,
        callId: Int32,
        remoteHandle: String,
        displayName: String? = nil,
        hasVideo: Bool = false
    ) async throws -> UUID {
        registerMapping(CallMapping(uuid: uuid, accountId: accountId, callId: callId, isVideo: hasVideo))

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: remoteHandle)
        update.localizedCallerName = displayName ?? remoteHandle
        update.hasVideo = hasVideo
        update.supportsHolding = true
        update.supportsDTMF = true
        update.supportsGrouping = false
        update.supportsUngrouping = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            provider.reportNewIncomingCall(with: uuid, update: update) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        return uuid
    }

    /// Reports an outgoing SIP call to CallKit.
    public func startOutgoingCall(
        uuid: UUID = UUID(),
        accountId: String,
        callId: Int32,
        remoteHandle: String,
        hasVideo: Bool = false
    ) async throws -> UUID {
        registerMapping(CallMapping(uuid: uuid, accountId: accountId, callId: callId, isVideo: hasVideo))
        let handle = CXHandle(type: .generic, value: remoteHandle)
        let action = CXStartCallAction(call: uuid, handle: handle)
        action.isVideo = hasVideo
        let transaction = CXTransaction(action: action)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            callController.request(transaction) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        return uuid
    }

    /// Notifies CallKit that a SIP call ended remotely or locally.
    public func reportCallEnded(accountId: String, callId: Int32, reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = removeMapping(accountId: accountId, callId: callId) else { return }
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
    }

    private func callKey(accountId: String, callId: Int32) -> String {
        "\(accountId)#\(callId)"
    }

    private func registerMapping(_ mapping: CallMapping) {
        lock.lock()
        uuidToCall[mapping.uuid] = mapping
        callKeyToUUID[callKey(accountId: mapping.accountId, callId: mapping.callId)] = mapping.uuid
        lock.unlock()
    }

    private func mapping(for uuid: UUID) -> CallMapping? {
        lock.lock()
        defer { lock.unlock() }
        return uuidToCall[uuid]
    }

    @discardableResult
    private func removeMapping(accountId: String, callId: Int32) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        let key = callKey(accountId: accountId, callId: callId)
        guard let uuid = callKeyToUUID.removeValue(forKey: key) else { return nil }
        uuidToCall.removeValue(forKey: uuid)
        return uuid
    }
}

extension SipCallKitAdapter: CXProviderDelegate {
    public func providerDidReset(_ provider: CXProvider) {
        logger.warning("CallKit", "CXProvider did reset — hanging up all active SIP calls.")
        Task {
            try? await sipService.hangupAllCalls()
            try? await sipService.setAudioDeviceActive(false)
        }
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let mapping = mapping(for: action.callUUID) else {
            action.fail()
            return
        }
        Task {
            do {
                try sipService.audioSessionManager.configureForCall(isVideo: mapping.isVideo)
                try await sipService.answerIncomingCall(
                    accountId: mapping.accountId,
                    callId: mapping.callId,
                    isVideo: mapping.isVideo
                )
                action.fulfill()
            } catch {
                logger.error("CallKit", "Answer failed: \(error.localizedDescription)")
                action.fail()
            }
        }
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let mapping = mapping(for: action.callUUID) else {
            action.fulfill()
            return
        }
        removeMapping(accountId: mapping.accountId, callId: mapping.callId)
        Task {
            try? await sipService.hangupCall(accountId: mapping.accountId, callId: mapping.callId)
            action.fulfill()
        }
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let mapping = mapping(for: action.callUUID) else {
            action.fail()
            return
        }
        Task {
            do {
                try await sipService.setCallMute(
                    accountId: mapping.accountId,
                    callId: mapping.callId,
                    muted: action.isMuted
                )
                action.fulfill()
            } catch {
                action.fail()
            }
        }
    }

    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        guard let mapping = mapping(for: action.callUUID) else {
            action.fail()
            return
        }
        Task {
            do {
                try await sipService.setCallHold(
                    accountId: mapping.accountId,
                    callId: mapping.callId,
                    hold: action.isOnHold
                )
                action.fulfill()
            } catch {
                action.fail()
            }
        }
    }

    public func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        guard let mapping = mapping(for: action.callUUID) else {
            action.fail()
            return
        }
        Task {
            do {
                try await sipService.sendDTMF(
                    accountId: mapping.accountId,
                    callId: mapping.callId,
                    digits: action.digits
                )
                action.fulfill()
            } catch {
                action.fail()
            }
        }
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        logger.debug("CallKit", "Audio session activated by CallKit — enabling PJSIP audio device.")
        Task {
            try? await sipService.setAudioDeviceActive(true)
        }
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        logger.debug("CallKit", "Audio session deactivated by CallKit — suspending PJSIP audio device.")
        Task {
            try? await sipService.setAudioDeviceActive(false)
        }
    }
}
