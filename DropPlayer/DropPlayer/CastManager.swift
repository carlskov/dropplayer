import Foundation
import GoogleCast
import UIKit
import SwiftUI
import Combine

// MARK: - CastManager

/// Manages the Google Cast session lifecycle and remote media playback.
@MainActor
final class CastManager: NSObject, ObservableObject {

    /// Use the default media receiver so no Cast Developer Console registration is needed.
    /// Replace with your own registered App ID for a custom receiver.
    static let receiverAppID = kGCKDefaultMediaReceiverApplicationID

    // MARK: - Published state

    @Published var castState: GCKCastState = .noDevicesAvailable
    @Published var isConnected: Bool = false
    @Published var isCastPlaying: Bool = false
    @Published var castCurrentTime: Double = 0
    @Published var castDuration: Double = 0

    // MARK: - Private

    private var castStateObservation: NSKeyValueObservation?
    private var progressTimer: Timer?
    private var trackCancellable: AnyCancellable?
    private weak var playerEngine: PlayerEngine?
    private weak var libraryViewModel: LibraryViewModel?

    // MARK: - Init

    override init() {
        super.init()
        castStateObservation = GCKCastContext.sharedInstance()
            .observe(\.castState, options: [.initial, .new]) { [weak self] context, _ in
                Task { @MainActor [weak self] in
                    self?.castState = context.castState
                }
            }
        GCKCastContext.sharedInstance().sessionManager.add(self)
    }

    deinit {
        castStateObservation?.invalidate()
        progressTimer?.invalidate()
    }

    // MARK: - Setup

    /// Call once at app startup to wire CastManager to the player and library.
    func setup(player: PlayerEngine, library: LibraryViewModel) {
        playerEngine = player
        libraryViewModel = library

        // React whenever the current track changes (covers play-from-any-view).
        trackCancellable = player.$currentTrack
            .receive(on: RunLoop.main)
            .sink { [weak self] track in
                self?.handleTrackChange(track)
            }
    }

    private func handleTrackChange(_ track: Track?) {
        guard isConnected, let track,
              let player = playerEngine, let library = libraryViewModel else { return }
        let album = library.albums.first(where: { $0.tracks.contains(where: { $0.id == track.id }) })
        Task { [weak self, weak player] in
            guard let self, let player else { return }
            await self.loadTrack(track, startTime: 0, album: album, artwork: player.currentArtwork)
        }
    }

    private func handleCurrentTrackOnConnect() {
        guard let player = playerEngine, let track = player.currentTrack,
              let library = libraryViewModel else { return }
        player.isCasting = true
        player.pauseForCasting()
        let album = library.albums.first(where: { $0.tracks.contains(where: { $0.id == track.id }) })
        let startTime = player.currentTime
        Task { [weak self, weak player] in
            guard let self, let player else { return }
            await self.loadTrack(track, startTime: startTime, album: album, artwork: player.currentArtwork)
        }
    }

    // MARK: - Computed helpers

    private var remoteMediaClient: GCKRemoteMediaClient? {
        GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient
    }

    // MARK: - Media loading

    /// Fetches a fresh Dropbox temporary link and loads it onto the Cast device.
    func loadTrack(_ track: Track, startTime: Double = 0, album: Album?, artwork: UIImage?) async {
        do {
            let url = try await DropboxBrowserService.shared.temporaryLink(for: track.dropboxPath)
            sendToReceiver(url: url, track: track, startTime: startTime, album: album, artwork: artwork)
        } catch {
            print("[CastManager] Failed to get temporary link: \(error)")
        }
    }

