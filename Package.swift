// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwingMusic",
    platforms: [.iOS(.v16)],
    products: [
        // Changed to .executable so xcodebuild can create an .app/IPA
        .executable(name: "SwingMusicApp", targets: ["SwingMusic"]),
    ],
    dependencies: [
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwingMusic",
            dependencies: [
                .product(name: "Kingfisher", package: "Kingfisher"),
            ],
            path: ".",
            // Added "App/Info.plist" to exclude to fix the duplicate rule error
            exclude: ["App/Info.plist", "Package.swift"], 
            sources: ["App", "Core", "Network", "Auth", "Features", "UIComponents"],
            resources: [.process("App/Info.plist")]
        ),
        .testTarget(
            name: "SwingMusicTests",
            dependencies: ["SwingMusic"],
            path: "Tests"
        ),
    ]
)
