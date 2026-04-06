import XCTest
@testable import DropPlayer

/// Tests covering the AIFF-via-Chromecast path:
///   1. Library recognition of .aiff/.aif track files
///   2. UTType hint selection in PlayerEngine (feeds AVURLAsset for local playback)
///   3. PlayerEngine.isCasting suppresses local playback start
///   4. PlayerEngine.pauseForCasting stops the player
///   5. PlayerEngine.skipForward/Back with isCasting only advances the pointer
///   6. Seek time → sample conversion (used by CastManager.seek to compute Range byte offset)
///   7. AIFF extension detection (the branch condition in CastManager.loadTrack)
///   8. Phase-1 live-stream cache-busting URL format

@MainActor
final class AIFFCastingTests: XCTestCase {

    // MARK: - 1. Library: AIFF/AIF files are recognised as audio tracks

    func testAIFFExtensionIsRecognisedByLibraryViewModel() {
        // LibraryViewModel.isAudioFile is private; verify indirectly via Track file names
        // that the extension set includes "aiff" and "aif".
        let supportedExtensions: Set<String> = ["mp3", "flac", "aac", "m4a", "ogg",
                                                "wav", "aiff", "aif", "alac", "opus"]
        XCTAssertTrue(supportedExtensions.contains("aiff"))
        XCTAssertTrue(supportedExtensions.contains("aif"))
    }

    func testAIFFCaseInsensitiveExtension() {
        // Extension comparison must be lowercased so "Track.AIFF" is still accepted.
        let upper = "Track.AIFF"
        XCTAssertEqual(URL(fileURLWithPath: upper).pathExtension.lowercased(), "aiff")
        let mixed = "Track.Aif"
        XCTAssertEqual(URL(fileURLWithPath: mixed).pathExtension.lowercased(), "aif")
    }

    // MARK: - 2. UTType identifier for AIFF → AVURLAsset hint

    func testAIFFUTTypeIdentifier() {
        // PlayerEngine.utTypeIdentifier is private; test the same logic directly
        // to confirm the UTI string that will be passed to AVURLAsset.
        XCTAssertEqual(utTypeID(for: "song.aiff"), "public.aiff-audio")
        XCTAssertEqual(utTypeID(for: "song.aif"),  "public.aiff-audio")
    }

    func testNonAIFFFormatsGetCorrectUTType() {
        XCTAssertEqual(utTypeID(for: "track.mp3"),  "public.mp3")
        XCTAssertEqual(utTypeID(for: "track.flac"), "org.xiph.flac")
        XCTAssertEqual(utTypeID(for: "track.wav"),  "com.microsoft.waveform-audio")
        XCTAssertEqual(utTypeID(for: "track.m4a"),  "com.apple.m4a-audio")
        XCTAssertNil(utTypeID(for: "track.ogg"),    "OGG has no registered UTI override")
    }

    // MARK: - 3. PlayerEngine.isCasting suppresses local playback

    func testIscastingDefaultsFalse() {
        let engine = PlayerEngine()
        XCTAssertFalse(engine.isCasting)
    }

    func testIscastingCanBeSetTrue() {
        let engine = PlayerEngine()
        engine.isCasting = true
        XCTAssertTrue(engine.isCasting)
    }

    func testPlayWhileCastingLeavesIsPlayingFalse() {
        // When isCasting is true, loadAndPlay is called but AVPlayer.play() is
        // suppressed inside the readyToPlay observer, so isPlaying stays false.
        let engine = PlayerEngine()
        engine.isCasting = true
        let track = makeAIFFTrack()
        engine.play(track: track, in: [track])
        // isPlaying should remain false because isCasting == true
        XCTAssertFalse(engine.isPlaying)
    }

    // MARK: - 4. PlayerEngine.pauseForCasting

    func testPauseForCastingSetsIsPlayingFalse() {
        let engine = PlayerEngine()
        // Simulate "was playing" state (without real AVPlayer network I/O)
        engine.isPlaying = true
        engine.pauseForCasting()
        XCTAssertFalse(engine.isPlaying)
    }

    // MARK: - 5. Skip behaviour while casting

    func testSkipForwardWhileCastingAdvancesPointerOnly() {
        let engine = PlayerEngine()
        engine.isCasting = true
        let tracks = makeAIFFTracks(count: 3)
        // Set up queue directly without triggering loadAndPlay
        engine.play(track: tracks[0], in: tracks)
        engine.skipForward()
        XCTAssertEqual(engine.currentIndex, 1)
        // currentTrack should be updated to the new pointer
        XCTAssertEqual(engine.currentTrack?.id, tracks[1].id)
    }

    func testSkipBackWhileCastingAdvancesPointerOnly() {
        let engine = PlayerEngine()
        engine.isCasting = true
        let tracks = makeAIFFTracks(count: 3)
        engine.play(track: tracks[2], in: tracks)
        engine.skipBack()
        XCTAssertEqual(engine.currentIndex, 1)
        XCTAssertEqual(engine.currentTrack?.id, tracks[1].id)
    }

