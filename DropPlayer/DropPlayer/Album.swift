import Foundation

// MARK: - Track

struct Track: Identifiable, Hashable, Codable {
    let id: String
    let dropboxPath: String
    let fileName: String
    let title: String
    let trackNumber: Int?
    let discNumber: Int?
    let durationSeconds: Double?

    var displayTitle: String {
        title.isEmpty ? fileName : title
    }
}

// MARK: - Album

struct Album: Identifiable, Codable {
    let id: String
    let folderPath: String
    let folderName: String
    var title: String
    var artist: String
    var year: String?
    var tracks: [Track]
    var artworkDropboxPath: String?

    var displayTitle: String {
        title.isEmpty ? folderName : title
    }

    var displayArtist: String {
        artist.isEmpty ? "Unknown Artist" : artist
    }
}
