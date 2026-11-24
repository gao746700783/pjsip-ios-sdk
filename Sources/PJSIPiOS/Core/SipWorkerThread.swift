import Foundation

/// Dedicated serial worker thread for all PJSUA2 invocations.
/// PJSIP requires every non-PJSIP thread that invokes PJLIB/PJSUA2 APIs to be registered
/// via `pj::Endpoint::libRegisterThread`. Using one persistent thread avoids repeated thread
/// registrations across GCD thread pools and guarantees non-blocking UI execution.
final class SipWorkerThread: @unchecked Sendable {
    private let thread: Thread
    private let condition = NSCondition()
    private var queue: [() -> Void] = []
    private var isStopped = false
    private let threadName: String

    init(name: String = "com.pjsipios.worker") {
        self.threadName = name
        var runner: (() -> Void)?
        let worker = Thread {
            runner?()
        }
        worker.name = name
        worker.qualityOfService = .userInitiated
        self.thread = worker

        runner = { [weak self] in
            self?.runLoop()
        }
        worker.start()
    }

    deinit {
        stop()
    }

    func execute<T: Sendable>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            enqueue {
                do {
                    let result = try work()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func enqueue(_ block: @escaping () -> Void) {
        condition.lock()
        guard !isStopped else {
            condition.unlock()
            return
        }
        queue.append(block)
        condition.signal()
        condition.unlock()
    }

    func stop() {
        condition.lock()
        isStopped = true
        condition.broadcast()
        condition.unlock()
    }

    private func runLoop() {
        while true {
            condition.lock()
            while queue.isEmpty && !isStopped {
                condition.wait()
            }
            if isStopped && queue.isEmpty {
                condition.unlock()
                return
            }
            let work = queue.removeFirst()
            condition.unlock()

            autoreleasepool {
                work()
            }
        }
    }
}
