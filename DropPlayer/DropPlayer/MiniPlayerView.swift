import SwiftUI

/// Persistent mini player bar shown above the tab bar.
struct MiniPlayerView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var nowPlaying: NowPlayingCoordinator
    @State private var artwork: UIImage?

    var body: some View {
        Button {
            nowPlaying.isPresented = true
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let image = artwork {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray6))
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.displayTitle ?? "")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if player.isBuffering {
                        Text("Buffering…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        let artist = player.currentTrack?.artist
                            ?? library.albums.first(where: { $0.tracks.contains(where: { $0.id == player.currentTrack?.id }) })?.displayArtist
                        if let artist {
                            Text(artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

        Button {
            player.togglePlayPause()
            if let track = player.currentTrack,
               let album = library.albums.first(where: { $0.tracks.contains(where: { $0.id == track.id }) }) {
                Task { _ = await library.loadArtwork(for: album) }
            }
        } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }

                Button {
                    player.skipForward()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 4, y: -1)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .task(id: player.currentTrack?.id) {
            artwork = nil
            if let track = player.currentTrack,
               let album = library.albums.first(where: { $0.tracks.contains(where: { $0.id == track.id }) }) {
                artwork = await library.loadArtwork(for: album)
            }
        }
    }
}
