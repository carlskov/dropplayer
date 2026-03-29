import SwiftUI
import SwiftyDropbox

@main
struct DropPlayerApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var library = LibraryViewModel()
    @StateObject private var player = PlayerEngine()

    init() {
        // Replace "YOUR_APP_KEY" with your Dropbox app key from https://www.dropbox.com/developers/apps
        DropboxClientsManager.setupWithAppKey("nidpcwsova63utb")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(player)
                .onOpenURL { url in
                    // Handle OAuth redirect after Dropbox login
                    let oauthCompletion: DropboxOAuthCompletion = { result in
                        if case .success = result {
                            NotificationCenter.default.post(name: .dropboxAuthSucceeded, object: nil)
                        }
                    }
                    DropboxClientsManager.handleRedirectURL(url, includeBackgroundClient: false, completion: oauthCompletion)
                }
        }
    }
}

extension Notification.Name {
    static let dropboxAuthSucceeded = Notification.Name("dropboxAuthSucceeded")
}
