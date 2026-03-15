import SwiftUI

// MARK: - Color palette (exact hex values from Color.kt)
extension Color {
    // Light scheme
    static let swingLightPrimary              = Color(argb: 0xFF1DB954)
    static let swingLightOnPrimary            = Color(argb: 0xFF000000)
    static let swingLightPrimaryContainer     = Color(argb: 0xFFD1F3DD)
    static let swingLightOnPrimaryContainer   = Color(argb: 0xFF002110)
    static let swingLightSecondary            = Color(argb: 0xFF535353)
    static let swingLightOnSecondary          = Color(argb: 0xFFFFFFFF)
    static let swingLightSecondaryContainer   = Color(argb: 0xFFE0E0E0)
    static let swingLightOnSecondaryContainer = Color(argb: 0xFF1A1A1A)
    static let swingLightTertiary             = Color(argb: 0xFF1AA34A)
    static let swingLightBackground           = Color(argb: 0xFFFAFAFA)
    static let swingLightOnBackground         = Color(argb: 0xFF1A1A1A)
    static let swingLightSurface              = Color(argb: 0xFFFFFFFF)
    static let swingLightOnSurface            = Color(argb: 0xFF1A1A1A)
    static let swingLightSurfaceVariant       = Color(argb: 0xFFF5F5F5)
    static let swingLightOnSurfaceVariant     = Color(argb: 0xFF535353)
    static let swingLightError                = Color(argb: 0xFFB3261E)
    static let swingLightErrorContainer       = Color(argb: 0xFFF9DEDC)
    static let swingLightOutline              = Color(argb: 0xFFB3B3B3)
    static let swingLightInverseSurface       = Color(argb: 0xFF2E2E2E)
    static let swingLightInverseOnSurface     = Color(argb: 0xFFF5F5F5)

    // Dark scheme
    static let swingDarkPrimary               = Color(argb: 0xFF1DB954)
    static let swingDarkOnPrimary             = Color(argb: 0xFF000000)
    static let swingDarkPrimaryContainer      = Color(argb: 0xFF1AA34A)
    static let swingDarkOnPrimaryContainer    = Color(argb: 0xFFFFFFFF)
    static let swingDarkSecondary             = Color(argb: 0xFFB3B3B3)
    static let swingDarkOnSecondary           = Color(argb: 0xFF1A1A1A)
    static let swingDarkSecondaryContainer    = Color(argb: 0xFF282828)
    static let swingDarkOnSecondaryContainer  = Color(argb: 0xFFE0E0E0)
    static let swingDarkTertiary              = Color(argb: 0xFF1ED760)
    static let swingDarkBackground            = Color(argb: 0xFF121212)
    static let swingDarkOnBackground          = Color(argb: 0xFFFFFFFF)
    static let swingDarkSurface               = Color(argb: 0xFF181818)
    static let swingDarkOnSurface             = Color(argb: 0xFFFFFFFF)
    static let swingDarkSurfaceVariant        = Color(argb: 0xFF282828)
    static let swingDarkOnSurfaceVariant      = Color(argb: 0xFFB3B3B3)
    static let swingDarkError                 = Color(argb: 0xFFF2B8B5)
    static let swingDarkErrorContainer        = Color(argb: 0xFF8C1D18)
    static let swingDarkOutline               = Color(argb: 0xFF535353)
    static let swingDarkInverseSurface        = Color(argb: 0xFFF5F5F5)
    static let swingDarkInverseOnSurface      = Color(argb: 0xFF121212)

    // Semantic shortcuts used throughout the app
    static let swingPrimary = Color(argb: 0xFF1DB954)

    // Version badge colors from AlbumItem.kt
    static let versionBgLight   = Color(red: 0x3D/255, green: 0x74/255, blue: 0x4F/255, opacity: 0x00/255.0) // 0x3D744F00
    static let versionTextLight = Color(argb: 0xFF744E00)
    static let versionBgDark    = Color(red: 0xDA/255, green: 0xCC/255, blue: 0x32/255, opacity: 0x26/255.0) // 0x26DACC32
    static let versionTextDark  = Color(argb: 0xFFDACC32)

    static func versionBg(darkMode: Bool) -> Color { darkMode ? versionBgDark : versionBgLight }
    static func versionText(darkMode: Bool) -> Color { darkMode ? versionTextDark : versionTextLight }

    // ARGB convenience init (mirrors Android Color(0xFFRRGGBB))
    init(argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255
        let r = Double((argb >> 16) & 0xFF) / 255
        let g = Double((argb >>  8) & 0xFF) / 255
        let b = Double( argb        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Typography (exact values from Type.kt)
struct SwingType {
    static let headlineLarge  = Font.system(size: 32, weight: .semibold)
    static let headlineMedium = Font.system(size: 28, weight: .semibold)
    static let headlineSmall  = Font.system(size: 24, weight: .semibold)
    static let titleLarge     = Font.system(size: 22, weight: .semibold)
    static let titleMedium    = Font.system(size: 16, weight: .semibold)
    static let titleSmall     = Font.system(size: 14, weight: .bold)
    static let bodyLarge      = Font.system(size: 16, weight: .regular)
    static let bodyMedium     = Font.system(size: 14, weight: .regular)
    static let bodySmall      = Font.system(size: 12, weight: .regular)
    static let labelLarge     = Font.system(size: 14, weight: .semibold)
    static let labelMedium    = Font.system(size: 12, weight: .semibold)
    static let labelSmall     = Font.system(size: 11, weight: .semibold)
}

// MARK: - SwingMusicTheme modifier
// Mirrors SwingMusicTheme @Composable.
// Dynamic color handled by iOS natively when using .tint(.swingPrimary)
struct SwingMusicThemeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.tint(.swingPrimary)
    }
}

extension View {
    func swingMusicTheme() -> some View {
        modifier(SwingMusicThemeModifier())
    }
}

// MARK: - Screen enum (from Screen.kt)
enum SwingScreen { case allAlbums, artist, search, home }
