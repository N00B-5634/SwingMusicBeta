import Foundation

// MARK: - Track (from TrackDto.kt + Track.kt domain model)
struct Track: Identifiable, Codable, Hashable {
    let trackHash: String
    let title: String
    let album: String
    let albumHash: String
    let duration: Int
    let bitrate: Int
    let filepath: String
    let folder: String
    let image: String
    var isFavorite: Bool
    let disc: Int
    let trackNumber: Int
    let trackArtists: [TrackArtist]
    let albumTrackArtists: [TrackArtist]

    var id: String { trackHash }

    var durationFormatted: String {
        let h = duration / 3600
        let m = (duration % 3600) / 60
        let s = duration % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var formattedAlbumDuration: String {
        let totalMinutes = (duration + 30) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        var result = ""
        if hours > 0 { result += "\(hours)hr\(hours > 1 ? "s" : "")" }
        if minutes > 0 { result += "\(result.isEmpty ? "" : " ")\(minutes)min" }
        return result.isEmpty ? "0min" : result
    }

    var artistNames: String { trackArtists.map(\.name).joined(separator: ", ") }

    enum CodingKeys: String, CodingKey {
        case trackHash = "trackhash"
        case title, album, bitrate, filepath, folder, image, disc, duration
        case albumHash = "albumhash"
        case isFavorite = "is_favorite"
        case trackNumber = "track"
        case trackArtists = "artists"
        case albumTrackArtists = "albumartists"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trackHash        = try c.decodeIfPresent(String.self,       forKey: .trackHash)        ?? ""
        title            = try c.decodeIfPresent(String.self,       forKey: .title)            ?? ""
        album            = try c.decodeIfPresent(String.self,       forKey: .album)            ?? ""
        albumHash        = try c.decodeIfPresent(String.self,       forKey: .albumHash)        ?? ""
        duration         = try c.decodeIfPresent(Int.self,          forKey: .duration)         ?? 0
        bitrate          = try c.decodeIfPresent(Int.self,          forKey: .bitrate)          ?? 0
        filepath         = try c.decodeIfPresent(String.self,       forKey: .filepath)         ?? ""
        folder           = try c.decodeIfPresent(String.self,       forKey: .folder)           ?? ""
        image            = try c.decodeIfPresent(String.self,       forKey: .image)            ?? ""
        isFavorite       = try c.decodeIfPresent(Bool.self,         forKey: .isFavorite)       ?? false
        disc             = try c.decodeIfPresent(Int.self,          forKey: .disc)             ?? 1
        trackNumber      = try c.decodeIfPresent(Int.self,          forKey: .trackNumber)      ?? 1
        trackArtists     = try c.decodeIfPresent([TrackArtist].self, forKey: .trackArtists)    ?? []
        albumTrackArtists = try c.decodeIfPresent([TrackArtist].self, forKey: .albumTrackArtists) ?? []
    }
}

// MARK: - TrackArtist (from TrackArtistDto.kt)
struct TrackArtist: Codable, Hashable {
    let artistHash: String
    let name: String
    let image: String

    enum CodingKeys: String, CodingKey {
        case artistHash = "artisthash"
        case name, image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artistHash = try c.decodeIfPresent(String.self, forKey: .artistHash) ?? ""
        name       = try c.decodeIfPresent(String.self, forKey: .name)       ?? ""
        image      = try c.decodeIfPresent(String.self, forKey: .image)      ?? ""
    }
}

// MARK: - Artist (from ArtistDto.kt)
struct Artist: Identifiable, Codable, Hashable {
    let artistHash: String
    let name: String
    let image: String
    let colors: [String]
    let helpText: String

    var id: String { artistHash }

    // helpText mirrors Android's replace("minutes", "mins")
    var displayHelpText: String { helpText.replacingOccurrences(of: "minutes", with: "mins") }

