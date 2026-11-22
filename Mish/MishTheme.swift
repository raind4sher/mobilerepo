import SwiftUI
import UIKit

// MARK: - User themes

struct MishTheme: Identifiable, Codable, Equatable {
    enum BackgroundMotion: String, CaseIterable, Identifiable, Codable {
        case none
        case scrolling
        case parallax

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "Still"
            case .scrolling: return "Slow scrolling"
            case .parallax: return "Tilt parallax"
            }
        }

        var subtitle: String {
            switch self {
            case .none: return "A stationary background"
            case .scrolling: return "The background drifts gently"
            case .parallax: return "The background responds to device movement"
            }
        }
    }

    var id: UUID
    var name: String
    var accentHex: UInt32
    var mainHex: UInt32
    var backgroundHex: UInt32
    var overlayOpacity: Double
    var blurEnabled: Bool
    var blurRadius: Double
    var overridesAlbumArtBlur: Bool
    var backgroundImageFilename: String?
    var motion: BackgroundMotion

    static var starter: MishTheme {
        MishTheme(
            id: UUID(),
            name: "Mish Default",
            accentHex: 0xA6E3A1,
            mainHex: 0xFFFFFF,
            backgroundHex: 0x101014,
            overlayOpacity: 0.48,
            blurEnabled: true,
            blurRadius: 55,
            overridesAlbumArtBlur: false,
            backgroundImageFilename: nil,
            motion: .none
        )
    }

    var accentColor: Color { Color(mishHex: accentHex) }
    var mainColor: Color { Color(mishHex: mainHex) }
    var backgroundColor: Color { Color(mishHex: backgroundHex) }

    /// Name for lists; never empty.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Theme" : trimmed
    }

    /// Short line under the name in the theme list.
    var summary: String {
        let backdrop = backgroundImageFilename == nil ? "Color background" : "Custom image"
        return "\(motion.title) · \(backdrop)"
    }
}

// MARK: - Store

@MainActor
final class MishThemeStore: ObservableObject {
    @Published private(set) var themes: [MishTheme] = []
    @Published var activeThemeID: UUID? {
        didSet { persist() }
    }

    private let defaultsKey = "mish.customThemes.v1"
    private let activeKey = "mish.activeCustomTheme.v1"

    /// Decoded background images, so views never hit the disk while rendering.
    private let imageCache = NSCache<NSString, UIImage>()

    init() {
        load()
    }

    var activeTheme: MishTheme {
        if let id = activeThemeID,
           let theme = themes.first(where: { $0.id == id }) {
            return theme
        }
        return themes.first ?? MishTheme.starter
    }

    /// Changes whenever the accent or main color (or active theme) changes,
    /// so the main screen can rebuild itself with `.id(...)`.
    var paletteRevision: String {
        let theme = activeTheme
        return "\(theme.id.uuidString)-\(theme.accentHex)-\(theme.mainHex)"
    }

    // MARK: Editing

    @discardableResult
    func createTheme() -> UUID {
        var theme = MishTheme.starter
        theme.id = UUID()
        theme.name = "My Theme \(themes.count + 1)"
        themes.append(theme)
        activeThemeID = theme.id
        persist()
        return theme.id
    }

    func update(_ theme: MishTheme) {
        guard let index = themes.firstIndex(where: { $0.id == theme.id }) else { return }
        guard themes[index] != theme else { return }
        themes[index] = theme
        persist()
    }

    func select(_ id: UUID) {
        guard themes.contains(where: { $0.id == id }) else { return }
        activeThemeID = id
    }

    func delete(_ id: UUID) {
        guard themes.count > 1 else { return }
        let filename = themes.first(where: { $0.id == id })?.backgroundImageFilename
        themes.removeAll { $0.id == id }
        discardImageFile(named: filename)
        if activeThemeID == id {
            activeThemeID = themes.first?.id
        }
        persist()
    }

    // MARK: Background images

