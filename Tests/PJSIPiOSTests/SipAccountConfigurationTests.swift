import XCTest
@testable import PJSIPiOS

final class SipAccountConfigurationTests: XCTestCase {
    func testDefaultPortsMatchTransport() {
        let udp = SipAccountConfiguration(host: "pbx.example.com", username: "1001", password: "secret", transport: .udp)
        let tcp = SipAccountConfiguration(host: "pbx.example.com", username: "1001", password: "secret", transport: .tcp)
        let tls = SipAccountConfiguration(host: "pbx.example.com", username: "1001", password: "secret", transport: .tls)

        XCTAssertEqual(udp.port, 5060)
        XCTAssertEqual(tcp.port, 5060)
        XCTAssertEqual(tls.port, 5061)
        XCTAssertEqual(udp.idURI, "sip:1001@pbx.example.com")
        XCTAssertEqual(tls.idURI, "sips:1001@pbx.example.com")
    }

    func testValidationRejectsEmptyHostOrUsername() {
        let missingHost = SipAccountConfiguration(host: "   ", username: "1001", password: "secret")
        XCTAssertThrowsError(try missingHost.validate())

        let missingUser = SipAccountConfiguration(host: "pbx.example.com", username: "", password: "secret")
        XCTAssertThrowsError(try missingUser.validate())
    }

    func testCodableRoundTripPreservesAllFields() throws {
        let original = SipAccountConfiguration(
            host: "sip.example.com",
            port: 5061,
            username: "alice",
            password: "pw",
            realm: "example.com",
            displayName: "Alice",
            srvDomain: "srv.example.com",
            transport: .tls,
            srtpMode: .mandatory,
            srtpSecureSignaling: true,
            regTimeoutSec: 600,
            regRetryIntervalSec: 30,
            enableICE: true,
            enableVideoAutoShow: true,
            enableVideoAutoTransmit: true,
            proxies: ["sips:proxy.example.com:5061;transport=tls"]
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SipAccountConfiguration.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }
}
