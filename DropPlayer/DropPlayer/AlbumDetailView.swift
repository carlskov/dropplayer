import SwiftUI

/// Shows all tracks in an album and lets the user start playback.
struct AlbumDetailView: View {
    let album: Album

    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var player: PlayerEngine
    @State private var artwork: UIImage?
    @State private var showNowPlaying = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header
                header

                // Track list
                Group {
                    ForEach(Array(sortedTracks.enumerated()), id: \.element.id) { index, track in
                        TrackRowView(
                            track: track,
                            index: index + 1,
                            isPlaying: player.currentTrack?.id == track.id && player.isPlaying
                        )
                        .onTapGesture {
                            player.play(track: track, in: sortedTracks)
                            showNowPlaying = true
                        }
                        Divider().padding(.leading, 52)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .navigationTitle(album.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .task {
            artwork = await library.loadArtwork(for: album)
        }
    }

    // MARK: - Sub-views

    private var header: some View {
        VStack(spacing: 8) {
            AlbumArtView(image: artwork, size: .flexible)
                .containerRelativeFrame(.horizontal) { w, _ in min(w * 0.58, 300) }
                .cornerRadius(12)
                .shadow(radius: 10, y: 4)
                .padding(.top, 12)

            VStack(spacing: 4) {
                Text(album.displayTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(album.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let year = album.year {
                    Text(year)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)

            // Playback controls
            HStack(spacing: 16) {
                Button {
                    player.play(track: sortedTracks[0], in: sortedTracks)
                    showNowPlaying = true
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sortedTracks.isEmpty)

                Button {
                    let shuffled = sortedTracks.shuffled()
                    if let first = shuffled.first {
                        player.play(track: first, in: shuffled)
                        showNowPlaying = true
                    }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(sortedTracks.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
        .padding(.bottom, 4)
    }

    private var sortedTracks: [Track] {
        album.tracks.sorted {
            let d0 = $0.discNumber ?? 1
            let d1 = $1.discNumber ?? 1
            if d0 != d1 { return d0 < d1 }
            let t0 = $0.trackNumber ?? Int.max
            let t1 = $1.trackNumber ?? Int.max
            if t0 != t1 { return t0 < t1 }
            return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }
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
                        .foregroundStyle(.blue)
                } else {
                    Text("\(track.trackNumber ?? index)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, alignment: .center)

            Text(track.displayTitle)
                .font(isPlaying ? .body.bold() : .body)
                .foregroundStyle(isPlaying ? .blue : .primary)
                .lineLimit(1)

            Spacer()

            if let duration = track.durationSeconds {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
