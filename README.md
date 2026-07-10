# Swing Music iOS Client

A native iOS client for **[Swing Music](https://github.com/swingmx/swingmusic)** - a self-hosted music streaming server.

> **Note**: This is an unofficial iOS client. The official Android client is available at [swingmx/android](https://github.com/swingmx/android).

## Project Status

This project is currently **not actively maintained**. I stopped using it when Swing Music introduced a subscription model for server features. The code remains available for reference or for anyone who wants to fork and continue development.

## Features

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

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Using Xcode (Recommended)

1. Clone this repository
2. Open `SwingMusicApp.xcodeproj` in Xcode
3. Select the "SwingMusicApp" scheme
4. Build and run on your device or simulator

### Command Line Build

```bash
# Archive for distribution
xcodebuild archive \
  -project SwingMusicApp.xcodeproj \
  -scheme SwingMusicApp \
  -destination generic/platform=iOS \
  -archivePath ./build/SwingMusicApp.xcarchive \
  CODE_SIGNING_ALLOWED=NO

# Or build the Swift package (library only, no .ipa)
swift build
```

## Configuration

### Connecting to Your Server

1. Launch the app
2. Enter your Swing Music server URL (e.g., `https://music.example.com` or `http://localhost:1970`)
3. Authenticate using one of the available methods:
   - **Password**: Enter username and password
   - **QR Code**: Scan the QR code from your Swing Music web interface (Settings > Pair device)
   - **Guest Access**: If enabled on your server, enter as a guest

### Server Setup

If you don't have a Swing Music server yet, you can set one up:

**Quick Install (Linux/MacOS):**
```bash
curl -fsSL https://setup.swingmx.com | bash
```

**Docker Compose:**
```yaml
services:
  swingmusic:
    image: ghcr.io/swingmx/swingmusic:latest
    container_name: swingmusic
    ports:
      - "1970:1970"
    volumes:
      - /path/to/music:/music
      - /path/to/config:/config
    environment:
      - SWINGMUSIC_PORT=1970
      - SWINGMUSIC_DEVICE_NAME=YourServerName
    restart: unless-stopped
```

The server will be available at `http://localhost:1970` by default.

### Allowing Insecure HTTP (Development Only)

For local development with HTTP:
1. Go to Settings in the app
2. Enable "Allow insecure HTTP"
3. Confirm the security warning

**Note**: iOS requires HTTPS by default (ATS - App Transport Security). Use a valid certificate (Cloudflare Tunnel provides free certificates) or connect over your local network.

## Project Structure

```
SwingMusicBeta/
├── App/                    # App entry point and main views
│   └── SwingMusicApp.swift # App structure and root views
├── Auth/                   # Authentication state management
│   └── AuthState.swift     # Authentication logic and state
├── Core/                   # Data models and core types
│   └── Models.swift        # Track, Album, Artist, and other data models
├── Features/               # Feature-specific views and logic
│   └── Player/             # Player state and views
│       ├── PlayerState.swift
│       └── PlayerViews.swift
├── Network/                # API client and network layer
│   └── SwingAPIClient.swift # Main API client with all endpoints
├── UIComponents/           # Reusable UI components
│   ├── Components/        # Custom SwiftUI components
│   └── Theme/              # App theming and styling
├── Package.swift           # Swift Package Manager manifest
└── App/                    # Xcode project resources
    ├── Assets.xcassets/    # App icons and assets
    └── Info.plist           # App configuration
```

## Server Compatibility

This client is designed to work with **[Swing Music by swingmx](https://github.com/swingmx/swingmusic)**.

### API Endpoints Used

The client implements the Swing Music API:
- Authentication: `/auth/users`, `/auth/login`, `/auth/pair`, `/auth/refresh`, `/auth/logout`
- Folders: `/folder`
- Albums: `/album`, `/album/{hash}/tracks`, `/getall/albums`
- Artists: `/artist/{hash}`, `/artist/{hash}/similar`, `/artist/{hash}/tracks`, `/getall/artists`
- Search: `/search/top`, `/search/`
- Favorites: `/favorites`, `/favorites/add`, `/favorites/remove`
- Playlists: `/playlists`, `/playlists/{id}`, `/playlists/new`, `/playlists/{id}/add`
- Recently Played: `/nothome/recents/played`, `/nothome/recents/added`
- Streaming: `/file/{hash}/legacy`
- Lyrics: `/lyrics` (server), lrclib.net API (external)
- Colors: `/colors/album/{hash}`

## Security

- All network requests use HTTPS by default
- TLS certificates are accepted for self-signed certs (intentional for self-hosted servers)
- User explicitly trusts the server by entering its URL
- Sensitive data (tokens) stored securely
- App Transport Security (ATS) enforced with user override option for local development

## Troubleshooting

### Connection Issues

- **Cannot connect to server**: Verify the server is running and the URL is correct. Default port is 1970.
- **SSL errors**: Use a valid certificate or enable "Allow insecure HTTP" for local development
- **403 Forbidden (Cloudflare)**: Disable "Browser Integrity Check" in Cloudflare Tunnel settings
- **404 errors**: Ensure you're using the correct server URL (just the host, no path)

### Build Issues

- **Missing dependencies**: Run `swift package resolve` to fetch dependencies
- **Code signing errors**: Use `CODE_SIGNING_ALLOWED=NO` for development builds
- **Xcode version**: Ensure you're using Xcode 15.0+ with Swift 5.9+

## Contributing

Contributions are welcome! Feel free to fork this repository and submit pull requests.

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

This project is open source and available under the MIT License.

## Credits

- **Swing Music Server**: [swingmx/swingmusic](https://github.com/swingmx/swingmusic)
- **Official Android Client**: [swingmx/android](https://github.com/swingmx/android)
- **Kingfisher**: Image loading library by [onevcat/Kingfisher](https://github.com/onevcat/Kingfisher)

## Resources

- [Swing Music Official Website](https://swingmx.com)
- [Swing Music Documentation](https://swingmx.com/guide/introduction.html)