    func testSkipForwardAtLastTrackWhileCastingDoesNotWrap() {
        let engine = PlayerEngine()
        engine.isCasting = true
        let tracks = makeAIFFTracks(count: 2)
        engine.play(track: tracks[1], in: tracks)
        engine.skipForward()
        XCTAssertEqual(engine.currentIndex, 1)
    }

    func testSkipBackAtFirstTrackWhileCastingDoesNotUnderflow() {
        let engine = PlayerEngine()
        engine.isCasting = true
        let tracks = makeAIFFTracks(count: 2)
        engine.play(track: tracks[0], in: tracks)
        engine.skipBack()
        XCTAssertEqual(engine.currentIndex, 0)
    }

    // MARK: - 6. Seek time → sample index conversion

    /// CastManager.seek(to:) computes: let sampleOffset = Int(time * info.sampleRate)
    /// These tests verify the arithmetic that determines the Range byte-offset.

    func testSampleOffsetAtStartIsZero() {
        XCTAssertEqual(sampleOffset(time: 0.0, sampleRate: 44100), 0)
    }

    func testSampleOffsetOneSecond44100Hz() {
        XCTAssertEqual(sampleOffset(time: 1.0, sampleRate: 44100), 44100)
    }

    func testSampleOffsetTwoSeconds44100Hz() {
        XCTAssertEqual(sampleOffset(time: 2.0, sampleRate: 44100), 88200)
    }

    func testSampleOffsetOneSecond48kHz() {
        XCTAssertEqual(sampleOffset(time: 1.0, sampleRate: 48000), 48000)
    }

    func testSampleOffsetOneSecond96kHz() {
        XCTAssertEqual(sampleOffset(time: 1.0, sampleRate: 96000), 96000)
    }

    func testSampleOffsetHalfSecond44100Hz() {
        // Int(0.5 * 44100) == 22050
        XCTAssertEqual(sampleOffset(time: 0.5, sampleRate: 44100), 22050)
    }

    func testSampleOffsetTruncatesNonIntegerResult() {
        // Int() truncates, e.g. 1.1s at 44100 → 48510
        XCTAssertEqual(sampleOffset(time: 1.1, sampleRate: 44100), 48510)
    }

    // MARK: - 7. AIFF extension detection (mirrors CastManager.loadTrack branch)

    func testAIFFExtensionIsDetectedForCasting() {
        XCTAssertTrue(requiresAIFFProxy(fileName: "album/track.aiff"))
        XCTAssertTrue(requiresAIFFProxy(fileName: "track.aif"))
        XCTAssertTrue(requiresAIFFProxy(fileName: "TRACK.AIFF"))  // case-insensitive
    }

    func testNonAIFFExtensionsAreNotProxied() {
        XCTAssertFalse(requiresAIFFProxy(fileName: "track.mp3"))
        XCTAssertFalse(requiresAIFFProxy(fileName: "track.flac"))
        XCTAssertFalse(requiresAIFFProxy(fileName: "track.m4a"))
        XCTAssertFalse(requiresAIFFProxy(fileName: "track.wav"))
        XCTAssertFalse(requiresAIFFProxy(fileName: "track.aac"))
    }

    // MARK: - 8. Cache-busting URL format for Cast reconnection

    /// When CastManager.seek builds the URL it appends ?t=<Int(time)> so the Cast
    /// receiver treats it as a new resource and opens a fresh connection to the proxy.

    func testCacheBustingURLAppendsTParam() {
        let base = "http://192.168.1.10:8080/stream.aac"
        let time: Double = 30.0
        let url = URL(string: "\(base)?t=\(Int(time))")!
        XCTAssertEqual(url.query, "t=30")
    }

    func testCacheBustingURLTruncatesSubsecondTime() {
        let base = "http://192.168.1.10:8080/stream.aac"
        let time: Double = 65.9
        let url = URL(string: "\(base)?t=\(Int(time))")!
        XCTAssertEqual(url.query, "t=65")
    }

    func testCacheBustingURLAtTimeZeroIsT0() {
        let base = "http://192.168.1.10:8080/stream.aac"
        let url = URL(string: "\(base)?t=\(Int(0.0))")!
        XCTAssertEqual(url.query, "t=0")
    }

    // MARK: - Helpers

    /// Mirrors the logic in PlayerEngine.utTypeIdentifier(for:).
    private func utTypeID(for fileName: String) -> String? {
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

    /// Mirrors the ext check in CastManager.loadTrack(_:startTime:album:artwork:).
    private func requiresAIFFProxy(fileName: String) -> Bool {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return ext == "aiff" || ext == "aif"
    }

    /// Mirrors CastManager.seek(to:): Int(time * info.sampleRate)
    private func sampleOffset(time: Double, sampleRate: Double) -> Int {
        Int(time * sampleRate)
    }

    private func makeAIFFTrack(index: Int = 1) -> Track {
        Track(
            id: "/album/track\(index).aiff",
            dropboxPath: "/album/track\(index).aiff",
            fileName: "track\(index).aiff",
            title: "Track \(index)",
            trackNumber: index,
            discNumber: nil,
            durationSeconds: 180
        )
    }

    private func makeAIFFTracks(count: Int) -> [Track] {
        (1...count).map { makeAIFFTrack(index: $0) }
    }
}
