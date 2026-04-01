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
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Group {
                        if let image = artwork {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                        } else {
                            Image(systemName: "music.note")
                                .font(.title3)
                                .foregroundStyle(.secondary)
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
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.skipForward()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                }
                
                if player.duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                            Rectangle()
                                .fill(Theme.accentColor)
                                .frame(width: geo.size.width * CGFloat(player.currentTime / player.duration))
                        }
                    }
                    .frame(height: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 6, y: -2)
            .padding(.horizontal, 12)
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
