import XCTest
@testable import DropPlayer

@MainActor
final class PlayerEngineTests: XCTestCase {

    func testInitialStateHasNoCurrentTrack() {
        let engine = PlayerEngine()
        XCTAssertNil(engine.currentTrack)
    }

    func testInitialQueueIsEmpty() {
        let engine = PlayerEngine()
        XCTAssertTrue(engine.queue.isEmpty)
    }

    func testInitialCurrentIndexIsZero() {
        let engine = PlayerEngine()
        XCTAssertEqual(engine.currentIndex, 0)
    }

    func testInitialIsPlayingIsFalse() {
        let engine = PlayerEngine()
        XCTAssertFalse(engine.isPlaying)
    }

    func testInitialIsBufferingIsFalse() {
        let engine = PlayerEngine()
        XCTAssertFalse(engine.isBuffering)
    }

    func testPlaySetsQueue() {
        let engine = PlayerEngine()
        let tracks = makeTracks(count: 3)
        engine.play(track: tracks[0], in: tracks)
        XCTAssertEqual(engine.queue.count, 3)
    }

    func testPlaySetsCurrentTrack() {
        let engine = PlayerEngine()
        let tracks = makeTracks(count: 3)
        engine.play(track: tracks[1], in: tracks)
        XCTAssertEqual(engine.currentTrack?.id, tracks[1].id)
    }

    func testPlaySetsCurrentIndexToMatchTrack() {
        let engine = PlayerEngine()
        let tracks = makeTracks(count: 3)
        engine.play(track: tracks[2], in: tracks)
        XCTAssertEqual(engine.currentIndex, 2)
    }

    func testPlaySetsIsBufferingTrue() {
        let engine = PlayerEngine()
        let track = makeTracks(count: 1)[0]
        engine.play(track: track, in: [track])
        XCTAssertTrue(engine.isBuffering)
    }

    func testSkipForwardIncrementsCurrentIndex() {
        let engine = PlayerEngine()
        let tracks = makeTracks(count: 3)
        engine.play(track: tracks[0], in: tracks)
        engine.skipForward()
        XCTAssertEqual(engine.currentIndex, 1)
    }

    func testSkipForwardAtLastTrackDoesNotChangeIndex() {
        let engine = PlayerEngine()
        let tracks = makeTracks(count: 2)
        engine.play(track: tracks[1], in: tracks)
        engine.skipForward()
        XCTAssertEqual(engine.currentIndex, 1)
    }

    func testSkipBackAtFirstTrackDoesNotChangeIndex() {
        let engine = PlayerEngine()
        let track = makeTracks(count: 1)[0]
        engine.play(track: track, in: [track])
        engine.skipBack()
        XCTAssertEqual(engine.currentIndex, 0)
    }

    func testSkipBackGoesToPreviousTrack() {
        let engine = PlayerEngine()
        let tracks = makeTracks(count: 3)
        engine.play(track: tracks[2], in: tracks)
        engine.skipBack()
        XCTAssertEqual(engine.currentIndex, 1)
    }

    func testSeekUpdatesCurrentTime() {
        let engine = PlayerEngine()
        engine.seek(to: 30.0)
        XCTAssertEqual(engine.currentTime, 30.0, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeTracks(count: Int) -> [Track] {
        (1...count).map { i in
            Track(
                id: "/album/track\(i).mp3",
                dropboxPath: "/album/track\(i).mp3",
                fileName: "track\(i).mp3",
                title: "Track \(i)",
                trackNumber: i,
                discNumber: nil,
                durationSeconds: nil
            )
        }
    }
}
