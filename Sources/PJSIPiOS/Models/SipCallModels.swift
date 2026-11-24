import Foundation
import PJSUA2Bridge
import UIKit

public enum SipCallState: Int, Codable, Sendable {
    case null = 0
    case calling = 1
    case incoming = 2
    case early = 3
    case connecting = 4
    case confirmed = 5
    case disconnected = 6

    init(bridgeValue: PJBridgeCallState) {
        self = SipCallState(rawValue: bridgeValue.rawValue) ?? .null
    }
}

public enum SipVideoOrientation: Int, Codable, Sendable {
    case natural = 0
    case rotate90 = 1
    case rotate180 = 2
    case rotate270 = 3

    var bridgeValue: PJBridgeVideoOrientation {
        PJBridgeVideoOrientation(rawValue: rawValue) ?? .natural
    }
}

/// Native iOS `UIView` handles for local camera preview and remote video rendering.
/// Attach these views on the main thread to your call UI container views.
public struct SipVideoViews: Equatable, @unchecked Sendable {
    public let accountId: String
    public let callId: Int32
    public let localPreview: UIView?
    public let remoteVideo: UIView?

    public init(accountId: String, callId: Int32, localPreview: UIView?, remoteVideo: UIView?) {
        self.accountId = accountId
        self.callId = callId
        self.localPreview = localPreview
        self.remoteVideo = remoteVideo
    }

    public static func == (lhs: SipVideoViews, rhs: SipVideoViews) -> Bool {
        lhs.accountId == rhs.accountId &&
        lhs.callId == rhs.callId &&
        lhs.localPreview === rhs.localPreview &&
        lhs.remoteVideo === rhs.remoteVideo
    }
}

public struct SipCallInfo: Equatable, Sendable {
    public let callId: Int32
    public let accountId: String
    public let sipCallId: String
    public let remoteURI: String
    public let remoteContact: String
    public let state: SipCallState
    public let stateText: String
    public let lastStatusCode: Int32
    public let lastReason: String
    public let connectDuration: TimeInterval
    public let totalDuration: TimeInterval
    public let isVideo: Bool
    public let isLocalHold: Bool
    public let isLocalMuted: Bool
    public let isVideoMuted: Bool

    public init(
        callId: Int32,
        accountId: String,
        sipCallId: String,
        remoteURI: String,
        remoteContact: String,
        state: SipCallState,
        stateText: String,
        lastStatusCode: Int32,
        lastReason: String,
        connectDuration: TimeInterval,
        totalDuration: TimeInterval,
        isVideo: Bool,
        isLocalHold: Bool,
        isLocalMuted: Bool,
        isVideoMuted: Bool
    ) {
        self.callId = callId
        self.accountId = accountId
        self.sipCallId = sipCallId
        self.remoteURI = remoteURI
        self.remoteContact = remoteContact
        self.state = state
        self.stateText = stateText
        self.lastStatusCode = lastStatusCode
        self.lastReason = lastReason
        self.connectDuration = connectDuration
        self.totalDuration = totalDuration
        self.isVideo = isVideo
        self.isLocalHold = isLocalHold
        self.isLocalMuted = isLocalMuted
        self.isVideoMuted = isVideoMuted
    }

    init(bridge: PJBridgeCallInfo) {
        self.callId = bridge.callId
        self.accountId = bridge.accountIdURI
        self.sipCallId = bridge.sipCallId
        self.remoteURI = bridge.remoteURI
        self.remoteContact = bridge.remoteContact
        self.state = SipCallState(bridgeValue: bridge.state)
        self.stateText = bridge.stateText
        self.lastStatusCode = bridge.lastStatusCode
        self.lastReason = bridge.lastReason
        self.connectDuration = bridge.connectDuration
        self.totalDuration = bridge.totalDuration
        self.isVideo = bridge.isVideo
        self.isLocalHold = bridge.isLocalHold
        self.isLocalMuted = bridge.isLocalMuted
        self.isVideoMuted = bridge.isVideoMuted
    }
}

public struct SipCallMediaState: Equatable, Sendable {
    public let accountId: String
    public let callId: Int32
    public let isLocalHold: Bool
    public let isLocalMuted: Bool
    public let isVideoMuted: Bool
    public let isVideo: Bool