    enum CodingKeys: String, CodingKey {
        case artistHash = "artisthash"
        case name, image, colors
        case helpText = "help_text"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artistHash = try c.decodeIfPresent(String.self,    forKey: .artistHash) ?? ""
        name       = try c.decodeIfPresent(String.self,    forKey: .name)       ?? ""
        image      = try c.decodeIfPresent(String.self,    forKey: .image)      ?? ""
        colors     = try c.decodeIfPresent([String].self,  forKey: .colors)     ?? []
        helpText   = try c.decodeIfPresent(String.self,    forKey: .helpText)   ?? ""
    }
}

// MARK: - ArtistExpanded (from ArtistExpandedDto.kt)
struct ArtistExpanded: Codable {
    let artistHash: String
    let name: String
    let image: String
    let albumCount: Int
    let trackCount: Int
    let duration: Int
    let color: String
    let isFavorite: Bool
    let genres: [Genre]

    enum CodingKeys: String, CodingKey {
        case artistHash = "artisthash"
        case name, image, color, duration, genres
        case albumCount = "albumcount"
        case trackCount = "trackcount"
        case isFavorite = "is_favorite"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artistHash = try c.decodeIfPresent(String.self,   forKey: .artistHash) ?? ""
        name       = try c.decodeIfPresent(String.self,   forKey: .name)       ?? ""
        image      = try c.decodeIfPresent(String.self,   forKey: .image)      ?? ""
        albumCount = try c.decodeIfPresent(Int.self,      forKey: .albumCount) ?? 0
        trackCount = try c.decodeIfPresent(Int.self,      forKey: .trackCount) ?? 0
        duration   = try c.decodeIfPresent(Int.self,      forKey: .duration)   ?? 0
        color      = try c.decodeIfPresent(String.self,   forKey: .color)      ?? ""
        isFavorite = try c.decodeIfPresent(Bool.self,     forKey: .isFavorite) ?? false
        genres     = try c.decodeIfPresent([Genre].self,  forKey: .genres)     ?? []
    }
}

// MARK: - Album (from AlbumDto.kt)
struct Album: Identifiable, Codable, Hashable {
    let albumHash: String
    let title: String
    let image: String
    let date: Int
    let colors: [String]
    let helpText: String
    let versions: [String]
    let albumArtists: [Artist]

    var id: String { albumHash }

    var yearString: String {
        let ts = Int64(date)
        guard ts > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let cal = Calendar.current
        return String(cal.component(.year, from: date))
    }

    enum CodingKeys: String, CodingKey {
        case albumHash = "albumhash"
        case title, image, date, colors, versions
        case helpText    = "help_text"
        case albumArtists = "albumartists"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albumHash    = try c.decodeIfPresent(String.self,   forKey: .albumHash)    ?? ""
        title        = try c.decodeIfPresent(String.self,   forKey: .title)        ?? ""
        image        = try c.decodeIfPresent(String.self,   forKey: .image)        ?? ""
        date         = try c.decodeIfPresent(Int.self,      forKey: .date)         ?? 0
        colors       = try c.decodeIfPresent([String].self, forKey: .colors)       ?? []
        helpText     = try c.decodeIfPresent(String.self,   forKey: .helpText)     ?? ""
        versions     = try c.decodeIfPresent([String].self, forKey: .versions)     ?? []
        albumArtists = try c.decodeIfPresent([Artist].self, forKey: .albumArtists) ?? []
    }
}

// MARK: - AlbumInfo (from AlbumInfoDto.kt)
struct AlbumInfo: Codable {
    let albumHash: String
    let title: String
    let image: String
    let date: Int
    let duration: Int
    let trackCount: Int
    var isFavorite: Bool
    let color: String
    let genres: [Genre]
    let albumArtists: [Artist]
    let type: String
    let ogTitle: String

    var formattedDuration: String {
        let totalMinutes = (duration + 30) / 60
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        var result = ""
        if h > 0 { result += "\(h)hr\(h > 1 ? "s" : "")" }
        if m > 0 { result += "\(result.isEmpty ? "" : " ")\(m)min" }
        return result.isEmpty ? "0min" : result
    }

