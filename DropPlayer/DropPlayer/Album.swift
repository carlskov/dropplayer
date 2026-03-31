import Foundation

// MARK: - Track

struct Track: Identifiable, Hashable, Codable {
    let id: String
    let dropboxPath: String
    let fileName: String
    var title: String
    var trackNumber: Int?
    var discNumber: Int?
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
    var discNumber: Int?
    var tracks: [Track]
    var artworkDropboxPath: String?
    var tagsLoaded: Bool = false
    var copyright: String? = nil
    var label: String? = nil
    var genre: String? = nil

    var displayTitle: String {
        title.isEmpty ? folderName : title
    }

    var displayArtist: String {
        artist.isEmpty ? "Unknown Artist" : artist
    }

    init(id: String, folderPath: String, folderName: String, title: String, artist: String, year: String? = nil, discNumber: Int? = nil, tracks: [Track] = [], artworkDropboxPath: String? = nil, tagsLoaded: Bool = false, copyright: String? = nil, label: String? = nil, genre: String? = nil) {
        self.id = id
        self.folderPath = folderPath
        self.folderName = folderName
        self.title = title
        self.artist = artist
        self.year = year
        self.discNumber = discNumber
        self.tracks = tracks.sorted { t1, t2 in
            let disc1 = t1.discNumber ?? 1
            let disc2 = t2.discNumber ?? 1
            if disc1 != disc2 {
                return disc1 < disc2
            }
            let track1 = t1.trackNumber ?? 0
            let track2 = t2.trackNumber ?? 0
            if track1 != track2 {
                return track1 < track2
            }
            return t1.id < t2.id
        }
        self.artworkDropboxPath = artworkDropboxPath
        self.tagsLoaded = tagsLoaded
        self.copyright = copyright
        self.label = label
        self.genre = genre
    }
}
