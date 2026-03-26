import SwiftUI

/// Full-screen Now Playing sheet.
struct NowPlayingView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var artwork: UIImage?
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Artwork — width set explicitly via containerRelativeFrame so it's always square
                AlbumArtView(image: artwork, size: .flexible)
                    .containerRelativeFrame(.horizontal) { w, _ in w - 64 }
                    .cornerRadius(16)
                    .shadow(radius: 16, y: 8)
                    .scaleEffect(player.isPlaying ? 1.0 : 0.88)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: player.isPlaying)
                    .padding(.top, 8)

                Spacer(minLength: 0)

                // Track info
                trackInfoSection
                    .padding(.horizontal, 32)
                    .padding(.top, 16)

                // Seek bar
                seekBarSection
                    .padding(.horizontal, 28)
                    .padding(.top, 12)

                // Transport controls
                transportControls
                    .padding(.top, 20)
                    .padding(.horizontal, 32)

                // Error
                if let error = player.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }

                Spacer(minLength: 0)
                    .frame(minHeight: 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Now Playing")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: player.currentTrack?.id) {
            if let track = player.currentTrack {
                // Try to find the album containing this track and load its artwork
                if let album = library.albums.first(where: { $0.tracks.contains(where: { $0.id == track.id }) }) {
                    artwork = await library.loadArtwork(for: album)
                }
            }
        }
    }

    // MARK: - Sub-views

    private var trackInfoSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.displayTitle ?? "—")
                    .font(.title3.bold())
                    .lineLimit(1)
                Text(queueInfo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var queueInfo: String {
        guard !player.queue.isEmpty else { return "" }
        return "\(player.currentIndex + 1) of \(player.queue.count)"
    }

    private var seekBarSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...(max(player.duration, 1))
            )
            .tint(.primary)

            HStack {
                Text(formatTime(player.currentTime))
                Spacer()
                Text(formatTime(player.duration))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 48) {
            Button {
                player.skipBack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }

            Button {
                if player.isBuffering {
                    // no-op while buffering
                } else {
                    player.togglePlayPause()
                }
            } label: {
                Group {
                    if player.isBuffering {
                        ProgressView()
                            .scaleEffect(1.4)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44))
                    }
                }
                .frame(width: 56, height: 56)
            }

            Button {
                player.skipForward()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
        }
        .foregroundStyle(.primary)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
