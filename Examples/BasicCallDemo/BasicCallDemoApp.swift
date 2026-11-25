import AVFoundation
import PJSIPiOS
import SwiftUI

@main
struct BasicCallDemoApp: App {
    var body: some Scene {
        WindowGroup { BasicCallView() }
    }
}

@MainActor
private struct BasicCallView: View {
    @State private var host = ""
    @State private var port = "5060"
    @State private var username = ""
    @State private var password = ""
    @State private var destination = ""
    @State private var accountId: String?
    @State private var registered = false
    @State private var hasCall = false
    @State private var callId: Int32?
    @State private var busy = false
    @State private var registrationStatus = "Not registered"
    @State private var callStatus = "Idle"
    @State private var errorMessage: String?

    private let sip = SipService.shared

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("SIP account (TCP)")) {
                    TextField("Server host or IP", text: $host)
                    TextField("Port", text: $port).keyboardType(.numberPad)
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                }
                .disabled(accountId != nil || busy)

                Section {
                    Text(registrationStatus)
                    Button("Register") { perform { try await register() } }
                        .disabled(busy || accountId != nil)
                    Button("Disconnect") { perform { try await disconnect() } }
                        .disabled(busy || !sip.isStarted)
                }

                Section(header: Text("Audio call")) {
                    TextField("Destination SIP URI", text: $destination)
                        .disabled(hasCall || busy)
                    Text(callStatus)
                    Button("Call") { perform { try await call() } }
                        .disabled(busy || !registered || hasCall)
                    Button("Hang up") {
                        perform {
                            guard let accountId, let callId else { return }
                            try await sip.hangupCall(accountId: accountId, callId: callId)
                        }
                    }
                    .disabled(busy || callId == nil)
                }

                if let errorMessage {
                    Section(header: Text("Error")) {
                        Text(errorMessage).foregroundColor(.red)
                    }
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Basic SIP Call")
        }
        .task {
            for await event in sip.events() {
                switch event {
                case let .registration(id, code, reason, active) where id == accountId:
                    registered = active && (200..<300).contains(code)
                    registrationStatus = "Registration: \(code) \(reason), active=\(active)"
                case let .callState(info) where info.accountId == accountId && hasCall:
                    callStatus = "\(info.stateText) — \(info.lastStatusCode) \(info.lastReason)"
                    if info.state == .disconnected {
                        callId = nil
                        hasCall = false
                    } else {
                        callId = info.callId
                    }
                default:
                    break
                }
            }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        busy = true
        errorMessage = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func register() async throws {
        guard let sipPort = UInt16(port), sipPort > 0 else {
            throw SipError.invalidConfiguration("Port must be between 1 and 65535.")
        }
        let account = SipAccountConfiguration(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: sipPort,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            transport: .tcp,
            enableVideoAutoShow: false
        )
        try account.validate()
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
        guard allowed else {
            throw SipError.audioSessionFailure("Allow microphone access in Settings to test calls.")
        }
        try sip.audioSessionManager.configureForCall(isVideo: false)
        try sip.audioSessionManager.activate()
        do {
            try await sip.start(configuration: SipEndpointConfiguration(
                maxCalls: 1,
                enableVideo: false,
                suspendAudioDeviceOnStart: false,
                preferredVideoCodec: nil
            ))
            accountId = account.idURI
            registrationStatus = "Registering…"
            try await sip.setAccount(account, persistToKeychain: false)
            password = ""
        } catch {
            // Keep Disconnect available if startup succeeded but account creation failed.
            sip.audioSessionManager.deactivate()
            throw error
        }
    }

    private func call() async throws {
        guard let accountId else { return }
        let uri = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard uri.hasPrefix("sip:"), uri.contains("@") else {
            throw SipError.invalidConfiguration("Enter a complete URI, e.g. sip:1002@192.168.1.10:5060.")
        }
        hasCall = true
        callStatus = "Calling…"
        do {
            // Call-state events also cover a disconnect that arrives before makeCall returns.
            _ = try await sip.makeCall(accountId: accountId, destinationURI: uri)
        } catch {
            hasCall = false
            callId = nil
            callStatus = "Call failed"
            throw error
        }
    }

    private func disconnect() async throws {
        try await sip.stop()
        sip.audioSessionManager.deactivate()
        accountId = nil
        registered = false
        hasCall = false
        callId = nil
        registrationStatus = "Not registered"
        callStatus = "Idle"
    }
}
