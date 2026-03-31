import Foundation
import Combine

enum AlbumSortOption: String, CaseIterable, Codable {
    case title = "Title"
    case artist = "Artist"
    case year = "Year"
    case location = "Location"
    case genre = "Genre"
}

/// Persists user preferences between launches.
final class AppSettings: ObservableObject {
    @Published var isAuthenticated: Bool {
        didSet { UserDefaults.standard.set(isAuthenticated, forKey: Keys.isAuthenticated) }
    }

    /// The Dropbox paths the user chose to scan, e.g. ["/Music", "/Audiobooks"]
    @Published var musicFolderPaths: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(musicFolderPaths) {
                UserDefaults.standard.set(data, forKey: Keys.musicFolderPaths)
            }
        }
    }

    @Published var albumSortOption: AlbumSortOption {
        didSet {
            UserDefaults.standard.set(albumSortOption.rawValue, forKey: Keys.albumSortOption)
        }
    }

    private enum Keys {
        static let isAuthenticated = "isAuthenticated"
        static let musicFolderPaths = "musicFolderPaths"
        static let musicFolderPathLegacy = "musicFolderPath"
        static let albumSortOption = "albumSortOption"
    }

    init() {
        self.isAuthenticated = UserDefaults.standard.bool(forKey: Keys.isAuthenticated)

        if let data = UserDefaults.standard.data(forKey: Keys.musicFolderPaths),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            self.musicFolderPaths = paths
        } else if let legacy = UserDefaults.standard.string(forKey: Keys.musicFolderPathLegacy) {
            self.musicFolderPaths = [legacy]
        } else {
            self.musicFolderPaths = []
        }

        if let sortRaw = UserDefaults.standard.string(forKey: Keys.albumSortOption),
           let sortOption = AlbumSortOption(rawValue: sortRaw) {
            self.albumSortOption = sortOption
        } else {
            self.albumSortOption = .title
        }
    }

    func logOut() {
        isAuthenticated = false
        musicFolderPaths = []
    }
}
