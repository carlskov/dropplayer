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
        .environmentObject(NowPlayingCoordinator.shared)
        .animation(.easeInOut, value: settings.isAuthenticated)
        .animation(.easeInOut, value: settings.musicFolderPath)
    }
}

struct MainTabView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var nowPlaying: NowPlayingCoordinator

    var body: some View {
        TabView {
            AlbumListView()
                .tabItem {
                    Label("Library", systemImage: "music.note.list")
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil {
                MiniPlayerView()
            }
        }
        .ignoresSafeArea(.keyboard)
        .sheet(isPresented: $nowPlaying.isPresented) {
            NowPlayingView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }
}
