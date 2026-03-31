import XCTest
@testable import DropPlayer

final class AlbumSortingTests: XCTestCase {

    private func makeAlbum(id: String, title: String, artist: String, year: String? = nil, genre: String? = nil, folderPath: String = "/music") -> Album {
        Album(
            id: id,
            folderPath: folderPath,
            folderName: "Folder",
            title: title,
            artist: artist,
            year: year,
            tracks: [],
            artworkDropboxPath: nil,
            genre: genre
        )
    }

    // MARK: - Title Sorting

    func testSortByTitleAlphabetical() {
        let albums = [
            makeAlbum(id: "1", title: "Zebra", artist: "Artist"),
            makeAlbum(id: "2", title: "Apple", artist: "Artist"),
            makeAlbum(id: "3", title: "Mango", artist: "Artist")
        ]

        let sorted = albums.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }

        XCTAssertEqual(sorted.map { $0.title }, ["Apple", "Mango", "Zebra"])
    }

    func testSortByTitleCaseInsensitive() {
        let albums = [
            makeAlbum(id: "1", title: "apple", artist: "Artist"),
            makeAlbum(id: "2", title: "Apple", artist: "Artist"),
            makeAlbum(id: "3", title: "APPLE", artist: "Artist")
        ]

        let sorted = albums.sorted {
            $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
        }

        XCTAssertEqual(sorted.count, 3)
    }

    // MARK: - Artist Sorting

    func testSortByArtistAlphabetical() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: "Zack"),
            makeAlbum(id: "2", title: "Album", artist: "Aaron"),
            makeAlbum(id: "3", title: "Album", artist: "Mike")
        ]

        let sorted = albums.sorted {
            $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist) == .orderedAscending
        }

        XCTAssertEqual(sorted.map { $0.artist }, ["Aaron", "Mike", "Zack"])
    }

    func testSortByArtistUnknownArtist() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: ""),
            makeAlbum(id: "2", title: "Album", artist: "Aaron")
        ]

        let sorted = albums.sorted {
            $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist) == .orderedAscending
        }

        XCTAssertEqual(sorted[0].artist, "Aaron")
        XCTAssertEqual(sorted[1].artist, "")
    }

    // MARK: - Year Sorting

    func testSortByYearDescending() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: "Artist", year: "2020"),
            makeAlbum(id: "2", title: "Album", artist: "Artist", year: "2023"),
            makeAlbum(id: "3", title: "Album", artist: "Artist", year: "2019")
        ]

        let sorted = albums.sorted { album1, album2 in
            let year1 = album1.year.flatMap { Int($0) } ?? 0
            let year2 = album2.year.flatMap { Int($0) } ?? 0
            if year1 != year2 {
                return year1 > year2
            }
            return album1.displayTitle.localizedCaseInsensitiveCompare(album2.displayTitle) == .orderedAscending
        }

        XCTAssertEqual(sorted.map { $0.year }, ["2023", "2020", "2019"])
    }

    func testSortByYearFallsBackToTitle() {
        let albums = [
            makeAlbum(id: "1", title: "Zebra", artist: "Artist", year: "2020"),
            makeAlbum(id: "2", title: "Apple", artist: "Artist", year: "2020")
        ]

        let sorted = albums.sorted { album1, album2 in
            let year1 = album1.year.flatMap { Int($0) } ?? 0
            let year2 = album2.year.flatMap { Int($0) } ?? 0
            if year1 != year2 {
                return year1 > year2
            }
            return album1.displayTitle.localizedCaseInsensitiveCompare(album2.displayTitle) == .orderedAscending
        }

        XCTAssertEqual(sorted.map { $0.title }, ["Apple", "Zebra"])
    }

    func testSortByYearWithNilYearAtEnd() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: "Artist", year: "2020"),
            makeAlbum(id: "2", title: "Album", artist: "Artist", year: nil),
            makeAlbum(id: "3", title: "Album", artist: "Artist", year: "2023")
        ]

        let sorted = albums.sorted { album1, album2 in
            let year1 = album1.year.flatMap { Int($0) } ?? 0
            let year2 = album2.year.flatMap { Int($0) } ?? 0
            if year1 != year2 {
                return year1 > year2
            }
            return album1.displayTitle.localizedCaseInsensitiveCompare(album2.displayTitle) == .orderedAscending
        }

        XCTAssertEqual(sorted[0].year, "2023")
        XCTAssertEqual(sorted[1].year, "2020")
        XCTAssertNil(sorted[2].year)
    }

    // MARK: - Location Sorting

    func testSortByLocationAlphabetical() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: "Artist", folderPath: "/music/zzz"),
            makeAlbum(id: "2", title: "Album", artist: "Artist", folderPath: "/music/aaa"),
            makeAlbum(id: "3", title: "Album", artist: "Artist", folderPath: "/music/mmm")
        ]

        let sorted = albums.sorted {
            $0.folderPath.localizedCaseInsensitiveCompare($1.folderPath) == .orderedAscending
        }

        XCTAssertEqual(sorted.map { $0.folderPath }, ["/music/aaa", "/music/mmm", "/music/zzz"])
    }

    // MARK: - Genre Sorting

    func testSortByGenreAlphabetical() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: "Artist", genre: "Rock"),
            makeAlbum(id: "2", title: "Album", artist: "Artist", genre: "Classical"),
            makeAlbum(id: "3", title: "Album", artist: "Artist", genre: "Jazz")
        ]

        let sorted = albums.sorted {
            let genreA = $0.genre ?? ""
            let genreB = $1.genre ?? ""
            if genreA == genreB {
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            return genreA.localizedCaseInsensitiveCompare(genreB) == .orderedAscending
        }

        XCTAssertEqual(sorted.map { $0.genre }, ["Classical", "Jazz", "Rock"])
    }

    func testSortByGenreFallsBackToTitle() {
        let albums = [
            makeAlbum(id: "1", title: "Zebra", artist: "Artist", genre: "Rock"),
            makeAlbum(id: "2", title: "Apple", artist: "Artist", genre: "Rock")
        ]

        let sorted = albums.sorted {
            let genreA = $0.genre ?? ""
            let genreB = $1.genre ?? ""
            if genreA == genreB {
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            return genreA.localizedCaseInsensitiveCompare(genreB) == .orderedAscending
        }

        XCTAssertEqual(sorted.map { $0.title }, ["Apple", "Zebra"])
    }

    func testSortByGenreWithNilAtEnd() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: "Artist", genre: "Rock"),
            makeAlbum(id: "2", title: "Album", artist: "Artist", genre: nil),
            makeAlbum(id: "3", title: "Album", artist: "Artist", genre: "Jazz")
        ]

        let sorted = albums.sorted {
            let genreA = $0.genre ?? ""
            let genreB = $1.genre ?? ""
            if genreA == genreB {
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            return genreA.localizedCaseInsensitiveCompare(genreB) == .orderedAscending
        }

        XCTAssertEqual(sorted[0].genre, "Jazz")
        XCTAssertEqual(sorted[1].genre, "Rock")
        XCTAssertNil(sorted[2].genre)
    }
}
