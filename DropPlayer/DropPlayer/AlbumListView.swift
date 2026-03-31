import SwiftUI

/// The main library screen — a grid of album cards.
struct AlbumListView: View {
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var settings: AppSettings

    @State private var showFolderManager = false
    @State private var searchText = ""
    @State private var navigationPath: [Album] = []
    @State private var columnsPerRow: Int = 2
    @EnvironmentObject var nowPlaying: NowPlayingCoordinator

    private var filteredAlbums: [Album] {
        let base = searchText.isEmpty ? library.albums : library.albums.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.displayArtist.localizedCaseInsensitiveContains(searchText)
        }
        return sortAlbums(base)
    }

    private func sortAlbums(_ albums: [Album]) -> [Album] {
        switch settings.albumSortOption {
        case .title:
            return albums.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .artist:
            return albums.sorted { $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist) == .orderedAscending }
        case .year:
            return albums.sorted { album1, album2 in
                let year1 = album1.year.flatMap { Int($0) } ?? 0
                let year2 = album2.year.flatMap { Int($0) } ?? 0
                if year1 != year2 {
                    return year1 > year2
                }
                return album1.displayTitle.localizedCaseInsensitiveCompare(album2.displayTitle) == .orderedAscending
            }
        case .location:
            return albums.sorted { $0.folderPath.localizedCaseInsensitiveCompare($1.folderPath) == .orderedAscending }
        case .genre:
            return albums.sorted {
                let genreA = $0.genre ?? ""
                let genreB = $1.genre ?? ""
                if genreA == genreB {
                    return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
                }
                return genreA.localizedCaseInsensitiveCompare(genreB) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if library.isScanning {
                    scanningView
                } else if library.albums.isEmpty && library.scanError == nil {
                    emptyView
                } else if let error = library.scanError {
                    errorView(message: error)
                } else {
                    albumGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search albums or artists")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if library.isTagScanning {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.8)
                            Text("Scanning file tags")
                                .font(.headline)
                        }
                    } else {
                        Text("Library")
                            .font(.headline)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        columnsPerRow = columnsPerRow == 2 ? 3 : 2
                    } label: {
                        Image(systemName: columnsPerRow == 2 ? "square.grid.3x3" : "square.grid.2x2")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Section("Sort By") {
                            ForEach(AlbumSortOption.allCases, id: \.self) { option in
                                Button {
                                    settings.albumSortOption = option
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if settings.albumSortOption == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            Task { await library.rescanLibrary(at: settings.musicFolderPaths) }
                        } label: {
                            Label("Rescan Library", systemImage: "arrow.clockwise")
                        }
                        .disabled(settings.musicFolderPaths.isEmpty)

                        Button {
                            showFolderManager = true
                        } label: {
                            Label("Manage Folders", systemImage: "folder.badge.gearshape")
                        }

                        Divider()

                        Button(role: .destructive) {
                            DropboxAuthManager.shared.signOut()
                            settings.logOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showFolderManager) {
                LibraryFoldersView()
            }
            .navigationDestination(for: Album.self) { album in
                AlbumDetailView(album: album)
            }
            .onChange(of: nowPlaying.navigateToAlbum) { _, album in
                guard let album else { return }
                navigationPath = [album]
                nowPlaying.navigateToAlbum = nil
            }
        }
    }

    // MARK: - Sub-views

    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columnsPerRow),
                spacing: 12
            ) {
                ForEach(filteredAlbums) { album in
                    NavigationLink(value: album) {
                        AlbumCardView(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var scanningView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Scanning library…")
                .font(.headline)
            Text(library.scanProgress)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No Albums Found")
                .font(.title2.bold())
            Text("Make sure your music folder contains sub-folders with audio files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Manage Folders") {
                showFolderManager = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            Text("Scan Failed")
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") {
                Task { await library.scanLibrary(at: settings.musicFolderPaths) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Album Card

struct AlbumCardView: View {
    let album: Album
    @State private var artwork: UIImage?
    @State private var isScanningThisAlbum = false
    @EnvironmentObject var library: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                AlbumArtView(image: artwork, size: .flexible)
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(8)
                    .shadow(radius: 4, y: 2)

                if isScanningThisAlbum {
                    Color.black.opacity(0.4)
                        .cornerRadius(8)
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                }
            }

            Text(album.displayTitle)
                .font(.caption.bold())
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            Text(album.displayArtist)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button {
                Task {
                    isScanningThisAlbum = true
                    await library.rescanTagsForAlbum(album)
                    artwork = await library.loadArtwork(for: album)
                    isScanningThisAlbum = false
                }
            } label: {
                Label("Rescan Tags", systemImage: "arrow.clockwise")
            }
        }
        .task {
            artwork = await library.loadArtwork(for: album)
        }
        .onChange(of: library.scanningAlbumId) { _, newId in
            isScanningThisAlbum = (newId == album.id)
        }
    }
}