    func backgroundImageURL(for theme: MishTheme) -> URL? {
        guard let filename = theme.backgroundImageFilename else { return nil }
        let url = themeDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Cached image for a theme's custom background (nil if it has none).
    func backgroundImage(for theme: MishTheme) -> UIImage? {
        guard let filename = theme.backgroundImageFilename else { return nil }
        let key = filename as NSString

        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        let path = themeDirectory.appendingPathComponent(filename).path
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        imageCache.setObject(image, forKey: key)
        return image
    }

    @discardableResult
    func setBackgroundImage(_ data: Data, for themeID: UUID) -> Bool {
        guard let index = themes.firstIndex(where: { $0.id == themeID }),
              let source = UIImage(data: data) else {
            return false
        }

        let image = source.mishScaledToFit(maxDimension: 2400)
        guard let jpeg = image.jpegData(compressionQuality: 0.88) else {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: themeDirectory,
                withIntermediateDirectories: true
            )

            // A fresh name per save keeps the cache from serving a stale picture.
            let suffix = String(UUID().uuidString.prefix(8))
            let filename = "\(themeID.uuidString)-\(suffix).jpg"
            try jpeg.write(
                to: themeDirectory.appendingPathComponent(filename),
                options: .atomic
            )

            discardImageFile(named: themes[index].backgroundImageFilename)
            themes[index].backgroundImageFilename = filename
            imageCache.setObject(image, forKey: filename as NSString)
            persist()
            return true
        } catch {
            print("Mish theme image save failed:", error)
            return false
        }
    }

    func clearBackgroundImage(for themeID: UUID) {
        guard let index = themes.firstIndex(where: { $0.id == themeID }) else { return }
        discardImageFile(named: themes[index].backgroundImageFilename)
        themes[index].backgroundImageFilename = nil
        persist()
    }

    private var themeDirectory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support.appendingPathComponent("MishThemes", isDirectory: true)
    }

    private func discardImageFile(named filename: String?) {
        guard let filename else { return }
        imageCache.removeObject(forKey: filename as NSString)
        try? FileManager.default.removeItem(
            at: themeDirectory.appendingPathComponent(filename)
        )
    }

    // MARK: Persistence

    private func load() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([MishTheme].self, from: data),
           !decoded.isEmpty {
            themes = decoded
        } else {
            themes = [MishTheme.starter]
        }

        if let rawID = defaults.string(forKey: activeKey),
           let id = UUID(uuidString: rawID),
           themes.contains(where: { $0.id == id }) {
            activeThemeID = id
        } else {
            activeThemeID = themes.first?.id
        }
        persist()
    }

    private func persist() {
        guard !themes.isEmpty,
              let data = try? JSONEncoder().encode(themes) else { return }
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: defaultsKey)
        defaults.set(activeThemeID?.uuidString, forKey: activeKey)
        syncPalette()
    }

    private func syncPalette() {
        let theme = activeTheme
        MishPalette.accent = theme.accentColor
        MishPalette.main = theme.mainColor
    }
}

// MARK: - App-wide palette

/// The active theme's accent and main colors, readable from any view
/// (the store keeps this up to date). `Color.mishGreen` reads from here.
enum MishPalette {
    static var accent: Color = Color(mishHex: 0xA6E3A1)
    static var main: Color = Color.white
}

// MARK: - Color <-> hex

/// One 0...1 color channel as 0...255. Kept as its own function so the
/// compiler never has to solve a long mixed-type expression.
private func mishChannel(_ value: CGFloat) -> UInt32 {
    let clamped: CGFloat = min(max(value, 0), 1)
    let scaled: CGFloat = (clamped * 255).rounded()
    return UInt32(scaled)
}

extension Color {
    init(mishHex: UInt32) {
        let red = Double((mishHex >> 16) & 0xFF) / 255.0
        let green = Double((mishHex >> 8) & 0xFF) / 255.0
        let blue = Double(mishHex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    var mishHex: UInt32 {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let r: UInt32 = mishChannel(red)
        let g: UInt32 = mishChannel(green)
        let b: UInt32 = mishChannel(blue)
        return (r << 16) | (g << 8) | b
    }
}

// MARK: - Image helper

extension UIImage {
    /// Shrinks the image so its longest side is at most `maxDimension`.
    func mishScaledToFit(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }

        let ratio = maxDimension / longest
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
