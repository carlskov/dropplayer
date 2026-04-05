import SwiftUI
import AVFoundation

struct NowPlayingView: View {
    @EnvironmentObject var player: PlayerEngine
    @EnvironmentObject var library: LibraryViewModel
    @EnvironmentObject var nowPlaying: NowPlayingCoordinator
    @EnvironmentObject var cast: CastManager

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

                    CastButtonView()
                        .frame(width: 24, height: 24)
                        .frame(maxWidth: .infinity, alignment: .trailing)
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
                    .scaleEffect(effectivePlaying ? 1.0 : 0.88)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: effectivePlaying)
                    .onTapGesture { goToAlbum() }

                trackInfoSection
                    .padding(.horizontal, 24)
                    .padding(.top, 32)

                seekBarSection
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                transportControls
                    .padding(.top, 24)

                AudioRouteView()
                    .padding(.top, 64)

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
                // If already casting, send the new track to the Cast device.
                if cast.isConnected {
                    await cast.loadTrack(track, startTime: 0, album: album, artwork: fetchedArt)
                }
            } else {
                currentAlbum = nil
            }
        }
        .onChange(of: cast.isConnected) { _, isNowConnected in
            if isNowConnected {
                // Pause local playback and hand off to the Cast device.
                player.isCasting = true
                player.pauseForCasting()
                if let track = player.currentTrack {
                    Task {
                        await cast.loadTrack(
                            track,
                            startTime: player.currentTime,
                            album: currentAlbum,
                            artwork: player.currentArtwork
                        )
                    }
                }
            } else {
                // Cast session ended; re-enable local playback.
                player.isCasting = false
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
                MarqueeText(
                    text: trackTitle ?? player.currentTrack?.displayTitle ?? "—",
                    font: .title2.bold(),
                    lineHeight: UIFont.preferredFont(forTextStyle: .title2).lineHeight
                )
                .frame(maxWidth: .infinity)
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
                // if let year = currentAlbum?.year {
                //     Text(year)
                //         .font(.caption)
                //         .foregroundStyle(.tertiary)
                //         .lineLimit(1)
                //         .multilineTextAlignment(.center)
                // }
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

    private var effectivePlaying: Bool {
        cast.isConnected ? cast.isCastPlaying : player.isPlaying
    }

    private var seekBarSection: some View {
        SeekBarView(
            currentTime: cast.isConnected ? cast.castCurrentTime : player.currentTime,
            duration: cast.isConnected ? cast.castDuration : player.duration,
            onSeek: { time in
                if cast.isConnected { cast.seek(to: time) } else { player.seek(to: time) }
            },
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
                if cast.isConnected {
                    cast.togglePlayPause()
                } else if !player.isBuffering {
                    player.togglePlayPause()
                }
            } label: {
                Group {
                    if player.isBuffering && !cast.isConnected {
                        ProgressView()
                            .scaleEffect(1.4)
                    } else {
                        Image(systemName: effectivePlaying ? "pause.fill" : "play.fill")
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

// MARK: - Audio Route

private final class AudioRouteObserver: ObservableObject {
    @Published var portName: String = ""
    @Published var portType: AVAudioSession.Port = .builtInSpeaker

    private var observation: NSObjectProtocol?

    init() {
        update()
        observation = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.update() }
    }

    deinit {
        if let observation { NotificationCenter.default.removeObserver(observation) }
    }

    private func update() {
        let output = AVAudioSession.sharedInstance().currentRoute.outputs.first
        portName = output?.portName ?? ""
        portType = output?.portType ?? .builtInSpeaker
    }
}

private struct AudioRouteView: View {
    @StateObject private var route = AudioRouteObserver()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: route.portType))
                .font(.caption)
            Text(route.portName)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }

    private func iconName(for port: AVAudioSession.Port) -> String {
        switch port {
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            return "hifispeaker.fill"
        case .airPlay:
            return "airplayaudio"
        case .headphones:
            return "headphones"
        case .builtInSpeaker:
            return "iphone.gen3"
        case .builtInReceiver:
            return "iphone.gen3"
        case .carAudio:
            return "car.fill"
        case .HDMI, .displayPort:
            return "tv"
        default:
            return "speaker.wave.2.fill"
        }
    }
}

// MARK: - Marquee Text

private struct MarqueeText: View {
    let text: String
    let font: Font
    let lineHeight: CGFloat

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var needsScroll: Bool { textWidth > containerWidth }

    // Pause at start, scroll across, then loop
    private static let pauseDuration: Double = 2.0
    private static let pixelsPerSecond: Double = 40.0

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width
            ZStack(alignment: .leading) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: needsScroll ? offset : (cw - textWidth) / 2)
                    .background(
                        GeometryReader { inner in
                            Color.clear
                                .onAppear {
                                    textWidth = inner.size.width
                                    containerWidth = cw
                                    startAnimation(containerWidth: cw, textWidth: inner.size.width)
                                }
                                .onChange(of: text) { _, _ in
                                    offset = 0
                                    textWidth = inner.size.width
                                    containerWidth = cw
                                    startAnimation(containerWidth: cw, textWidth: inner.size.width)
                                }
                        }
                    )
            }
            .frame(width: cw, alignment: .leading)
            .clipped()
            .onChange(of: cw) { _, newWidth in
                containerWidth = newWidth
            }
        }
        .frame(height: lineHeight)
    }

    private func startAnimation(containerWidth: CGFloat, textWidth: CGFloat) {
        guard textWidth > containerWidth else { return }
        let scrollDistance = textWidth - containerWidth
        let duration = scrollDistance / Self.pixelsPerSecond

        // Scroll forward
        withAnimation(.linear(duration: 0)) { offset = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pauseDuration) {
            guard textWidth > containerWidth else { return }
            withAnimation(.linear(duration: duration)) { offset = -scrollDistance }

            // Scroll back
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + Self.pauseDuration) {
                guard textWidth > containerWidth else { return }
                withAnimation(.linear(duration: duration)) { offset = 0 }

                // Loop
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + Self.pauseDuration) {
                    startAnimation(containerWidth: containerWidth, textWidth: textWidth)
                }
            }
        }
    }
}
