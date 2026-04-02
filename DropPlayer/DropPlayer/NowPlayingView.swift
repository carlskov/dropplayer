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
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Now Playing")
                        .font(.headline)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                AlbumArtView(image: player.currentArtwork, size: .flexible)
                    // .containerRelativeFrame(.horizontal) { w, _ in min(w * 0.95, 400) }
                    .containerRelativeFrame(.horizontal) { w, _ in w - 48 }
                    .cornerRadius(16)
                    .shadow(radius: 24, y: 12)
                    // .padding(.horizontal, 16)
                    .padding(.top, 48)
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
            trackArtist = player.currentTrack?.artist
            trackTitle = player.currentTrack?.title
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
            VStack(alignment: .center, spacing: 4) {
                Text(trackTitle ?? player.currentTrack?.displayTitle ?? "—")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                Text(trackArtist ?? currentAlbum?.displayArtist ?? "—")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                Text(currentAlbum?.displayTitle ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top,2)
                    .multilineTextAlignment(.center)
                    .onTapGesture { goToAlbum() }
                Text(trackPositionInfo)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.top, 8)
                    // .padding(.bottom)
            }
            .frame(maxWidth: .infinity)
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
        SeekBarView(
            currentTime: player.currentTime,
            duration: player.duration,
            onSeek: { player.seek(to: $0) },
            formatTime: formatTime
        )
    }

    private var transportControls: some View {
        HStack(spacing: 60) {
            Button {
                player.skipBack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 24))
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
                    .font(.system(size: 24))
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

// MARK: - Seek Bar

private struct SeekBarView: View {
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void
    let formatTime: (Double) -> String

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return isDragging ? dragProgress : min(currentTime / duration, 1)
    }

    private var displayTime: Double {
        isDragging ? dragProgress * duration : currentTime
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                let trackHeight: CGFloat = isDragging ? 6 : 4

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(Color.primary)
                        .frame(width: max(0, CGFloat(progress) * width), height: trackHeight)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging { isDragging = true }
                            dragProgress = min(max(Double(value.location.x / width), 0), 1)
                        }
                        .onEnded { value in
                            let p = min(max(Double(value.location.x / width), 0), 1)
                            dragProgress = p
                            onSeek(p * duration)
                            isDragging = false
                        }
                )
                .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
            .frame(height: 20)

            HStack {
                Text(formatTime(displayTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
