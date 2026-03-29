import Foundation
import Combine

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

    private enum Keys {
        static let isAuthenticated = "isAuthenticated"
        static let musicFolderPaths = "musicFolderPaths"
        static let musicFolderPathLegacy = "musicFolderPath"
    }

    init() {
        self.isAuthenticated = UserDefaults.standard.bool(forKey: Keys.isAuthenticated)

        if let data = UserDefaults.standard.data(forKey: Keys.musicFolderPaths),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            self.musicFolderPaths = paths
        } else if let legacy = UserDefaults.standard.string(forKey: Keys.musicFolderPathLegacy) {
            // Migrate single-folder setting from previous version
            self.musicFolderPaths = [legacy]
        } else {
            self.musicFolderPaths = []
        }
    }

    func logOut() {
        isAuthenticated = false
        musicFolderPaths = []
    }
}
