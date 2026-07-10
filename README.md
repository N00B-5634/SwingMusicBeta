# ⚠️ ARCHIVED: Swing Music iOS Client

> **⚠️ This repository is archived and no longer maintained.**
>
> **Reason**: The project fell out of my regular use. Swing Music has introduced a paywall ($4.08/month) to use the server, which I find unacceptable. I believe they are taking the same path as Plex - closing the source and jacking up prices, making it harder to know what they're doing with user data and the software itself.
>
> I no longer endorse or use this software.

---

## Historical Context

This was a native iOS client for **[Swing Music](https://github.com/swingmx/swingmusic)** - a self-hosted music streaming server.

> **Note**: This was an unofficial iOS client. The official Android client was available at [swingmx/android](https://github.com/swingmx/android).

## Original Features

- **Authentication**: Password login, QR code scanning, and guest access
- **Browsing**: Explore music by folders, albums, and artists
- **Search**: Find tracks, albums, and artists with top results
- **Playback**: Full playback controls with queue management
- **Favorites**: Save favorite tracks, albums, and artists
- **Playlists**: Create and manage custom playlists
- **Recently Played/Added**: Track your listening history and new additions
- **Lyrics**: View synced lyrics from lrclib.net or your Swing Music server
- **Theming**: Custom theme system with dark mode support
- **Multi-user Support**: Connect to shared Swing Music servers

## Original Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Original Installation

### Using Xcode

1. Clone this repository
2. Open `SwingMusicApp.xcodeproj` in Xcode
3. Select the "SwingMusicApp" scheme
4. Build and run on your device or simulator

### Command Line Build

```bash
xcodebuild archive \
  -project SwingMusicApp.xcodeproj \
  -scheme SwingMusicApp \
  -destination generic/platform=iOS \
  -archivePath ./build/SwingMusicApp.xcarchive \
  CODE_SIGNING_ALLOWED=NO
```

## Alternatives

If you're looking for self-hosted music streaming solutions that remain open-source and free, consider:

- **[Navidrome](https://github.com/navidrome/navidrome)** - Open-source music streaming server
- **[Subsonic](https://github.com/subsonic/subsonic)** - Free media streaming server
- **[Jellyfin](https://github.com/jellyfin/jellyfin)** - Free Software Media System
- **[Mopidy](https://github.com/mopidy/mopidy)** - Extensible music server
- **[Airsonic](https://github.com/airsonic/airsonic)** - Fork of Subsonic with additional features

## Original Credits

- **Swing Music Server**: [swingmx/swingmusic](https://github.com/swingmx/swingmusic)
- **Official Android Client**: [swingmx/android](https://github.com/swingmx/android)
- **Kingfisher**: Image loading library by [onevcat/Kingfisher](https://github.com/onevcat/Kingfisher)

## License

This project was open source and available under the MIT License.

---

*Archived by Ribhav (N00B-5634) - March 2025*