    enum CodingKeys: String, CodingKey {
        case albumHash = "albumhash"
        case title, image, date, duration, color, genres, type
        case trackCount  = "trackcount"
        case isFavorite  = "is_favorite"
        case albumArtists = "albumartists"
        case ogTitle     = "og_title"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albumHash    = try c.decodeIfPresent(String.self,   forKey: .albumHash)    ?? ""
        title        = try c.decodeIfPresent(String.self,   forKey: .title)        ?? ""
        image        = try c.decodeIfPresent(String.self,   forKey: .image)        ?? ""
        date         = try c.decodeIfPresent(Int.self,      forKey: .date)         ?? 0
        duration     = try c.decodeIfPresent(Int.self,      forKey: .duration)     ?? 0
        trackCount   = try c.decodeIfPresent(Int.self,      forKey: .trackCount)   ?? 0
        isFavorite   = try c.decodeIfPresent(Bool.self,     forKey: .isFavorite)   ?? false
        color        = try c.decodeIfPresent(String.self,   forKey: .color)        ?? ""
        genres       = try c.decodeIfPresent([Genre].self,  forKey: .genres)       ?? []
        albumArtists = try c.decodeIfPresent([Artist].self, forKey: .albumArtists) ?? []
        type         = try c.decodeIfPresent(String.self,   forKey: .type)         ?? ""
        ogTitle      = try c.decodeIfPresent(String.self,   forKey: .ogTitle)      ?? ""
    }
}

struct AlbumWithInfo: Codable {
    let albumInfo: AlbumInfo
    let tracks: [Track]
    let copyright: String
    enum CodingKeys: String, CodingKey { case albumInfo = "info", tracks, copyright }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albumInfo  = try c.decode(AlbumInfo.self,  forKey: .albumInfo)
        tracks     = try c.decodeIfPresent([Track].self,  forKey: .tracks)    ?? []
        copyright  = try c.decodeIfPresent(String.self,  forKey: .copyright)  ?? ""
    }
}

// MARK: - AlbumsAndAppearances (from AlbumsAndAppearancesDto.kt)
struct AlbumsAndAppearances: Codable {
    let albums: [Album]
    let appearances: [Album]
    let compilations: [Album]
    let singlesAndEps: [Album]
    let artistName: String
    enum CodingKeys: String, CodingKey {
        case albums, appearances, compilations
        case singlesAndEps = "singles_and_eps"
        case artistName    = "artistname"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albums        = try c.decodeIfPresent([Album].self, forKey: .albums)        ?? []
        appearances   = try c.decodeIfPresent([Album].self, forKey: .appearances)   ?? []
        compilations  = try c.decodeIfPresent([Album].self, forKey: .compilations)  ?? []
        singlesAndEps = try c.decodeIfPresent([Album].self, forKey: .singlesAndEps) ?? []
        artistName    = try c.decodeIfPresent(String.self,  forKey: .artistName)    ?? ""
    }
}

struct ArtistInfo: Codable {
    let artist: ArtistExpanded
    let albumsAndAppearances: AlbumsAndAppearances
    let tracks: [Track]
    enum CodingKeys: String, CodingKey {
        case artist
        case albumsAndAppearances = "albums"
        case tracks
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist                = try c.decode(ArtistExpanded.self,        forKey: .artist)
        albumsAndAppearances  = try c.decode(AlbumsAndAppearances.self,  forKey: .albumsAndAppearances)
        tracks                = try c.decodeIfPresent([Track].self,      forKey: .tracks) ?? []
    }
}

// MARK: - Folder (from FolderDto.kt)
struct Folder: Identifiable, Codable, Hashable {
    let name: String
    let path: String
    let trackCount: Int
    let folderCount: Int
    let isSym: Bool

