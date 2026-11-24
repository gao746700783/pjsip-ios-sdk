import Foundation

/// Exhaustive event enum mirroring VoiSmart/pjsip-android's `BroadcastEventEmitter`.
public enum SipEvent: Equatable, Sendable {
    case stackStatus(started: Bool)
    case registration(accountId: String, statusCode: Int32, reason: String, isActive: Bool)
    case incomingCall(SipCallInfo)
    case callState(SipCallInfo)
    case callMediaState(SipCallMediaState)
    case videoMediaReady(SipVideoViews)
    case callStats(SipCallStats)
    case dtmfDigit(accountId: String, callId: Int32, digit: String)
    case transferStatus(accountId: String, callId: Int32, statusCode: Int32, reason: String, isFinal: Bool)
    case networkChanged(isReachable: Bool, isExpensive: Bool)
}
