import Foundation
import UIKit

// MARK: - Track

struct Track: Identifiable, Hashable {
    let id: String          // Dropbox path_lower
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

struct Album: Identifiable {
    let id: String          // Dropbox folder path_lower
    let folderPath: String
    let folderName: String  // display fallback
    var title: String
    var artist: String
    var year: String?
    var tracks: [Track]
    var artworkDropboxPath: String?   // path to cover image in Dropbox

    // Cached artwork loaded from Dropbox
    var artworkImage: UIImage?

    var displayTitle: String {
        title.isEmpty ? folderName : title
    }

    var displayArtist: String {
        artist.isEmpty ? "Unknown Artist" : artist
    }
}
