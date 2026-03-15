# SwingMusic iOS — Build Instructions

## Why there is both a Package.swift and an .xcodeproj

Swift Package Manager alone cannot produce a signed `.ipa` or an Xcode
archive. `xcodebuild archive` requires a `.xcodeproj` with a named scheme
and an app target that declares the bundle ID, Info.plist path, and signing
identity. The `Package.swift` is used by Xcode's SPM integration (for
dependency resolution and `swift build` checks). The `.xcodeproj` is what
you actually build and archive from.

## Build commands

### Option A — Xcode GUI (recommended)
1. `open SwingMusicApp.xcodeproj`
2. Select the **SwingMusicApp** scheme (top bar)
3. Product → Archive

### Option B — xcodebuild CLI (unsigned, for CI)
```bash
xcodebuild archive \
  -project SwingMusicApp.xcodeproj \
  -scheme SwingMusicApp \
  -destination generic/platform=iOS \
  -archivePath ./build/SwingMusicApp.xcarchive \
  CODE_SIGNING_ALLOWED=NO
```

### Option C — xcodebuild CLI (signed)
```bash
xcodebuild archive \
  -project SwingMusicApp.xcodeproj \
  -scheme SwingMusicApp \
  -destination generic/platform=iOS \
  -archivePath ./build/SwingMusicApp.xcarchive \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  DEVELOPMENT_TEAM="YOUR_TEAM_ID"
```

### Option D — swift build (compile check only, no .app)
```bash
swift build
```

## What was wrong with the previous build

| Problem | Cause | Fix |
|---|---|---|
| "scheme SwingMusicApp not found" | Package was named `SwingMusic`, scheme was `SwingMusicApp` | Added `.xcodeproj` with explicit scheme matching the archive command |
| "multiple rules emit the same output" | `Info.plist` was listed as both an SPM resource and referenced by Xcode | Removed from SPM resources; Xcode reads it via `INFOPLIST_FILE` build setting only |
| SPM package can't produce .ipa | SPM produces libraries/executables, not signed app bundles | `.xcodeproj` app target wraps the Swift sources and adds signing/bundle/plist |

## Before submitting to App Store

1. Set your `DEVELOPMENT_TEAM` in the xcodeproj build settings
2. Change `PRODUCT_BUNDLE_IDENTIFIER` to your registered bundle ID
3. Add your signing certificate
4. Replace the QR scanner stub in `ServerPairingView` with real
   `AVCaptureSession` + `VisionKit` implementation
5. Register `com.swingmusic.ios.tokenRefresh` as a BGTaskSchedulerPermittedIdentifier
   and add the `BGAppRefreshTask` registration in `SwingMusicApp.init()`