    var id: String { path }
    var isEmpty: Bool { trackCount == 0 && folderCount == 0 }

    var trackCountText: String {
        trackCount <= 1 ? "\(trackCount) Track" : "\(trackCount) Tracks"
    }
    var folderCountText: String {
        folderCount <= 1 ? "\(folderCount) Folder" : "\(folderCount) Folders"
    }

    enum CodingKeys: String, CodingKey {
        case name, path
        case trackCount  = "count"
        case folderCount = "foldercount"
        case isSym       = "is_sym"
    }

    init(name: String, path: String, trackCount: Int, folderCount: Int, isSym: Bool) {
        self.name = name; self.path = path
        self.trackCount = trackCount; self.folderCount = folderCount; self.isSym = isSym
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name        = try c.decodeIfPresent(String.self, forKey: .name)        ?? ""
        path        = try c.decodeIfPresent(String.self, forKey: .path)        ?? ""
        trackCount  = (try? c.decodeIfPresent(Int.self,  forKey: .trackCount)) ?? 0
        folderCount = try c.decodeIfPresent(Int.self,    forKey: .folderCount) ?? 0
        isSym       = try c.decodeIfPresent(Bool.self,   forKey: .isSym)       ?? false
    }
}

struct FoldersAndTracks: Codable {
    let folders: [Folder]
    let tracks: [Track]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        tracks  = try c.decodeIfPresent([Track].self,  forKey: .tracks)  ?? []
    }
    enum CodingKeys: String, CodingKey { case folders, tracks }
}

struct RootDirs: Codable {
    let rootDirs: [String]
    enum CodingKeys: String, CodingKey { case rootDirs = "root_dirs" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rootDirs = try c.decodeIfPresent([String].self, forKey: .rootDirs) ?? []
    }
}

// MARK: - Genre (from GenreDto.kt)
struct Genre: Codable, Hashable {
    let genreHash: String
    let name: String
    enum CodingKeys: String, CodingKey { case genreHash = "genrehash", name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        genreHash = try c.decodeIfPresent(String.self, forKey: .genreHash) ?? ""
        name      = try c.decodeIfPresent(String.self, forKey: .name)      ?? ""
    }
}

// MARK: - LyricLine (from LyricLine.kt domain model)
struct LyricLine: Identifiable {
    let id = UUID()
    let timeMs: Int64
    let text: String
}

// MARK: - Search models (from TopSearchResultsDto, TracksSearchResultDto etc.)
struct TopSearchResults: Codable {
    let topResultItem: TopResultItem?
    let tracks: [Track]
    let albums: [Album]
    let artists: [Artist]
    enum CodingKeys: String, CodingKey {
        case topResultItem = "top_result", tracks, albums, artists
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topResultItem = try c.decodeIfPresent(TopResultItem.self, forKey: .topResultItem)
        tracks        = try c.decodeIfPresent([Track].self,       forKey: .tracks)  ?? []
        albums        = try c.decodeIfPresent([Album].self,       forKey: .albums)  ?? []
        artists       = try c.decodeIfPresent([Artist].self,      forKey: .artists) ?? []
    }
}

struct TopResultItem: Codable {
    let type: String
    let title: String
    let name: String
    let image: String
    let artistHash: String
    let albumHash: String
    let trackHash: String
    let albumArtists: [Artist]
    let artists: [Artist]
    let isFavorite: Bool
    let duration: Int
    let bitrate: Int
    let explicit: Bool
    let filepath: String
    let folder: String
    let album: String

