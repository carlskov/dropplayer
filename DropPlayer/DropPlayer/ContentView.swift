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
            } else if settings.musicFolderPaths.isEmpty {
                FolderPickerView(isInitialSetup: true)
            } else {
                MainTabView()
            }
        }
        .background {
            Theme.libraryGradient
                .ignoresSafeArea()
        }
        .environmentObject(NowPlayingCoordinator.shared)
        .animation(.easeInOut, value: settings.isAuthenticated)
        .animation(.easeInOut, value: settings.musicFolderPaths.isEmpty)
    }
}

struct MainTabView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var nowPlaying: NowPlayingCoordinator
    @EnvironmentObject var cast: CastManager

    var body: some View {
        AlbumListView()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.currentTrack != nil || cast.isConnected {
                    MiniPlayerView()
                }
            }
            .fullScreenCover(isPresented: $nowPlaying.isPresented) {
                NowPlayingView()
            }
    }
}
