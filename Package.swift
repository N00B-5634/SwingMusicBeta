// swift-tools-version: 5.9
//
// SwingMusic iOS — Swift Package Manifest
//
// HOW TO BUILD:
//
//   Xcode (recommended):
//     Open SwingMusicApp.xcodeproj → select "SwingMusicApp" scheme → Archive
//
//   xcodebuild CLI:
//     xcodebuild archive \
//       -project SwingMusicApp.xcodeproj \
//       -scheme SwingMusicApp \
//       -destination generic/platform=iOS \
//       -archivePath ./build/SwingMusicApp.xcarchive \
//       CODE_SIGNING_ALLOWED=NO
//
//   swift build (library check only, no .ipa):
//     swift build
//
// WHY xcodeproj IS NEEDED:
//   Pure SPM packages cannot produce .ipa files. xcodebuild needs a
//   .xcodeproj with an explicit app target that declares the bundle ID,
//   signing identity, and INFOPLIST_FILE path. The xcodeproj wraps this
//   package as a local dependency and adds those settings.
//
// WHY Info.plist IS NOT A RESOURCE HERE:
//   Info.plist must be referenced by the Xcode app target's INFOPLIST_FILE
//   build setting, NOT embedded as an SPM resource. Including it as
//   .process("App/Info.plist") causes the Xcode "multiple rules emit the
//   same output file" duplicate error that was seen in the build log.

import PackageDescription

let package = Package(
    name: "SwingMusicApp",
    platforms: [.iOS(.v16)],
    products: [
        // Library consumed by the Xcode app target via local package reference
        .library(name: "SwingMusicCore", targets: ["SwingMusicCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "SwingMusicCore",
            dependencies: [
                .product(name: "Kingfisher", package: "Kingfisher"),
            ],
            path: "Sources"
            // No resources — Info.plist handled by Xcode app target
        ),
        .testTarget(
            name: "SwingMusicTests",
            dependencies: ["SwingMusicCore"],
            path: "Tests"
        ),
    ]
)
