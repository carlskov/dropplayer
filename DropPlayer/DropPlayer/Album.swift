import Foundation

// MARK: - Track

struct Track: Identifiable, Hashable, Codable {
    let id: String
    let dropboxPath: String
    let fileName: String
    var title: String
    var trackNumber: Int?
    let discNumber: Int?
    let durationSeconds: Double?
    var artist: String? = nil

    var displayTitle: String {
        title.isEmpty ? fileName : title
    }
}

// MARK: - Album

struct Album: Identifiable, Hashable, Codable {
    let id: String
    let folderPath: String
    let folderName: String
    var title: String
    var artist: String
    var year: String?
    var tracks: [Track]
    var artworkDropboxPath: String?
    var tagsLoaded: Bool = false

    var displayTitle: String {
        title.isEmpty ? folderName : title
    }

    var displayArtist: String {
        artist.isEmpty ? "Unknown Artist" : artist
    }
}