    public init(
        accountId: String,
        callId: Int32,
        isLocalHold: Bool,
        isLocalMuted: Bool,
        isVideoMuted: Bool,
        isVideo: Bool
    ) {
        self.accountId = accountId
        self.callId = callId
        self.isLocalHold = isLocalHold
        self.isLocalMuted = isLocalMuted
        self.isVideoMuted = isVideoMuted
        self.isVideo = isVideo
    }
}

/// RTP/RTCP statistics collected when a call disconnects (mirrors pjsip-android `onCallStats`).
public struct SipCallStats: Equatable, Sendable {
    public let callId: Int32
    public let accountId: String
    public let duration: TimeInterval
    public let audioCodec: String
    public let callStatusCode: Int32
    public let rxPackets: UInt32
    public let txPackets: UInt32
    public let rxPacketLoss: UInt32
    public let txPacketLoss: UInt32
    public let rttMeanMs: Double
    public let rxJitterMeanMs: Double
    public let txJitterMeanMs: Double

    public init(
        callId: Int32,
        accountId: String,
        duration: TimeInterval,
        audioCodec: String,
        callStatusCode: Int32,
        rxPackets: UInt32,
        txPackets: UInt32,
        rxPacketLoss: UInt32,
        txPacketLoss: UInt32,
        rttMeanMs: Double,
        rxJitterMeanMs: Double,
        txJitterMeanMs: Double
    ) {
        self.callId = callId
        self.accountId = accountId
        self.duration = duration
        self.audioCodec = audioCodec
        self.callStatusCode = callStatusCode
        self.rxPackets = rxPackets
        self.txPackets = txPackets
        self.rxPacketLoss = rxPacketLoss
        self.txPacketLoss = txPacketLoss
        self.rttMeanMs = rttMeanMs
        self.rxJitterMeanMs = rxJitterMeanMs
        self.txJitterMeanMs = txJitterMeanMs
    }

    init(bridge: PJBridgeCallStats) {
        self.callId = bridge.callId
        self.accountId = bridge.accountIdURI
        self.duration = bridge.duration
        self.audioCodec = bridge.audioCodec
        self.callStatusCode = bridge.callStatusCode
        self.rxPackets = bridge.rxPackets
        self.txPackets = bridge.txPackets
        self.rxPacketLoss = bridge.rxPacketLoss
        self.txPacketLoss = bridge.txPacketLoss
        self.rttMeanMs = bridge.rttMeanMs
        self.rxJitterMeanMs = bridge.rxJitterMeanMs
        self.txJitterMeanMs = bridge.txJitterMeanMs
    }
}

/// Mirrors `CodecPriority` in VoiSmart/pjsip-android (`0` = disabled, `1...254` = priority).
public struct CodecPriority: Codable, Equatable, Sendable, Identifiable {
    public var id: String { codecId }
    public let codecId: String
    public var priority: UInt8

    public init(codecId: String, priority: UInt8) {
        self.codecId = codecId
        self.priority = priority
    }

    init(bridge: PJBridgeCodecPriority) {
        self.codecId = bridge.codecId
        self.priority = bridge.priority
    }

    func toBridge() -> PJBridgeCodecPriority {
        PJBridgeCodecPriority(codecId: codecId, priority: priority)
    }
}

public struct SipCallOptions: Sendable {
    public var isVideo: Bool
    public var isVideoMutedInitially: Bool
    public var isSilentCall: Bool
    public var customHeaders: [String: String]
    /// Optional fixed SIP `Call-ID` header (mirrors pjsip-android fixed Call-ID support).
    public var fixedCallId: String?

    public init(
        isVideo: Bool = false,
        isVideoMutedInitially: Bool = false,
        isSilentCall: Bool = false,
        customHeaders: [String: String] = [:],
        fixedCallId: String? = nil
    ) {
        self.isVideo = isVideo
        self.isVideoMutedInitially = isVideoMutedInitially
        self.isSilentCall = isSilentCall
        self.customHeaders = customHeaders
        self.fixedCallId = fixedCallId
    }
}
