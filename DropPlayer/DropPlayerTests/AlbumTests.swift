import XCTest
@testable import DropPlayer

final class AlbumTests: XCTestCase {

    func testDisplayTitleUsesTitleWhenNotEmpty() {
        let album = Album(
            id: "/music/album",
            folderPath: "/music/album",
            folderName: "Album - Artist",
            title: "Album Title",
            artist: "Artist",
            year: nil,
            tracks: [],
            artworkDropboxPath: nil
        )
        XCTAssertEqual(album.displayTitle, "Album Title")
    }

    func testDisplayTitleUsesFolderNameWhenTitleEmpty() {
        let album = Album(
            id: "/music/album",
            folderPath: "/music/album",
            folderName: "My Album Folder",
            title: "",
            artist: "Artist",
            year: nil,
            tracks: [],
            artworkDropboxPath: nil
        )
        XCTAssertEqual(album.displayTitle, "My Album Folder")
    }

    func testDisplayArtistUsesArtistWhenNotEmpty() {
        let album = Album(
            id: "/music/album",
            folderPath: "/music/album",
            folderName: "Album",
            title: "Album Title",
            artist: "My Artist",
            year: nil,
            tracks: [],
            artworkDropboxPath: nil
        )
        XCTAssertEqual(album.displayArtist, "My Artist")
    }

    func testDisplayArtistUsesUnknownWhenEmpty() {
        let album = Album(
            id: "/music/album",
            folderPath: "/music/album",
            folderName: "Album",
            title: "Album Title",
            artist: "",
            year: nil,
            tracks: [],
            artworkDropboxPath: nil
        )
        XCTAssertEqual(album.displayArtist, "Unknown Artist")
    }

    func testAlbumTracksSortedByDiscNumber() {
        let track1 = Track(
            id: "/album/01.mp3",
            dropboxPath: "/album/01.mp3",
            fileName: "01.mp3",
            title: "Track 1",
            trackNumber: 1,
            discNumber: 2,
            durationSeconds: nil
        )
        let track2 = Track(
            id: "/album/02.mp3",
            dropboxPath: "/album/02.mp3",
            fileName: "02.mp3",
            title: "Track 2",
            trackNumber: 1,
            discNumber: 1,
            durationSeconds: nil
        )
        let album = Album(
            id: "/album",
            folderPath: "/album",
            folderName: "Album",
            title: "Album",
            artist: "Artist",
            year: nil,
            tracks: [track1, track2],
            artworkDropboxPath: nil
        )
        XCTAssertEqual(album.tracks.first?.id, "/album/02.mp3")
        XCTAssertEqual(album.tracks.last?.id, "/album/01.mp3")
    }
}
