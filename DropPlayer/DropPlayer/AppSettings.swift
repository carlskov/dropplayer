import Foundation
import Combine

/// Persists user preferences between launches.
final class AppSettings: ObservableObject {
    @Published var isAuthenticated: Bool {
        didSet { UserDefaults.standard.set(isAuthenticated, forKey: Keys.isAuthenticated) }
    }

    /// The Dropbox path the user chose to scan, e.g. "/Music"
    @Published var musicFolderPath: String? {
        didSet { UserDefaults.standard.set(musicFolderPath, forKey: Keys.musicFolderPath) }
    }

    private enum Keys {
        static let isAuthenticated = "isAuthenticated"
        static let musicFolderPath = "musicFolderPath"
    }

    init() {
        self.isAuthenticated = UserDefaults.standard.bool(forKey: Keys.isAuthenticated)
        self.musicFolderPath = UserDefaults.standard.string(forKey: Keys.musicFolderPath)
    }

    func logOut() {
        isAuthenticated = false
        musicFolderPath = nil
    }
}
