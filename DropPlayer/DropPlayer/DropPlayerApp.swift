import SwiftUI
import SwiftyDropbox
import GoogleCast

@main
struct DropPlayerApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var library = LibraryViewModel()
    @StateObject private var player = PlayerEngine()
    @StateObject private var cast = CastManager()

    init() {
        // Replace "YOUR_APP_KEY" with your Dropbox app key from https://www.dropbox.com/developers/apps
        DropboxClientsManager.setupWithAppKey("nidpcwsova63utb")

        // Initialise Google Cast. Must be called before the first SwiftUI scene renders.
        let options = GCKCastOptions(
            discoveryCriteria: GCKDiscoveryCriteria(applicationID: CastManager.receiverAppID)
        )
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(cast)
                .task {
                    cast.setup(player: player, library: library)
                }
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