    var displayTitle: String { type == "artist" ? name : title }
    var displayType: String { type.prefix(1).uppercased() + type.dropFirst() }
    var hash: String {
        switch type {
        case "artist": return artistHash
        case "track":  return trackHash
        case "album":  return albumHash
        default:       return ""
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, title, name, image, artists, album, filepath, folder, duration, bitrate, explicit
        case artistHash   = "artisthash"
        case albumHash    = "albumhash"
        case trackHash    = "trackhash"
        case albumArtists = "albumartists"
        case isFavorite   = "is_favorite"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type         = try c.decodeIfPresent(String.self,   forKey: .type)         ?? ""
        title        = try c.decodeIfPresent(String.self,   forKey: .title)        ?? ""
        name         = try c.decodeIfPresent(String.self,   forKey: .name)         ?? ""
        image        = try c.decodeIfPresent(String.self,   forKey: .image)        ?? ""
        artistHash   = try c.decodeIfPresent(String.self,   forKey: .artistHash)   ?? ""
        albumHash    = try c.decodeIfPresent(String.self,   forKey: .albumHash)    ?? ""
        trackHash    = try c.decodeIfPresent(String.self,   forKey: .trackHash)    ?? ""
        albumArtists = try c.decodeIfPresent([Artist].self, forKey: .albumArtists) ?? []
        artists      = try c.decodeIfPresent([Artist].self, forKey: .artists)      ?? []
        isFavorite   = try c.decodeIfPresent(Bool.self,     forKey: .isFavorite)   ?? false
        duration     = try c.decodeIfPresent(Int.self,      forKey: .duration)     ?? 0
        bitrate      = try c.decodeIfPresent(Int.self,      forKey: .bitrate)      ?? 0
        explicit     = try c.decodeIfPresent(Bool.self,     forKey: .explicit)     ?? false
        filepath     = try c.decodeIfPresent(String.self,   forKey: .filepath)     ?? ""
        folder       = try c.decodeIfPresent(String.self,   forKey: .folder)       ?? ""
        album        = try c.decodeIfPresent(String.self,   forKey: .album)        ?? ""
    }
}

struct TracksSearchResult: Codable {
    let more: Bool; let results: [Track]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        more    = try c.decodeIfPresent(Bool.self,    forKey: .more)    ?? false
        results = try c.decodeIfPresent([Track].self, forKey: .results) ?? []
    }
    enum CodingKeys: String, CodingKey { case more, results }
}

struct AlbumsSearchResult: Codable {
    let more: Bool; let results: [Album]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        more    = try c.decodeIfPresent(Bool.self,    forKey: .more)    ?? false
        results = try c.decodeIfPresent([Album].self, forKey: .results) ?? []
    }
    enum CodingKeys: String, CodingKey { case more, results }
}

struct ArtistsSearchResult: Codable {
    let more: Bool; let results: [Artist]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        more    = try c.decodeIfPresent(Bool.self,     forKey: .more)    ?? false
        results = try c.decodeIfPresent([Artist].self, forKey: .results) ?? []
    }
    enum CodingKeys: String, CodingKey { case more, results }
}

struct AllAlbums: Codable {
    let items: [Album]; let total: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([Album].self, forKey: .items) ?? []
        total = try c.decodeIfPresent(Int.self,     forKey: .total) ?? 0
    }
    enum CodingKeys: String, CodingKey { case items, total }
}

struct AllArtists: Codable {
    let items: [Artist]; let total: Int
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([Artist].self, forKey: .items) ?? []
        total = try c.decodeIfPresent(Int.self,      forKey: .total) ?? 0
    }
    enum CodingKeys: String, CodingKey { case items, total }
}

// MARK: - Auth models
// Field names match the actual Swing Music API JSON responses.
// Use the debug error helper in SwingAPIClient.getAllUsers to see raw
// JSON if anything changes server-side.

struct LogInResult: Codable {
    let accessToken: String
    let refreshToken: String
    let maxAge: Int64
    let msg: String

    // Swing Music server returns: accesstoken, refreshtoken, maxage, msg
    enum CodingKeys: String, CodingKey {
        case accessToken  = "accesstoken"
        case refreshToken = "refreshtoken"
        case maxAge       = "maxage"
        case msg
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken  = try c.decodeIfPresent(String.self, forKey: .accessToken)  ?? ""
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
        maxAge       = try c.decodeIfPresent(Int64.self,  forKey: .maxAge)       ?? 0
        msg          = try c.decodeIfPresent(String.self, forKey: .msg)          ?? ""
    }
}