    private func sendToReceiver(url: URL, track: Track, startTime: Double, album: Album?, artwork: UIImage?) {
        guard let client = remoteMediaClient else { return }

        let metadata = GCKMediaMetadata(metadataType: .musicTrack)
        metadata.setString(track.displayTitle, forKey: kGCKMetadataKeyTitle)
        if let artist = track.artist {
            metadata.setString(artist, forKey: kGCKMetadataKeyArtist)
        }
        if let albumTitle = album?.displayTitle {
            metadata.setString(albumTitle, forKey: kGCKMetadataKeyAlbumTitle)
        }

        let infoBuilder = GCKMediaInformationBuilder(contentURL: url)
        infoBuilder.streamType = .buffered
        infoBuilder.contentType = mimeType(for: track.fileName)
        infoBuilder.metadata = metadata
        if let dur = track.durationSeconds {
            infoBuilder.streamDuration = dur
        }

        let requestBuilder = GCKMediaLoadRequestDataBuilder()
        requestBuilder.mediaInformation = infoBuilder.build()
        requestBuilder.startTime = startTime

        let request = client.loadMedia(with: requestBuilder.build())
        request.delegate = self
    }

    // MARK: - Playback control

    func togglePlayPause() {
        guard let client = remoteMediaClient else { return }
        if isCastPlaying {
            client.pause()
        } else {
            client.play()
        }
    }

    func seek(to time: Double) {
        guard let client = remoteMediaClient else { return }
        let options = GCKMediaSeekOptions()
        options.interval = time
        options.resumeState = isCastPlaying ? .play : .pause
        client.seek(with: options)
        castCurrentTime = time
    }

    // MARK: - Progress polling

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollProgress() }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func pollProgress() {
        guard let status = remoteMediaClient?.mediaStatus else { return }
        castCurrentTime = status.streamPosition
        castDuration = status.mediaInformation?.streamDuration ?? castDuration
        isCastPlaying = status.playerState == .playing
    }

    // MARK: - Helpers

    private func mimeType(for fileName: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "mp3":              return "audio/mpeg"
        case "m4a", "aac":      return "audio/mp4"
        case "flac":             return "audio/flac"
        case "wav":              return "audio/wav"
        case "ogg":              return "audio/ogg"
        case "aiff", "aif":     return "audio/aiff"
        default:                 return "audio/mpeg"
        }
    }
}

// MARK: - GCKSessionManagerListener

extension CastManager: GCKSessionManagerListener {

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager,
                                    didStart session: GCKCastSession) {
        Task { @MainActor [weak self] in
            self?.isConnected = true
            self?.startProgressTimer()
            self?.handleCurrentTrackOnConnect()
        }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager,
                                    didResumeCastSession session: GCKCastSession) {
        Task { @MainActor [weak self] in
            self?.isConnected = true
            self?.startProgressTimer()
            self?.handleCurrentTrackOnConnect()
        }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager,
                                    didEnd session: GCKSession,
                                    withError error: Error?) {
        Task { @MainActor [weak self] in
            self?.isConnected = false
            self?.isCastPlaying = false
            self?.stopProgressTimer()
            self?.playerEngine?.isCasting = false
        }
    }

    nonisolated func sessionManager(_ sessionManager: GCKSessionManager,
                                    didSuspend session: GCKSession,
                                    with reason: GCKConnectionSuspendReason) {
        Task { @MainActor [weak self] in
            self?.isConnected = false
            self?.stopProgressTimer()
            self?.playerEngine?.isCasting = false
        }
    }
}

// MARK: - GCKRequestDelegate

extension CastManager: GCKRequestDelegate {
    nonisolated func requestDidComplete(_ request: GCKRequest) {
        Task { @MainActor [weak self] in
            self?.startProgressTimer()
        }
    }

    nonisolated func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        print("[CastManager] Request failed: \(error.localizedDescription)")
    }
}

// MARK: - SwiftUI Cast Button

/// Wraps `GCKUICastButton` for use in SwiftUI. Tapping opens the Cast device picker.
struct CastButtonView: UIViewRepresentable {
    var tintColor: UIColor = .label

    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        button.tintColor = tintColor
        return button
    }

    func updateUIView(_ uiView: GCKUICastButton, context: Context) {
        uiView.tintColor = tintColor
    }
}
