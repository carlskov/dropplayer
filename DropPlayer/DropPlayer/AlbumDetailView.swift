import SwiftUI

/// Shows all tracks in an album and lets the user start playback.
struct AlbumDetailView: View {
    let album: Album

    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var nowPlaying: NowPlayingCoordinator
    @State private var artwork: UIImage?
    @State private var isFullscreenArtwork = false

    private func playTrack(_ track: Track) {
        player.play(track: track, in: sortedTracks, album: album)
        nowPlaying.isPresented = true
        Task {
            let image = await library.loadArtwork(for: album)
            player.updateArtwork(image)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header

                ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                    VStack(spacing: 0) {
                        if isMultiDisc && (index == 0 || track.discNumber != sortedTracks[index - 1].discNumber) {
                            DiscHeaderView(discNumber: track.discNumber ?? 1)
                        }
                        TrackRowView(
                            track: track,
                            index: trackNumberForDisc(track: track, at: index),
                            isPlaying: player.currentTrack?.id == track.id && player.isPlaying
                        )
                        .onTapGesture {
                            playTrack(track)
                        }
                    }
                }
                .padding(.bottom, 16)

                labelFooter
                    .padding(.horizontal, 16)
                    .padding(.top, 0)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle(album.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            artwork = await library.loadArtwork(for: album)
            // Only push to the player/widget when this album is actually playing
            if album.tracks.contains(where: { $0.id == player.currentTrack?.id }) {
                player.updateArtwork(artwork)
            }
        }
        .fullScreenCover(isPresented: $isFullscreenArtwork) {
            ZoomableImageView(image: artwork)
                .ignoresSafeArea()
                .background(Color.black)
        }
    }

    private var isMultiDisc: Bool {
        let uniqueDiscs = Set(album.tracks.map { $0.discNumber ?? 1 })
        return uniqueDiscs.count > 1
    }

    private func trackNumberForDisc(track: Track, at sortedIndex: Int) -> Int {
        if album.discNumber != nil || album.tracks.contains(where: { $0.discNumber != nil && $0.discNumber != 1 }) {
            // Multi-disc album: count tracks within this disc
            let currentDisc = track.discNumber ?? 1
            var count = 0
            for t in sortedTracks {
                if t.discNumber ?? 1 < currentDisc { continue }
                if t.discNumber ?? 1 > currentDisc { break }
                count += 1
                if t.id == track.id { break }
            }
            return count
        }
        return track.trackNumber ?? (sortedIndex + 1)
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(spacing: 16) {
            Button {
                isFullscreenArtwork = true
            } label: {
                AlbumArtView(image: artwork, size: .flexible)
                    .cornerRadius(16)
                    .clipped()
                    .shadow(radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            VStack(spacing: 4) {
                Text(album.displayTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    // .padding(.bottom, 2)
                Text(album.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let year = album.year {
                    Text([year, album.label, album.genre].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let genre = album.genre, !genre.isEmpty {
                    Text(genre) 
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            // .padding(.bottom, 8)

            HStack(spacing: 12) {
                Button {
                    player.play(track: sortedTracks[0], in: sortedTracks, album: album)
                    nowPlaying.isPresented = true
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accentColor)
                .controlSize(.large)
                .disabled(sortedTracks.isEmpty)

                Button {
                    let shuffled = sortedTracks.shuffled()
                    if let first = shuffled.first {
                        player.play(track: first, in: shuffled, album: album)
                        nowPlaying.isPresented = true
                    }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.bordered)
                .tint(Theme.accentColor)
                .controlSize(.large)
                .disabled(sortedTracks.isEmpty)
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .padding(.bottom, 4)
    }

    private var sortedTracks: [Track] {
        let hasTrackNumbers = album.tracks.contains(where: { $0.trackNumber != nil })
        if hasTrackNumbers {
            return album.tracks.sorted {
                let d0 = $0.discNumber ?? 1
                let d1 = $1.discNumber ?? 1
                if d0 != d1 { return d0 < d1 }
                return ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max)
            }
        }
        return album.tracks
    }

    private var labelFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            let count = sortedTracks.count
            Text("\(count) \(count == 1 ? "song" : "songs")")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let copyright = album.copyright {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Track row

struct TrackRowView: View {
    let track: Track
    let index: Int
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Track number / playing indicator
            ZStack {
                if isPlaying {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                        .foregroundStyle(Theme.accentColor)
                } else {
                    Text("\(track.trackNumber ?? index)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(isPlaying ? .body.bold() : .body)
                    .foregroundStyle(isPlaying ? Theme.accentColor : .primary)
                    .lineLimit(1)
                if let artist = track.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let duration = track.durationSeconds {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Disc Header

struct DiscHeaderView: View {
    let discNumber: Int

    var body: some View {
        HStack {
            Text("Disc \(discNumber)")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation(.spring()) {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.0 {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.0
                                lastScale = 2.0
                            }
                        }
                    }
                    .onTapGesture {
                        dismiss()
                    }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.5))
                    .onTapGesture {
                        dismiss()
                    }
            }
        }
    }
}
