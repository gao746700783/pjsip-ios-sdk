import Foundation
import PJSUA2Bridge

public enum SipTransport: String, Codable, Sendable, CaseIterable {
    case udp
    case tcp
    case tls

    var bridgeValue: PJBridgeTransportType {
        switch self {
        case .udp: return .UDP
        case .tcp: return .TCP
        case .tls: return .TLS
        }
    }

    public var defaultPort: UInt16 {
        switch self {
        case .udp, .tcp: return 5060
        case .tls: return 5061
        }
    }
}

public enum SipSRTPMode: String, Codable, Sendable, CaseIterable {
    case disabled
    case optional
    case mandatory

    var bridgeValue: PJBridgeSRTPMode {
        switch self {
        case .disabled: return .disabled
        case .optional: return .optional
        case .mandatory: return .mandatory
        }
    }
}

/// Account configuration mirroring VoiSmart/pjsip-android's `SipAccountData`.
public struct SipAccountConfiguration: Codable, Equatable, Sendable, Identifiable {
    public var host: String
    public var port: UInt16
    public var username: String
    public var password: String
    public var realm: String
    public var displayName: String?
    /// Optional domain for DNS SRV (RFC 3263) lookup when different from `host`.
    public var srvDomain: String?
    public var transport: SipTransport
    public var srtpMode: SipSRTPMode
    public var srtpSecureSignaling: Bool
    public var regTimeoutSec: UInt32
    public var regRetryIntervalSec: UInt32
    public var enableICE: Bool
    public var enableVideoAutoShow: Bool
    public var enableVideoAutoTransmit: Bool
    public var proxies: [String]

    /// Canonical account identifier URI (e.g. `sip:1001@pbx.example.com` or `sips:1001@pbx.example.com`).
    public var id: String { idURI }

    public var idURI: String {
        let scheme = transport == .tls ? "sips" : "sip"
        return "\(scheme):\(username)@\(host)"
    }

    public init(
        host: String,
        port: UInt16? = nil,
        username: String,
        password: String,
        realm: String = "*",
        displayName: String? = nil,
        srvDomain: String? = nil,
        transport: SipTransport = .udp,
        srtpMode: SipSRTPMode = .disabled,
        srtpSecureSignaling: Bool = false,
        regTimeoutSec: UInt32 = 300,
        regRetryIntervalSec: UInt32 = 60,
        enableICE: Bool = false,
        enableVideoAutoShow: Bool = true,
        enableVideoAutoTransmit: Bool = false,
        proxies: [String] = []
    ) {
        self.host = host
        self.port = port ?? transport.defaultPort
        self.username = username
        self.password = password
        self.realm = realm
        self.displayName = displayName
        self.srvDomain = srvDomain
        self.transport = transport
        self.srtpMode = srtpMode
        self.srtpSecureSignaling = srtpSecureSignaling
        self.regTimeoutSec = regTimeoutSec
        self.regRetryIntervalSec = regRetryIntervalSec
        self.enableICE = enableICE
        self.enableVideoAutoShow = enableVideoAutoShow
        self.enableVideoAutoTransmit = enableVideoAutoTransmit
        self.proxies = proxies
    }

    public func validate() throws {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SipError.invalidConfiguration("host must not be empty.")
        }
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SipError.invalidConfiguration("username must not be empty.")
        }
    }

    func toBridgeConfig() -> PJBridgeAccountConfig {
        let cfg = PJBridgeAccountConfig()
        cfg.accountIdURI = idURI
        cfg.host = host
        cfg.port = port
        cfg.username = username
        cfg.password = password
        cfg.realm = realm
        cfg.displayName = displayName
        cfg.srvDomain = srvDomain
        cfg.transport = transport.bridgeValue
        cfg.srtpMode = srtpMode.bridgeValue
        cfg.srtpSecureSignaling = srtpSecureSignaling
        cfg.regTimeoutSec = regTimeoutSec
        cfg.regRetryIntervalSec = regRetryIntervalSec
        cfg.enableICE = enableICE
        cfg.enableVideoAutoShow = enableVideoAutoShow
        cfg.enableVideoAutoTransmit = enableVideoAutoTransmit
        cfg.proxies = proxies
        return cfg
    }
}
