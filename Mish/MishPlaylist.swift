
import Foundation

struct MishPlaylist: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var trackPaths: [String]
    /// File name of a custom cover picture (see MishPlaylistCovers).
    var coverFilename: String? = nil

    var trackCount: Int {
        trackPaths.count
    }

    mutating func add(_ url: URL) {
        trackPaths.append(url.standardizedFileURL.absoluteString)
    }

    mutating func remove(at index: Int) {
        guard trackPaths.indices.contains(index) else { return }
        trackPaths.remove(at: index)
    }

    mutating func move(from source: IndexSet, to destination: Int) {
        trackPaths.move(fromOffsets: source, toOffset: destination)
    }
}
