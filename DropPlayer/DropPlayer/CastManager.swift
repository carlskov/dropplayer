import Foundation
import GoogleCast
import UIKit
import SwiftUI
import Combine
import AVFoundation

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
    private let proxy = AudioTranscodeProxy()
    private let bufferedServer = LocalAudioServer()
    private var transcodeTask: Task<Void, Never>?
    private var currentTranscodedURL: URL?
    // AIFF live-stream context — used for Range-based seeking during Phase 1.
    private var currentAIFFDropboxURL: URL?
    private var currentAIFFTrack: Track?
    private var currentAIFFAlbum: Album?
    private var currentAIFFArtwork: UIImage?

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
        proxy.start()
        bufferedServer.start()
    }

    deinit {
        castStateObservation?.invalidate()
        progressTimer?.invalidate()
        transcodeTask?.cancel()
        proxy.stop()
        bufferedServer.stop()
        if let url = currentTranscodedURL { try? FileManager.default.removeItem(at: url) }
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
        // Cancel any in-progress background transcode for a previous track.
        transcodeTask?.cancel()
        do {
            let url = try await DropboxBrowserService.shared.temporaryLink(for: track.dropboxPath)
            let ext = URL(fileURLWithPath: track.fileName).pathExtension.lowercased()
            if ext == "aiff" || ext == "aif" {
                await castAIFF(dropboxURL: url, track: track, startTime: startTime, album: album, artwork: artwork)
            } else {
                currentAIFFDropboxURL = nil
                sendToReceiver(url: url, track: track, startTime: startTime, album: album, artwork: artwork, streamType: .buffered)
            }
        } catch {
            print("[CastManager] Failed to get temporary link: \(error)")
        }
    }

    /// Phase 1: Start a live transcoding stream immediately so Cast plays within seconds.
    /// Phase 2: In the background, download the full file and transcode to a seekable M4A,
    ///          then swap Cast to the buffered version preserving the current playback position.
    private func castAIFF(dropboxURL: URL, track: Track, startTime: Double, album: Album?, artwork: UIImage?) async {
        // Cancel any previous background transcode.
        transcodeTask?.cancel()
        if let old = currentTranscodedURL { try? FileManager.default.removeItem(at: old); currentTranscodedURL = nil }

        // Store context for seek-triggered stream restarts.
        currentAIFFDropboxURL = dropboxURL
        currentAIFFTrack      = track
        currentAIFFAlbum      = album
        currentAIFFArtwork    = artwork

        guard let ip = localIPAddress() else {
            print("[CastManager] No local IP")
            return
        }
        if proxy.port == 0 || bufferedServer.port == 0 {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        // ── Phase 1: start live stream ──
        proxy.serveTranscoded(from: dropboxURL)
        guard let liveURL = URL(string: "http://\(ip):\(proxy.port)/stream.aac") else { return }
        sendToReceiver(url: liveURL, track: track, startTime: 0, album: album, artwork: artwork, streamType: .live)

        // ── Phase 2: transcode in background, then swap to buffered ──
        transcodeTask = Task { [weak self] in
            guard let self else { return }
            let downloadTemp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("aif")
            let exportURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")

            do {
                let (tmp, _) = try await URLSession.shared.download(from: dropboxURL)
                try FileManager.default.moveItem(at: tmp, to: downloadTemp)
            } catch {
                print("[CastManager] AIFF background download failed: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: downloadTemp)
                return
            }
            defer { try? FileManager.default.removeItem(at: downloadTemp) }

            let asset = AVURLAsset(url: downloadTemp, options: [
                "AVURLAssetTypeIdentifierKey": "public.aiff-audio",
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return }
            session.outputURL = exportURL
            session.outputFileType = .m4a
            await session.export()

            guard !Task.isCancelled, session.status == .completed else {
                try? FileManager.default.removeItem(at: exportURL)
                return
            }

            await MainActor.run { [weak self] in
                guard let self, self.isConnected else {
                    try? FileManager.default.removeItem(at: exportURL)
                    return
                }
                self.currentTranscodedURL = exportURL
                self.bufferedServer.serve(fileAt: exportURL, mimeType: "audio/mp4")
                guard let bufferedURL = URL(string: "http://\(ip):\(self.bufferedServer.port)/track.m4a") else { return }
                // Preserve current playback position when swapping streams.
                let resumeAt = self.castCurrentTime
                self.sendToReceiver(url: bufferedURL, track: track, startTime: resumeAt,
                                    album: album, artwork: artwork, streamType: .buffered)
            }
        }
    }

    private func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            let ifa = ptr!.pointee
            guard ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name == "en0" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
        }
        return address
    }

    private func sendToReceiver(url: URL, track: Track, startTime: Double, album: Album?, artwork: UIImage?, streamType: GCKMediaStreamType) {
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
        infoBuilder.streamType = streamType
        infoBuilder.contentType = streamType == .live ? "audio/aac" : mimeType(for: track.fileName)
        infoBuilder.metadata = metadata
        if streamType != .live, let dur = track.durationSeconds {
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
        // During Phase 1 (live AIFF stream, buffered M4A not yet ready) restart
        // the proxy from the requested sample position using an HTTP Range request.
        if let aiffURL = currentAIFFDropboxURL,
           currentTranscodedURL == nil,
           let info = proxy.cachedInfo,
           let track = currentAIFFTrack,
           let ip = localIPAddress() {
            transcodeTask?.cancel()
            let sampleOffset = Int(time * info.sampleRate)
            proxy.serveTranscoded(from: aiffURL, startSample: sampleOffset)
            // Append a cache-busting query param so Cast treats this as a new URL
            // and opens a fresh connection to the proxy.
            guard let liveURL = URL(string: "http://\(ip):\(proxy.port)/stream.aac?t=\(Int(time))") else { return }
            sendToReceiver(url: liveURL, track: track, startTime: 0,
                           album: currentAIFFAlbum, artwork: currentAIFFArtwork, streamType: .live)
            castCurrentTime = time
        } else {
            guard let client = remoteMediaClient else { return }
            let options = GCKMediaSeekOptions()
            options.interval = time
            options.resumeState = isCastPlaying ? .play : .pause
            client.seek(with: options)
            castCurrentTime = time
        }
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
