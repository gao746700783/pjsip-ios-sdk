# pjsip-ios-sdk

A reusable, production-oriented iOS SIP/VoIP Swift Package that wraps **PJSUA2** on top of [`laconicman/swift-pjsip`](https://github.com/laconicman/swift-pjsip), modeled after the high-level service architecture of [`VoiSmart/pjsip-android`](https://github.com/VoiSmart/pjsip-android).

## Why This Architecture?

1. **Prebuilt Single-Artifact PJSIP (`swift-pjsip`)**: Depends directly on [`laconicman/swift-pjsip`](https://github.com/laconicman/swift-pjsip) (`>= 0.7.0`), which bundles `libpjproject.a` (`ios-arm64` + `ios-arm64-simulator`) with video (Metal/VideoToolbox + VP8/VP9), native Darwin TLS, Opus, G.729, and SRTP inside one `PJSIP.xcframework`.
2. **Thin Objective-C++ Bridge (`PJSUA2Bridge`)**: As documented in [`laconicman/swift-pjsua`](https://github.com/laconicman/swift-pjsua), Swift/C++ interop cannot subclass C++ classes (`pj::Endpoint`, `pj::Account`, `pj::Call`, `pj::LogWriter`) or override their virtual methods. `PJSUA2Bridge` handles C++ subclassing, translates `pj::Error` C++ exceptions into `NSError`, extracts native iOS `UIView` video windows, and **automatically force-links** the required Apple system frameworks (`AVFoundation`, `AudioToolbox`, `CoreAudio`, `CoreMedia`, `CoreVideo`, `VideoToolbox`, `MetalKit`, `Network`, `Security`, `UIKit`, `Foundation`, `libc++`) with `PJ_AUTOCONF=1` and `PJMEDIA_HAS_VIDEO=1`.
3. **Pure Swift Consumer Layer (`PJSIPiOS`)**: Downstream iOS/SwiftUI apps simply `import PJSIPiOS`—**no global Swift C++ interop**, no bridging header, and no manual framework linking required.

## Architecture Mapping (`pjsip-android` → `pjsip-ios-sdk`)

| `VoiSmart/pjsip-android` | `pjsip-ios-sdk` | Role |
| :--- | :--- | :--- |
| `SipService` + background HandlerThread | `SipService` + `SipWorkerThread` | Single PJLIB-registered POSIX worker thread; non-blocking UI |
| `SipServiceCommand` | `SipService` `async throws` API | Accounts, calls, mute, hold, blind/attended transfer, DTMF, video, codecs |
| `BroadcastEventEmitter` / `BroadcastEventReceiver` | `SipEvent` + `SipEventBroadcaster` (`AsyncStream`) + `SipEventDelegate` | Multi-subscriber Swift Concurrency stream + weak delegate |
| `SipAccountData` + Jetpack Security | `SipAccountConfiguration` + `SipAccountKeychainStore` | `Codable` config with iOS Keychain encrypted persistence |
| `SipAccount` / `SipCall` (SWIG Java) | `PJAccount` / `PJCall` (Obj-C++ in `PJSUA2Bridge`) | Direct PJSUA2 C++ subclasses with deferred call teardown, `UIView` video extraction & RTCP stats |
| `CodecPriority` | `CodecPriority` + `SipVideoCodecParameters` | Audio/video codec priorities + H.264 resolution/fps/bitrate/`packetization-mode` tuning |
| `Logger` / `LoggerDelegate` + `ENABLE_SIP_LOGGING` | `SipLogger` / `SipLogHandler` + `PJLogWriter` | Default `os.Logger` + customizable delegate + native PJSIP log capture |
| Android AudioManager / ConnectivityManager | `SipAudioSessionManager` + `SipNetworkMonitor` + `SipCallKitAdapter` + `SipVideoOrientationObserver` | `AVAudioSession`, `NWPathMonitor` IP recovery, CallKit `setNullDev()` handoff, camera orientation sync |

## Installation (Swift Package Manager)

Add `pjsip-ios-sdk` in Xcode (**File → Add Package Dependencies…**) or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gao746700783/pjsip-ios-sdk", from: "0.1.0")
]
```

Then link the `PJSIPiOS` product to your app target and `import PJSIPiOS`.

> **Privacy Manifest**: `PJSIPiOS` ships `Sources/PJSIPiOS/Resources/PrivacyInfo.xcprivacy` declaring `NSPrivacyAccessedAPICategorySystemBootTime` (`35F9.1`) for PJSIP's `mach_absolute_time` timers, following [`swift-pjsip`'s privacy guidance](https://github.com/laconicman/swift-pjsip).

## Key Features Included

- **Account & Transport**: Multi-account support, UDP / TCP / Darwin TLS, optional TLS server certificate verification (`verifySipServerCert` + `caListFilePath`), SRTP (`disabled` / `optional` / `mandatory`), ICE, and DNS SRV (RFC 3263) with per-account `srvDomain`.
- **Call Control**: Outgoing, incoming, and direct calls (`makeDirectCall`), silent calls, fixed SIP `Call-ID` header, custom SIP headers, mute/unmute, hold/unhold, hold/hangup all calls, call reconnection (`reinvite` with contact/via/media refresh), blind transfer (`xfer`), attended transfer (`xferReplaces`), and RFC 2833 DTMF.
- **Video & Hardware Gateway Compatibility**: Native iOS `UIView` extraction for both local camera preview and remote video (`SipEvent.videoMediaReady`), video mute/unmute, camera switching, H.264 encoder tuning (`SipVideoCodecParameters.h264Standard`: `640×480 @ 15fps`, `512kbps`, `packetization-mode=1`), and automatic `UIDevice` orientation rotation (`SipVideoOrientationObserver` → `setCaptureOrient`).
- **iOS Platform Integration**: CallKit-safe startup audio suspension (`suspendAudioDeviceOnStart = true` → `setNullDev()`), `SipAudioSessionManager` (`AVAudioSession` + `setSpeakerEnabled`), `SipNetworkMonitor` (`NWPathMonitor` → `handleIpChange`), `SipAccountKeychainStore` (Keychain), and an optional `SipCallKitAdapter` (`CXProvider` + `CXCallController`).

## Quick Start

See [`Examples/QuickStartExample.swift`](Examples/QuickStartExample.swift) for a complete Swift Concurrency + Video `UIView` + CallKit integration flow.

## Licensing

- This wrapper library (`pjsip-ios-sdk`) is licensed under the Apache-2.0 License (matching [`VoiSmart/pjsip-android`](https://github.com/VoiSmart/pjsip-android)).
- Upstream prebuilt binaries from [`laconicman/swift-pjsip`](https://github.com/laconicman/swift-pjsip) include **PJSIP** (GPLv2+ / Teluu commercial license), **bcg729** (GPLv3 / Belledonne commercial license), **libopus** (BSD-3-Clause), and **libvpx** (BSD-3-Clause). Ensure commercial or GPL compliance before shipping to the App Store.