// GET /auth/users response
// { "users": [...], "settings": { "enableGuest": bool, "usersOnLogin": bool } }
struct AllUsersResponse: Codable {
    let users: [SwingUser]
    let settings: ProfileSettings

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        users    = try c.decodeIfPresent([SwingUser].self,    forKey: .users)    ?? []
        settings = try c.decodeIfPresent(ProfileSettings.self, forKey: .settings)
                   ?? ProfileSettings(enableGuest: false, usersOnLogin: false)
    }
    // Memberwise init for fallback parsing
    init(users: [SwingUser], settings: ProfileSettings) {
        self.users    = users
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey { case users, settings }
}

struct SwingUser: Identifiable, Codable {
    let id: Int
    let username: String
    let firstname: String
    let lastname: String
    let email: String
    let image: String
    let roles: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(Int.self,      forKey: .id)        ?? 0
        username  = try c.decodeIfPresent(String.self,   forKey: .username)  ?? ""
        firstname = try c.decodeIfPresent(String.self,   forKey: .firstname) ?? ""
        lastname  = try c.decodeIfPresent(String.self,   forKey: .lastname)  ?? ""
        email     = try c.decodeIfPresent(String.self,   forKey: .email)     ?? ""
        image     = try c.decodeIfPresent(String.self,   forKey: .image)     ?? ""
        roles     = try c.decodeIfPresent([String].self, forKey: .roles)     ?? []
    }
    enum CodingKeys: String, CodingKey {
        case id, username, firstname, lastname, email, image, roles
    }
}

struct ProfileSettings: Codable {
    let enableGuest: Bool
    let usersOnLogin: Bool

    // Swing Music uses camelCase in JSON: enableGuest, usersOnLogin
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enableGuest  = try c.decodeIfPresent(Bool.self, forKey: .enableGuest)  ?? false
        usersOnLogin = try c.decodeIfPresent(Bool.self, forKey: .usersOnLogin) ?? false
    }

    // Memberwise init for fallback when settings key is missing
    init(enableGuest: Bool, usersOnLogin: Bool) {
        self.enableGuest  = enableGuest
        self.usersOnLogin = usersOnLogin
    }

    enum CodingKeys: String, CodingKey { case enableGuest, usersOnLogin }
}

// MARK: - Playback enums (from PlaybackState.kt, RepeatMode.kt, ShuffleMode.kt, QueueSource.kt)
enum PlaybackState { case playing, paused, error, buffering }

enum RepeatMode: String, CaseIterable, Codable {
    case none = "REPEAT_NONE"
    case all  = "REPEAT_ALL"
    case one  = "REPEAT_ONE"

    var next: RepeatMode {
        switch self { case .none: return .all; case .all: return .one; case .one: return .none }
    }
    var systemImage: String {
        switch self { case .none, .all: return "repeat"; case .one: return "repeat.1" }
    }
    var isActive: Bool { self != .none }
}

enum ShuffleMode: String, Codable { case on = "SHUFFLE_ON"; case off = "SHUFFLE_OFF" }

// SortBy + SortOrder (from SortBy.kt, SortOrder.kt)
enum SortBy: String, CaseIterable {
    case title = "title"
    case albumArtists = "albumartists"
    case date = "date"
    case createdDate = "created_date"
    case duration = "duration"
    case playCount = "playcount"
    case playDuration = "playduration"
    case lastPlayed = "lastplayed"
    case noOfTracks = "trackcount"
    case name = "name"
    case noOfAlbums = "albumcount"

