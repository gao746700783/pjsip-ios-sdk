// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pjsip-ios-sdk",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "PJSIPiOS",
            targets: ["PJSIPiOS"]
        ),
        .library(
            name: "PJSUA2Bridge",
            targets: ["PJSUA2Bridge"]
        )
    ],
    dependencies: [
        // Single prebuilt PJSIP.xcframework vending both PJSIP (C) and PJSUA2 (C++) modules.
        // See: https://github.com/laconicman/swift-pjsip
        .package(url: "https://github.com/laconicman/swift-pjsip", from: "0.7.0")
    ],
    targets: [
        // Objective-C++ bridge that subclasses PJSUA2 C++ classes (pj::Endpoint, pj::Account,
        // pj::Call, pj::LogWriter), translates C++ exceptions (pj::Error) into NSError, extracts
        // native iOS UIView video windows, and force-links required Apple system frameworks so
        // downstream Swift targets do not need C++ interop enabled or manual linker flags.
        .target(
            name: "PJSUA2Bridge",
            dependencies: [
                .product(name: "PJSIP", package: "swift-pjsip")
            ],
            path: "Sources/PJSUA2Bridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .define("PJ_AUTOCONF", to: "1"),
                .define("PJMEDIA_HAS_VIDEO", to: "1")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
                .linkedLibrary("c++")
            ]
        ),
        // High-level, idiomatic Swift VoIP SDK inspired by VoiSmart/pjsip-android.
        .target(
            name: "PJSIPiOS",
            dependencies: ["PJSUA2Bridge"],
            path: "Sources/PJSIPiOS",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("CallKit")
            ]
        ),
        .testTarget(
            name: "PJSIPiOSTests",
            dependencies: ["PJSIPiOS"],
            path: "Tests/PJSIPiOSTests"
        )
    ],
    cxxLanguageStandard: .gnucxx14
)
