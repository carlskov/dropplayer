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

    func testAlbumWithGenre() {
        let album = Album(
            id: "/music/album",
            folderPath: "/music/album",
            folderName: "Album",
            title: "Album Title",
            artist: "Artist",
            year: nil,
            tracks: [],
            artworkDropboxPath: nil,
            genre: "Rock"
        )
        XCTAssertEqual(album.genre, "Rock")
    }

    func testAlbumWithYearAndGenre() {
        let album = Album(
            id: "/music/album",
            folderPath: "/music/album",
            folderName: "Album",
            title: "Album Title",
            artist: "Artist",
            year: "2024",
            tracks: [],
            artworkDropboxPath: nil,
            genre: "Jazz"
        )
        XCTAssertEqual(album.year, "2024")
        XCTAssertEqual(album.genre, "Jazz")
    }

    func testAlbumGenreIsNilByDefault() {
        let album = Album(
            id: "/music/album",
            folderPath: "/music/album",
            folderName: "Album",
            title: "Album Title",
            artist: "Artist",
            year: nil,
            tracks: [],
            artworkDropboxPath: nil
        )
        XCTAssertNil(album.genre)
    }

    func testArtworkFilenamePatternMatching() {
        // Test the filename pattern matching logic for the "front" fallback requirement
        let testCases = [
            // (filename: String, isImageFile: Bool, shouldMatchFrontPattern: Bool)
            ("cover.jpg", true, false),
            ("folder.png", true, false),
            ("front.jpg", false), // no prefix - handled by preferred names, not fallback pattern
            ("-front.jpg", true), // ends with "-front"
            ("_front.png", true), // ends with "_front"
            ("album-front.webp", true), // ends with "-front"
            ("cover_front.jpeg", true), // ends with "_front"
            ("00-VA_-_Tribal_Science-front.jpg", true), // complex case with "-front" ending
            ("my_front_cover.jpg", false), // doesn't end with "-front" or "_front"
            ("frontcover.jpg", false), // doesn't end with "-front" or "_front"
            ("image.jpg", false),
            ("track.mp3", false),
        ]

        for (filename, isImage, shouldMatchFront) in testCases {
            let isActualImage = isImageFile(filename)
            XCTAssertEqual(isActualImage, isImage, "Image detection for: " + filename)

            let doesMatchFront = matchesFrontPattern(filename)
            XCTAssertEqual(doesMatchFront, shouldMatchFront, "Front pattern for: " + filename)
        }
    }

    private func isImageFile(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "webp"].contains(ext)
    }

    private func matchesFrontPattern(_ filename: String) -> Bool {
        let lowercaseName = filename.lowercased()
        // Pattern: files ending with "front" (prefixed with - or _)
        let frontPattern = #"[^\\/]*[-_]front\.(jpg|jpeg|png|webp)$"#
        return lowercaseName.range(of: frontPattern, options: .regularExpression) != nil
    }
}
