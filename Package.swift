// swift-tools-version: 5.9
// Replaces all build.gradle.kts files from the Android project.
// iOS 16 minimum = Android minSdk 26 equivalent feature set.

import PackageDescription

let package = Package(
    name: "SwingMusic",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SwingMusic", targets: ["SwingMusic"]),
    ],
    dependencies: [
        // Coil → Kingfisher for async image loading + disk cache
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "SwingMusic",
            dependencies: [
                .product(name: "Kingfisher", package: "Kingfisher"),
            ],
            path: ".",
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

/*
 ╔══════════════════════════════════════╦═════════════════════════════════════════╗
 ║ Android                              ║ iOS                                     ║
 ╠══════════════════════════════════════╬═════════════════════════════════════════╣
 ║ Retrofit + OkHttp                    ║ URLSession async/await (built-in)        ║
 ║ Gson @SerializedName                 ║ Codable + CodingKeys (built-in)          ║
 ║ Room database                        ║ SwiftData / CoreData (built-in)          ║
 ║ DataStore Preferences                ║ UserDefaults + Keychain (built-in)       ║
 ║ Hilt dependency injection            ║ @EnvironmentObject (built-in)            ║
 ║ ExoPlayer / Media3                   ║ AVPlayer (built-in)                      ║
 ║ MediaSessionCompat                   ║ MPNowPlayingInfoCenter (built-in)        ║
 ║ WorkManager (token refresh)          ║ BGAppRefreshTask (built-in)              ║
 ║ Coil image loading                   ║ Kingfisher (external, same API surface)  ║
 ║ Jetpack Compose                      ║ SwiftUI (built-in)                       ║
 ║ StateFlow + ViewModel                ║ @Published + ObservableObject (built-in) ║
 ║ NavHost + Compose Destinations       ║ NavigationStack + TabView (built-in)     ║
 ║ Paging 3                             ║ Manual offset pagination                 ║
 ║ QrScanner library                    ║ AVCaptureSession + VisionKit (built-in)  ║
 ║ Timber logging                       ║ os.Logger (built-in)                     ║
 ║ ChuckerInterceptor                   ║ (dev-only, omitted)                      ║
 ╠══════════════════════════════════════╬═════════════════════════════════════════╣
 ║ TLS / Security                                                                  ║
 ╠══════════════════════════════════════╬═════════════════════════════════════════╣
 ║ OkHttp default TLS                   ║ TLS 1.3 minimum (URLSessionConfig)       ║
 ║ No HSTS enforcement client-side      ║ HSTS enforced by server (CF/nginx/Caddy) ║
 ║ HTTP possible without warning        ║ HTTP opt-in only, warning sheet + banner ║
 ║ No blanket ATS exception needed      ║ NSAllowsLocalNetworking for RFC-1918     ║
 ╚══════════════════════════════════════╩═════════════════════════════════════════╝

 Connection model:
   Any HTTPS endpoint works — Cloudflare Tunnel, nginx, Caddy, Traefik, direct HTTPS.
   Local network (192.168.x.x, 10.x.x.x, *.local) works automatically via
   NSAllowsLocalNetworking without a TLS cert.
   HTTP over internet: user must explicitly enable in Settings > Advanced,
   acknowledge the ATS warning sheet, and accept the persistent InsecureBanner.
*/