    var displayLabel: String {
        switch self {
        case .title:       return "Title"
        case .albumArtists: return "Artists"
        case .date:        return "Year Released"
        case .createdDate: return "Date Added"
        case .duration:    return "Duration"
        case .playCount:   return "No. of plays"
        case .playDuration: return "Play duration"
        case .lastPlayed:  return "Last played"
        case .noOfTracks:  return "No. of tracks"
        case .name:        return "Name"
        case .noOfAlbums:  return "Albums"
        }
    }
}

enum SortOrder: Int { case ascending = 0; case descending = 1 }

enum QueueSource: Equatable, Codable {
    case folder(name: String, path: String)
    case album(name: String, hash: String)
    case artist(name: String, hash: String)
    case search(query: String)
    case favorite
    case unknown

    var displayName: String {
        switch self {
        case .folder(let n, _): return n
        case .album(let n, _):  return n
        case .artist(let n, _): return n
        case .search(let q):    return "Search: \(q)"
        case .favorite:         return "Favorites"
        case .unknown:          return "Queue"
        }
    }
}

// MARK: - Network request bodies
struct FoldersAndTracksRequest: Encodable {
    let folder: String; let tracksOnly: Bool; let limit: Int; let start: Int
    enum CodingKeys: String, CodingKey {
        case folder; case tracksOnly = "tracks_only"; case limit; case start
    }
}
struct AlbumHashRequest: Encodable { let albumhash: String }
struct ToggleFavoriteRequest: Encodable { let hash: String; let type: String }
struct LogTrackRequest: Encodable {
    let duration: Int; let source: String; let timestamp: Int64; let trackHash: String
    enum CodingKeys: String, CodingKey {
        case duration, source, timestamp; case trackHash = "trackhash"
    }
}
struct LoginRequest: Encodable { let username: String; let password: String }
private struct EmptyResponse: Codable {}

// MARK: - Playlist models
struct Playlist: Codable, Identifiable {
    let id: Int
    let name: String
    let trackCount: Int
    let duration: Int
    let image: String

    enum CodingKeys: String, CodingKey {
        case id; case name
        case trackCount = "trackcount"
        case duration; case image
    }
}

struct PlaylistsResponse: Codable {
    let playlists: [Playlist]
}

struct PlaylistWithTracks: Codable {
    let info: Playlist
    let tracks: [Track]
}

struct CreatePlaylistRequest: Encodable { let name: String }
struct PlaylistTracksRequest: Encodable { let trackhashes: [String] }

// MARK: - Recently played
struct RecentlyPlayedResponse: Codable {
    let tracks: [Track]
    let albums: [Album]
    let artists: [Artist]
}

// MARK: - Queue
struct QueueResponse: Codable {
    let tracks: [Track]
    let currentIndex: Int
    enum CodingKeys: String, CodingKey {
        case tracks; case currentIndex = "current_index"
    }
}

struct SaveQueueRequest: Encodable {
    let trackhashes: [String]
    let currentIndex: Int
    enum CodingKeys: String, CodingKey {
        case trackhashes; case currentIndex = "current_index"
    }
}

// MARK: - Additional response types

struct FavoritesResponse: Codable {
    let tracks: [Track]
    let albums: [Album]
    let artists: [Artist]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tracks  = try c.decodeIfPresent([Track].self,  forKey: .tracks)  ?? []
        albums  = try c.decodeIfPresent([Album].self,  forKey: .albums)  ?? []
        artists = try c.decodeIfPresent([Artist].self, forKey: .artists) ?? []
    }
    enum CodingKeys: String, CodingKey { case tracks, albums, artists }
}

struct HomepageResponse: Codable {
    // Dynamic shape — ignored for now, HomeView fetches separately
    init(from decoder: Decoder) throws {}
}

struct LyricsServerResponse: Codable {
    let synced: Bool
    let copyright: String
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        synced    = try c.decodeIfPresent(Bool.self,   forKey: .synced)    ?? false
        copyright = try c.decodeIfPresent(String.self, forKey: .copyright) ?? ""
    }
    enum CodingKeys: String, CodingKey { case synced, copyright }
}
