import Foundation

/// Delegate protocol mirroring VoiSmart/pjsip-android's `BroadcastEventReceiver`.
/// All methods have default empty implementations so consumers only override what they need.
public protocol SipEventDelegate: AnyObject {
    func sipService(_ service: SipService, didChangeStackStatus started: Bool)
    func sipService(_ service: SipService, didChangeRegistration accountId: String, statusCode: Int32, reason: String, isActive: Bool)
    func sipService(_ service: SipService, didReceiveIncomingCall callInfo: SipCallInfo)
    func sipService(_ service: SipService, didChangeCallState callInfo: SipCallInfo)
    func sipService(_ service: SipService, didChangeCallMediaState mediaState: SipCallMediaState)
    func sipService(_ service: SipService, didPrepareVideoViews videoViews: SipVideoViews)
    func sipService(_ service: SipService, didReceiveCallStats stats: SipCallStats)
    func sipService(_ service: SipService, didReceiveDTMF digit: String, accountId: String, callId: Int32)
    func sipService(_ service: SipService, didChangeTransferStatus accountId: String, callId: Int32, statusCode: Int32, reason: String, isFinal: Bool)
    func sipService(_ service: SipService, didDetectNetworkChange isReachable: Bool, isExpensive: Bool)
}

public extension SipEventDelegate {
    func sipService(_ service: SipService, didChangeStackStatus started: Bool) {}
    func sipService(_ service: SipService, didChangeRegistration accountId: String, statusCode: Int32, reason: String, isActive: Bool) {}
    func sipService(_ service: SipService, didReceiveIncomingCall callInfo: SipCallInfo) {}
    func sipService(_ service: SipService, didChangeCallState callInfo: SipCallInfo) {}
    func sipService(_ service: SipService, didChangeCallMediaState mediaState: SipCallMediaState) {}
    func sipService(_ service: SipService, didPrepareVideoViews videoViews: SipVideoViews) {}
    func sipService(_ service: SipService, didReceiveCallStats stats: SipCallStats) {}
    func sipService(_ service: SipService, didReceiveDTMF digit: String, accountId: String, callId: Int32) {}
    func sipService(_ service: SipService, didChangeTransferStatus accountId: String, callId: Int32, statusCode: Int32, reason: String, isFinal: Bool) {}
    func sipService(_ service: SipService, didDetectNetworkChange isReachable: Bool, isExpensive: Bool) {}
}
