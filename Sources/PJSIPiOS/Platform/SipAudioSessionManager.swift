import AVFoundation
import Foundation

public enum SipAudioRoute: Sendable {
    case earpiece
    case speaker
}

/// Manages `AVAudioSession` lifecycle and audio routing for VoIP calls.
/// Designed to work seamlessly both standalone and with Apple CallKit's
/// `provider(_:didActivate:)` / `provider(_:didDeactivate:)` handoff.
public final class SipAudioSessionManager: @unchecked Sendable {
    private let session: AVAudioSession
    private let logger: SipLogger

    public init(session: AVAudioSession = .sharedInstance(), logger: SipLogger = .shared) {
        self.session = session
        self.logger = logger
    }

    /// Configures `AVAudioSession` for VoIP voice or video calls without activating it
    /// (CallKit activates the session when the system grants audio).
    public func configureForCall(isVideo: Bool, preferredSampleRate: Double = 16000) throws {
        do {
            let mode: AVAudioSession.Mode = isVideo ? .videoChat : .voiceChat
            let options: AVAudioSession.CategoryOptions = [
                .allowBluetooth,
                .allowBluetoothA2DP
            ]
            try session.setCategory(.playAndRecord, mode: mode, options: options)
            try session.setPreferredSampleRate(preferredSampleRate)
            try session.setPreferredIOBufferDuration(0.02)
            logger.debug("AudioSession", "Configured category=.playAndRecord mode=\(mode.rawValue)")
        } catch {
            throw SipError.audioSessionFailure(error.localizedDescription)
        }
    }

    /// Activates the audio session directly (use when NOT using CallKit).
    public func activate() throws {
        do {
            try session.setActive(true, options: [])
            logger.debug("AudioSession", "Activated AVAudioSession")
        } catch {
            throw SipError.audioSessionFailure(error.localizedDescription)
        }
    }

    /// Deactivates the audio session and notifies other apps to resume audio.
    public func deactivate() {
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            logger.debug("AudioSession", "Deactivated AVAudioSession")
        } catch {
            logger.warning("AudioSession", "Failed to deactivate AVAudioSession: \(error.localizedDescription)")
        }
    }

    /// Switches output audio route between receiver (earpiece) and speakerphone.
    public func setAudioRoute(_ route: SipAudioRoute) throws {
        do {
            switch route {
            case .earpiece:
                try session.overrideOutputAudioPort(.none)
            case .speaker:
                try session.overrideOutputAudioPort(.speaker)
            }
            logger.debug("AudioSession", "Switched audio route to \(route)")
        } catch {
            throw SipError.audioSessionFailure(error.localizedDescription)
        }
    }
}
