import SwiftUI

/// The main library screen — a grid of album cards.
struct AlbumListView: View {
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var settings: AppSettings

    @State private var showFolderPicker = false
    @State private var searchText = ""

    private var filteredAlbums: [Album] {
        guard !searchText.isEmpty else { return library.albums }
        return library.albums.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            $0.displayArtist.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            if let path = settings.musicFolderPath {
                                Task { await library.rescanLibrary(at: path) }
                            }
                        } label: {
                            Label("Rescan Library", systemImage: "arrow.clockwise")
                        }

                        Button {
                            showFolderPicker = true
                        } label: {
                            Label("Change Folder", systemImage: "folder")
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
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(isInitialSetup: false)
            }
        }
    }

    // MARK: - Sub-views

    private var albumGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)],
                spacing: 12
            ) {
                ForEach(filteredAlbums) { album in
                    NavigationLink(destination: AlbumDetailView(album: album)) {
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
            Button("Change Folder") {
                showFolderPicker = true
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
                if let path = settings.musicFolderPath {
                    Task { await library.scanLibrary(at: path) }
                }
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
    @EnvironmentObject var library: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AlbumArtView(image: artwork, size: .flexible)
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(8)
                .shadow(radius: 4, y: 2)

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
        .task {
            artwork = await library.loadArtwork(for: album)
        }
    }
}
