import Foundation
import UIKit

/// Observes `UIDevice.orientationDidChangeNotification` and automatically updates PJSIP's
/// camera capture orientation so remote peers see upright video during portrait/landscape calls.
@MainActor
public final class SipVideoOrientationObserver {
    private unowned let sipService: SipService
    private let captureDeviceId: Int32
    private var observerToken: NSObjectProtocol?

    public init(sipService: SipService, captureDeviceId: Int32 = -1) {
        self.sipService = sipService
        self.captureDeviceId = captureDeviceId
    }

    deinit {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    public func start() {
        guard observerToken == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        applyCurrentOrientation()

        observerToken = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyCurrentOrientation()
            }
        }
    }

    public func stop() {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
            observerToken = nil
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    public func applyCurrentOrientation() {
        guard let orient = mapOrientation(UIDevice.current.orientation) else { return }
        let devId = captureDeviceId
        Task { [weak sipService] in
            try? await sipService?.setVideoCaptureOrientation(orient, captureDeviceId: devId)
        }
    }

    private func mapOrientation(_ deviceOrientation: UIDeviceOrientation) -> SipVideoOrientation? {
        switch deviceOrientation {
        case .portrait:
            return .rotate90
        case .portraitUpsideDown:
            return .rotate270
        case .landscapeLeft:
            return .natural
        case .landscapeRight:
            return .rotate180
        default:
            return nil
        }
    }
}
