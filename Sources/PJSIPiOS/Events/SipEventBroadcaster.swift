import Foundation

/// Thread-safe multi-subscriber AsyncStream broadcaster for `SipEvent`.
public final class SipEventBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<SipEvent>.Continuation] = [:]

    public init() {}

    deinit {
        finishAll()
    }

    public func makeStream(bufferingPolicy: AsyncStream<SipEvent>.Continuation.BufferingPolicy = .bufferingNewest(128)) -> AsyncStream<SipEvent> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    public func emit(_ event: SipEvent) {
        lock.lock()
        let active = Array(continuations.values)
        lock.unlock()

        for continuation in active {
            continuation.yield(event)
        }
    }

    public func finishAll() {
        lock.lock()
        let active = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()

        for continuation in active {
            continuation.finish()
        }
    }

    private func removeContinuation(id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
