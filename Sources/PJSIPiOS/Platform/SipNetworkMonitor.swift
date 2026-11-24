import Foundation
import Network

/// Monitors iOS network path transitions (Wi-Fi <-> Cellular, offline <-> online)
/// via `NWPathMonitor` to trigger PJSIP IP change handling and call reconnection.
public final class SipNetworkMonitor: @unchecked Sendable {
    public struct Status: Equatable, Sendable {
        public let isReachable: Bool
        public let isExpensive: Bool
        public let interfaceSignature: String
    }

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var lastStatus: Status?
    private var onChange: ((Status) -> Void)?

    public init(queueLabel: String = "com.pjsipios.network-monitor") {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    deinit {
        stop()
    }

    public func start(onChange: @escaping (Status) -> Void) {
        lock.lock()
        self.onChange = onChange
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePath(path)
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
        lock.lock()
        onChange = nil
        lastStatus = nil
        lock.unlock()
    }

    private func handlePath(_ path: NWPath) {
        let isReachable = (path.status == .satisfied)
        let interfaces = path.availableInterfaces
            .map { "\($0.name):\($0.type)" }
            .sorted()
            .joined(separator: ",")
        let status = Status(
            isReachable: isReachable,
            isExpensive: path.isExpensive,
            interfaceSignature: interfaces
        )

        lock.lock()
        let previous = lastStatus
        lastStatus = status
        let callback = onChange
        lock.unlock()

        if previous != nil && previous != status {
            callback?(status)
        }
    }
}
