import SwiftUI

/// Root view: routes between setup and the main library screen.
struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var player: PlayerEngine

    var body: some View {
        Group {
            if !settings.isAuthenticated {
                SetupView()
            } else if settings.musicFolderPath == nil {
                FolderPickerView(isInitialSetup: true)
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut, value: settings.isAuthenticated)
        .animation(.easeInOut, value: settings.musicFolderPath)
    }
}

struct MainTabView: View {
    @EnvironmentObject var player: PlayerEngine

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                AlbumListView()
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
            }

            if player.currentTrack != nil {
                MiniPlayerView()
                    .padding(.bottom, 49) // tab bar height
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}
