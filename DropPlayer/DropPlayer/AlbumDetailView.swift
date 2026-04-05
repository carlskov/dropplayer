import SwiftUI

/// Shows all tracks in an album and lets the user start playback.
struct AlbumDetailView: View {
    let album: Album

    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var nowPlaying: NowPlayingCoordinator
    @Environment(\.colorScheme) var colorScheme
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
                    .padding(.bottom, 128)
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
                    .scaleEffect(0.95)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            // .padding(.bottom, 4)

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
                        .foregroundColor(colorScheme == .light ? Theme.darkAccentColor : Theme.lighterAccentColor)
                }
                // .buttonStyle(Theme.adaptiveBorderedButtonStyle())
                .buttonStyle(.bordered)
                // .background(Color.clear)
                //.tint(colorScheme == .light ? Theme.lighterAccentColor : Theme.accentColor)
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
                        // .foregroundColor(colorScheme == .light ? Theme.accentColor : Theme.lighterAccentColor)
                        .foregroundColor(colorScheme == .light ? Theme.darkAccentColor : Theme.lighterAccentColor)
                }
                .buttonStyle(.bordered)
                // .buttonStyle(Theme.adaptiveBorderedButtonStyle())
                //.tint(colorScheme == .light ? Theme.lighterAccentColor : Theme.accentColor)
                .controlSize(.large)
                .disabled(sortedTracks.isEmpty)
            }
            .padding(.horizontal)
            // .padding(.top, 4)
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
                        .foregroundStyle(Theme.nowPlayingAccentColor)
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
                    .foregroundStyle(isPlaying ? Theme.nowPlayingAccentColor : .primary)
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

    var body: some View {
        ZoomScrollView(image: image, onDismiss: { dismiss() })
            .ignoresSafeArea()
    }
}

private struct ZoomScrollView: UIViewRepresentable {
    let image: UIImage?
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        context.coordinator.container = container

        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.bouncesZoom = true
        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.scrollView = scrollView
        container.addSubview(scrollView)

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        context.coordinator.imageView = imageView
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSingleTap)
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        let dismissPan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDismissPan(_:))
        )
        dismissPan.delegate = context.coordinator
        container.addGestureRecognizer(dismissPan)
        context.coordinator.dismissPan = dismissPan

        return container
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var container: UIView?
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        weak var dismissPan: UIPanGestureRecognizer?
        let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView = imageView else { return }
            let offsetX = max((scrollView.bounds.width - imageView.frame.width) / 2, 0)
            let offsetY = max((scrollView.bounds.height - imageView.frame.height) / 2, 0)
            imageView.center = CGPoint(
                x: scrollView.contentSize.width / 2 + offsetX,
                y: scrollView.contentSize.height / 2 + offsetY
            )
        }

        // Allow the dismiss pan to run at the same time as the scroll view's pan
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === dismissPan
        }

        // Only begin the dismiss pan when not zoomed in and gesture is primarily downward
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === dismissPan,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let scrollView = scrollView else { return true }
            guard scrollView.zoomScale == 1.0 else { return false }
            let v = pan.velocity(in: container)
            return v.y > abs(v.x)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = scrollView else { return }
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let location = gesture.location(in: imageView)
                let size = CGSize(
                    width: scrollView.bounds.width / 2.0,
                    height: scrollView.bounds.height / 2.0
                )
                let rect = CGRect(
                    x: location.x - size.width / 2,
                    y: location.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }

        @objc func handleSingleTap() {
            onDismiss()
        }

        @objc func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
            guard let container = container else { return }
            let translation = gesture.translation(in: container)
            let ty = max(0, translation.y)

            switch gesture.state {
            case .began:
                scrollView?.isScrollEnabled = false

            case .changed:
                container.transform = CGAffineTransform(translationX: 0, y: ty)
                container.alpha = 1 - min(ty / 300, 0.5)

            case .ended, .cancelled:
                scrollView?.isScrollEnabled = true
                let velocity = gesture.velocity(in: container)
                if ty > 120 || velocity.y > 600 {
                    UIView.animate(withDuration: 0.25, animations: {
                        container.transform = CGAffineTransform(
                            translationX: 0, y: container.bounds.height + ty
                        )
                        container.alpha = 0
                    }) { _ in self.onDismiss() }
                } else {
                    UIView.animate(
                        withDuration: 0.35, delay: 0,
                        usingSpringWithDamping: 0.75, initialSpringVelocity: 0
                    ) {
                        container.transform = .identity
                        container.alpha = 1
                    }
                }

            default:
                break
            }
        }
    }
}
