import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var nowPlaying: NowPlayingCoordinator

    @State private var currentAlbum: Album?
    @State private var trackArtist: String?
    @State private var trackTitle: String?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Now Playing")
                        .font(.headline)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                AlbumArtView(image: player.currentArtwork, size: .flexible)
                    .containerRelativeFrame(.horizontal) { w, _ in min(w * 0.82, 400) }
                    .cornerRadius(16)
                    .shadow(radius: 24, y: 12)
                    .scaleEffect(player.isPlaying ? 1.0 : 0.88)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: player.isPlaying)
                    .onTapGesture { goToAlbum() }

                trackInfoSection
                    .padding(.horizontal, 24)
                    .padding(.top, 32)

                seekBarSection
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                transportControls
                    .padding(.top, 24)

                if let error = player.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 16)
                }

                Spacer()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.height > 0 && abs(value.translation.height) > abs(value.translation.width) {
                        dismiss()
                    }
                }
        )
        .task(id: player.currentTrack?.id) {
            trackArtist = nil
            trackTitle = nil
            if let track = player.currentTrack,
               let album = library.albums.first(where: { $0.tracks.contains(where: { $0.id == track.id }) }) {
                currentAlbum = album
                async let meta = library.loadTrackMetadata(for: track)
                async let art = library.loadArtwork(for: album)
                let (fetchedMeta, fetchedArt) = await (meta, art)
                trackArtist = fetchedMeta.artist
                trackTitle = fetchedMeta.title
                player.updateArtwork(fetchedArt)
                player.updateAlbum(album)
            } else {
                currentAlbum = nil
            }
        }
    }

    private func dismiss() {
        nowPlaying.isPresented = false
    }

    private func goToAlbum() {
        guard let album = currentAlbum else { return }
        nowPlaying.isPresented = false
        // Small delay so the sheet dismissal animates before the push
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            nowPlaying.navigateToAlbum = album
        }
    }

    // MARK: - Sub-views

    private var trackInfoSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(trackTitle ?? player.currentTrack?.displayTitle ?? "—")
                    .font(.title2.bold())
                    .lineLimit(1)
                Text(trackArtist ?? currentAlbum?.displayArtist ?? "—")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(currentAlbum?.displayTitle ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .onTapGesture { goToAlbum() }
                Text(trackPositionInfo)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var trackPositionInfo: String {
        guard let trackNumber = player.currentTrack?.trackNumber else { return "" }
        if let total = currentAlbum.map({ $0.tracks.count }), total > 0 {
            return "Track \(trackNumber) of \(total)"
        }
        return "Track \(trackNumber)"
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
        HStack(spacing: 60) {
            Button {
                player.skipBack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 32))
            }

            Button {
                if !player.isBuffering {
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
            }

            Button {
                player.skipForward()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 32))
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
