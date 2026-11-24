import Foundation
import PJSUA2Bridge

public enum SipError: Error, LocalizedError, Sendable {
    case stackNotStarted
    case accountNotFound(String)
    case callNotFound(accountId: String, callId: Int32)
    case invalidConfiguration(String)
    case keychainFailure(OSStatus)
    case audioSessionFailure(String)
    case bridgeError(code: Int, message: String, reason: String?)

    public var errorDescription: String? {
        switch self {
        case .stackNotStarted:
            return "SIP stack is not started."
        case .accountNotFound(let accountId):
            return "SIP account not found: \(accountId)"
        case .callNotFound(let accountId, let callId):
            return "SIP call \(callId) not found for account \(accountId)."
        case .invalidConfiguration(let detail):
            return "Invalid SIP configuration: \(detail)"
        case .keychainFailure(let status):
            return "Keychain operation failed with OSStatus \(status)."
        case .audioSessionFailure(let detail):
            return "AVAudioSession configuration failed: \(detail)"
        case .bridgeError(let code, let message, let reason):
            if let reason, !reason.isEmpty {
                return "PJSIP error (\(code)): \(message) [\(reason)]"
            }
            return "PJSIP error (\(code)): \(message)"
        }
    }

    static func from(_ error: Error) -> SipError {
        if let sipError = error as? SipError {
            return sipError
        }
        let nsError = error as NSError
        if nsError.domain == PJBridgeErrorDomain {
            return .bridgeError(
                code: nsError.code,
                message: nsError.localizedDescription,
                reason: nsError.localizedFailureReason
            )
        }
        return .bridgeError(code: nsError.code, message: nsError.localizedDescription, reason: nil)
    }
}
