import Foundation
import AVFoundation
import MediaPlayer
import Combine

/// Controls audio playback via AVPlayer, backed by Dropbox temporary links.
@MainActor
final class PlayerEngine: NSObject, ObservableObject {
    // MARK: - Published state
    @Published var currentTrack: Track?
    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0

    @Published var isPlaying = false
    @Published var isBuffering = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var errorMessage: String?
    /// When true, local audio playback is suppressed so the Cast device plays instead.
    var isCasting: Bool = false

    // MARK: - Private
    private var player = AVPlayer()
    private var timeObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()
    @Published var currentArtwork: UIImage?
    private var currentAlbum: Album?

    override init() {
        super.init()
        configureAudioSession()
        setupRemoteCommandCenter()
        startTimeObserver()
    }

    // MARK: - Public API

    func play(track: Track, in tracks: [Track], album: Album? = nil) {
        queue = tracks
        currentIndex = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
        currentAlbum = album
        loadAndPlay(track: track)
    }

    func updateArtwork(_ image: UIImage?) {
        currentArtwork = image
        updateNowPlayingInfo()
    }

    func updateAlbum(_ album: Album?) {
        currentAlbum = album
        updateNowPlayingInfo()
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }

    func pauseForCasting() {
        player.pause()
        isPlaying = false
    }

    func skipForward() {
        let next = currentIndex + 1
        guard next < queue.count else { return }
        currentIndex = next
        if isCasting {
            // Only advance the track pointer; Cast device will load the new track.
            currentTrack = queue[next]
        } else {
            loadAndPlay(track: queue[next])
        }
    }

    func skipBack() {
        if isCasting {
            let prev = currentIndex - 1
            guard prev >= 0 else { return }
            currentIndex = prev
            currentTrack = queue[prev]
        } else if currentTime > 3 {
            seek(to: 0)
        } else {
            let prev = currentIndex - 1
            guard prev >= 0 else { return }
            currentIndex = prev
            loadAndPlay(track: queue[prev])
        }
    }

    func seek(to time: Double) {
        let target = CMTime(seconds: time, preferredTimescale: 1000)
        player.seek(to: target)
        currentTime = time
    }

    // MARK: - Loading

    private func loadAndPlay(track: Track) {
        currentTrack = track
        currentArtwork = nil
        isPlaying = false
        isBuffering = true
        errorMessage = nil
        currentTime = 0
        duration = 0

        Task {
            do {
                let url = try await DropboxBrowserService.shared.temporaryLink(for: track.dropboxPath)
                await startPlayback(url: url, track: track)
            } catch {
                isBuffering = false
                errorMessage = "Could not load track: \(error.localizedDescription)"
            }
        }
    }

    private func startPlayback(url: URL, track: Track) async {
        var assetOptions: [String: Any] = [:]
        if let typeID = utTypeIdentifier(for: track.fileName) {
            assetOptions[AVURLAssetPreferPreciseDurationAndTimingKey] = true
            assetOptions["AVURLAssetTypeIdentifierKey"] = typeID
        }
        let asset = AVURLAsset(url: url, options: assetOptions.isEmpty ? nil : assetOptions)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)

        // Observe buffering / ready state
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    self.isBuffering = false
                    if !self.isCasting {
                        self.player.play()
                        self.isPlaying = true
                    }
                    self.updateNowPlayingInfo()
                case .failed:
                    self.isBuffering = false
                    self.errorMessage = item.error?.localizedDescription ?? "Playback failed"
                default:
                    break
                }
            }
        }

        // Auto-advance
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    @objc private func itemDidFinish() {
        skipForward()
    }

    // MARK: - Audio Session

    private func utTypeIdentifier(for fileName: String) -> String? {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "aiff", "aif": return "public.aiff-audio"
        case "wav":          return "com.microsoft.waveform-audio"
        case "flac":         return "org.xiph.flac"
        case "mp3":          return "public.mp3"
        case "m4a":          return "com.apple.m4a-audio"
        case "aac":          return "public.aac-audio"
        default:             return nil
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    // MARK: - Time observer

    private func startTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, self.isPlaying else { return }
            self.currentTime = time.seconds
        }
    }

    // MARK: - Lock screen / Control Center

    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player.play()
            self.isPlaying = true
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player.pause()
            self.isPlaying = false
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipBack()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: e.positionTime)
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        let artist = track.artist ?? currentAlbum?.displayArtist
        if let artist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let albumTitle = currentAlbum?.displayTitle {
            info[MPMediaItemPropertyAlbumTitle] = albumTitle
        }
        if let image = currentArtwork {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
