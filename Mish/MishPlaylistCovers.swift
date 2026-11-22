import UIKit

/// Stores custom playlist cover pictures in the app's private storage.
/// Pictures are cropped to a square and shrunk once on save, then cached.
final class MishPlaylistCovers {
    static let shared = MishPlaylistCovers()

    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    private var directory: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support.appendingPathComponent("MishPlaylistCovers", isDirectory: true)
    }

    func image(named name: String?) -> UIImage? {
        guard let name else { return nil }
        let key = name as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        let path = directory.appendingPathComponent(name).path
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Saves picked image data and returns the new file name (nil on failure).
    func save(_ data: Data) -> String? {
        guard let source = UIImage(data: data) else { return nil }

        let square = squareCropped(source, maxSide: 900)
        guard let jpeg = square.jpegData(compressionQuality: 0.88) else { return nil }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let name = UUID().uuidString + ".jpg"
            try jpeg.write(to: directory.appendingPathComponent(name), options: .atomic)
            cache.setObject(square, forKey: name as NSString)
            return name
        } catch {
            print("Mish playlist cover save failed:", error)
            return nil
        }
    }

    func remove(named name: String?) {
        guard let name else { return }
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    // MARK: Cropping

    private func squareCropped(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return image }

        let shortest = min(width, height)
        let target = min(maxSide, shortest)
        let scale = target / shortest

        let drawSize = CGSize(width: width * scale, height: height * scale)
        let originX = (target - drawSize.width) / 2
        let originY = (target - drawSize.height) / 2
        let drawRect = CGRect(x: originX, y: originY, width: drawSize.width, height: drawSize.height)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: target, height: target),
            format: format
        )
        return renderer.image { _ in
            image.draw(in: drawRect)
        }
    }
}
