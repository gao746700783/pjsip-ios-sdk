import XCTest
@testable import PJSIPiOS

final class SipEventBroadcasterTests: XCTestCase {
    func testMultipleSubscribersReceiveBroadcastedEvents() async {
        let broadcaster = SipEventBroadcaster()
        let streamA = broadcaster.makeStream()
        let streamB = broadcaster.makeStream()

        let taskA = Task<[SipEvent], Never> {
            var collected: [SipEvent] = []
            for await event in streamA {
                collected.append(event)
                if collected.count == 2 { break }
            }
            return collected
        }

        let taskB = Task<[SipEvent], Never> {
            var collected: [SipEvent] = []
            for await event in streamB {
                collected.append(event)
                if collected.count == 2 { break }
            }
            return collected
        }

        try? await Task.sleep(nanoseconds: 20_000_000)

        let expected: [SipEvent] = [
            .stackStatus(started: true),
            .registration(accountId: "sip:1001@pbx.local", statusCode: 200, reason: "OK", isActive: true)
        ]
        for event in expected {
            broadcaster.emit(event)
        }

        let receivedA = await taskA.value
        let receivedB = await taskB.value
        XCTAssertEqual(receivedA, expected)
        XCTAssertEqual(receivedB, expected)
    }
}
