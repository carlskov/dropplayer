import XCTest
@testable import DropPlayer

final class TrackTests: XCTestCase {

    func testDisplayTitleUsesTitleWhenNotEmpty() {
        let track = Track(
            id: "/music/album/track.mp3",
            dropboxPath: "/music/album/track.mp3",
            fileName: "01 - Song Title.mp3",
            title: "Song Title",
            trackNumber: 1,
            discNumber: nil,
            durationSeconds: 180
        )
        XCTAssertEqual(track.displayTitle, "Song Title")
    }

    func testDisplayTitleUsesFileNameWhenTitleEmpty() {
        let track = Track(
            id: "/music/album/track.mp3",
            dropboxPath: "/music/album/track.mp3",
            fileName: "01 - Song Title.mp3",
            title: "",
            trackNumber: 1,
            discNumber: nil,
            durationSeconds: 180
        )
        XCTAssertEqual(track.displayTitle, "01 - Song Title.mp3")
    }

    func testTrackHashable() {
        let track1 = Track(
            id: "/music/album/track.mp3",
            dropboxPath: "/music/album/track.mp3",
            fileName: "track.mp3",
            title: "Title",
            trackNumber: 1,
            discNumber: nil,
            durationSeconds: nil
        )
        let track2 = Track(
            id: "/music/album/track.mp3",
            dropboxPath: "/music/album/track.mp3",
            fileName: "track.mp3",
            title: "Title",
            trackNumber: 1,
            discNumber: nil,
            durationSeconds: nil
        )
        XCTAssertEqual(track1, track2)
    }
}
