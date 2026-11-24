import Foundation
import PJSUA2Bridge

public enum SipLogLevel: Int, Codable, Sendable, Comparable {
    case fatal = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4
    case trace = 5

    public static func < (lhs: SipLogLevel, rhs: SipLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var bridgeValue: PJBridgeLogLevel {
        PJBridgeLogLevel(rawValue: rawValue) ?? .info
    }

    init(bridgeValue: PJBridgeLogLevel) {
        self = SipLogLevel(rawValue: bridgeValue.rawValue) ?? .info
    }
}

/// Video codec priority and encoder tuning (e.g., H264/97 640x480@15fps, 512kbps, packetization-mode=1
/// for interoperability with hardware SIP phones and GB28181 gateways).
public struct SipVideoCodecParameters: Codable, Equatable, Sendable {
    public var codecId: String
    public var priority: UInt8
    public var width: UInt32
    public var height: UInt32
    public var fps: UInt32
    public var avgBitrateBps: UInt32
    public var maxBitrateBps: UInt32
    public var packetizationMode: String?

    public static let h264Standard = SipVideoCodecParameters(
        codecId: "H264/97",
        priority: 255,
        width: 640,
        height: 480,
        fps: 15,
        avgBitrateBps: 512_000,
        maxBitrateBps: 1_024_000,
        packetizationMode: "1"
    )

    public init(
        codecId: String = "H264/97",
        priority: UInt8 = 255,
        width: UInt32 = 640,
        height: UInt32 = 480,
        fps: UInt32 = 15,
        avgBitrateBps: UInt32 = 512_000,
        maxBitrateBps: UInt32 = 1_024_000,
        packetizationMode: String? = "1"
    ) {
        self.codecId = codecId
        self.priority = priority
        self.width = width
        self.height = height
        self.fps = fps
        self.avgBitrateBps = avgBitrateBps
        self.maxBitrateBps = maxBitrateBps
        self.packetizationMode = packetizationMode
    }

    func toBridge() -> PJBridgeVideoCodecParam {
        let param = PJBridgeVideoCodecParam()
        param.codecId = codecId
        param.priority = priority
        param.width = width
        param.height = height
        param.fps = fps
        param.avgBitrateBps = avgBitrateBps
        param.maxBitrateBps = maxBitrateBps
        param.packetizationMode = packetizationMode
        return param
    }
}

/// Endpoint-level stack configuration applied when starting `SipService`.
public struct SipEndpointConfiguration: Codable, Equatable, Sendable {
    public var userAgent: String
    public var maxCalls: Int
    public var threadCount: Int
    public var clockRate: UInt32
    public var echoCancellationTailMs: UInt32
    public var disableVAD: Bool
    public var enableVideo: Bool
    /// Calls `setNullDev()` immediately after stack startup so CallKit controls CoreAudio activation.
    public var suspendAudioDeviceOnStart: Bool
    /// Optional preferred video codec parameters applied immediately on startup (e.g., `.h264Standard`).
    public var preferredVideoCodec: SipVideoCodecParameters?
    /// Enable TLS server certificate verification (mirrors `setVerifySipServerCert` in pjsip-android).
    public var verifySipServerCert: Bool
    /// Optional path to a custom CA bundle `.crt`/`.pem` file.
    public var caListFilePath: String?
    /// Enable DNS SRV resolution (RFC 3263, mirrors `setDnsSrvLookup` in pjsip-android).
    public var enableDnsSrvLookup: Bool
    /// Optional explicit DNS servers for SRV queries (e.g. `["8.8.8.8", "1.1.1.1"]`).
    public var dnsServers: [String]
    /// Forward native PJSIP logs to `SipLogger` (mirrors `SipServiceUtils.ENABLE_SIP_LOGGING`).
    public var enableSipLogging: Bool
    public var sipLogLevel: SipLogLevel
    public var localUDPPort: UInt16
    public var localTCPPort: UInt16
    public var localTLSPort: UInt16
    /// Automatically monitor network path changes (Wi-Fi <-> Cellular) via NWPathMonitor.
    public var enableAutoNetworkRecovery: Bool

    public init(
        userAgent: String = "PJSIPiOS/1.0",
        maxCalls: Int = 4,
        threadCount: Int = 1,
        clockRate: UInt32 = 16000,
        echoCancellationTailMs: UInt32 = 100,
        disableVAD: Bool = true,
        enableVideo: Bool = true,
        suspendAudioDeviceOnStart: Bool = true,
        preferredVideoCodec: SipVideoCodecParameters? = .h264Standard,
        verifySipServerCert: Bool = false,
        caListFilePath: String? = nil,
        enableDnsSrvLookup: Bool = false,
        dnsServers: [String] = [],
        enableSipLogging: Bool = false,
        sipLogLevel: SipLogLevel = .info,
        localUDPPort: UInt16 = 0,
        localTCPPort: UInt16 = 0,
        localTLSPort: UInt16 = 0,
        enableAutoNetworkRecovery: Bool = true
    ) {
        self.userAgent = userAgent
        self.maxCalls = maxCalls
        self.threadCount = threadCount
        self.clockRate = clockRate
        self.echoCancellationTailMs = echoCancellationTailMs
        self.disableVAD = disableVAD
        self.enableVideo = enableVideo
        self.suspendAudioDeviceOnStart = suspendAudioDeviceOnStart
        self.preferredVideoCodec = preferredVideoCodec
        self.verifySipServerCert = verifySipServerCert
        self.caListFilePath = caListFilePath
        self.enableDnsSrvLookup = enableDnsSrvLookup
        self.dnsServers = dnsServers
        self.enableSipLogging = enableSipLogging
        self.sipLogLevel = sipLogLevel
        self.localUDPPort = localUDPPort
        self.localTCPPort = localTCPPort
        self.localTLSPort = localTLSPort
        self.enableAutoNetworkRecovery = enableAutoNetworkRecovery
    }

    func toBridgeConfig() -> PJBridgeEndpointConfig {
        let cfg = PJBridgeEndpointConfig()
        cfg.userAgent = userAgent
        cfg.maxCalls = UInt(max(1, maxCalls))
        cfg.threadCount = UInt(max(1, threadCount))
        cfg.clockRate = clockRate
        cfg.echoCancellationTailMs = echoCancellationTailMs
        cfg.disableVAD = disableVAD
        cfg.enableVideo = enableVideo
        cfg.suspendAudioDeviceOnStart = suspendAudioDeviceOnStart
        cfg.preferredVideoCodec = preferredVideoCodec?.toBridge()
        cfg.verifySipServerCert = verifySipServerCert
        cfg.caListFilePath = caListFilePath
        cfg.enableDnsSrvLookup = enableDnsSrvLookup
        cfg.dnsServers = dnsServers
        cfg.enableSipLogging = enableSipLogging
        cfg.sipLogLevel = sipLogLevel.bridgeValue
        cfg.localUDPPort = localUDPPort
        cfg.localTCPPort = localTCPPort
        cfg.localTLSPort = localTLSPort
        return cfg
    }
}
