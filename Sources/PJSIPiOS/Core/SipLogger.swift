import Foundation
import os

/// Pluggable logging delegate mirroring VoiSmart/pjsip-android's `Logger.LoggerDelegate`.
public protocol SipLogHandler: AnyObject, Sendable {
    func log(level: SipLogLevel, tag: String, message: String)
}

/// Default `os.Logger`-backed handler.
public final class DefaultOSLogHandler: SipLogHandler, @unchecked Sendable {
    private let subsystem: String

    public init(subsystem: String = "com.pjsipios.sdk") {
        self.subsystem = subsystem
    }

    public func log(level: SipLogLevel, tag: String, message: String) {
        let logger = Logger(subsystem: subsystem, category: tag)
        switch level {
        case .fatal:
            logger.fault("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .debug, .trace:
            logger.debug("\(message, privacy: .public)")
        }
    }
}

/// Global SDK logger configurable at runtime.
public final class SipLogger: @unchecked Sendable {
    public static let shared = SipLogger()

    private let lock = NSLock()
    private var _minLevel: SipLogLevel = .debug
    private var _handler: SipLogHandler = DefaultOSLogHandler()

    private init() {}

    public var minLevel: SipLogLevel {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _minLevel
        }
        set {
            lock.lock()
            _minLevel = newValue
            lock.unlock()
        }
    }

    public func setHandler(_ handler: SipLogHandler) {
        lock.lock()
        _handler = handler
        lock.unlock()
    }

    public func log(_ level: SipLogLevel, tag: String, _ message: String) {
        lock.lock()
        let allowed = level <= _minLevel
        let handler = _handler
        lock.unlock()

        guard allowed else { return }
        handler.log(level: level, tag: tag, message: message)
    }

    public func debug(_ tag: String, _ message: String) { log(.debug, tag: tag, message) }
    public func info(_ tag: String, _ message: String) { log(.info, tag: tag, message) }
    public func warning(_ tag: String, _ message: String) { log(.warning, tag: tag, message) }
    public func error(_ tag: String, _ message: String) { log(.error, tag: tag, message) }
}
