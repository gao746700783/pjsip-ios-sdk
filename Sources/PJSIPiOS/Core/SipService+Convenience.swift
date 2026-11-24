import Foundation

public extension SipService {
    /// Convenience method mirroring `PJSIPWrapper.setSpeakerEnabled(_:)` to toggle speakerphone.
    func setSpeakerEnabled(_ enabled: Bool) throws {
        try audioSessionManager.setAudioRoute(enabled ? .speaker : .earpiece)
    }
}
