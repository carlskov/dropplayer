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

    private func extractYear(from dateString: String?) -> Int? {
        guard let dateString = dateString else { return nil }
        
        if let year = Int(dateString), year > 1000 && year < 10000 {
            return year
        }
        
        let patterns = [
            "(\\d{4})[-\\/]\\d{2}[-\\/]\\d{2}",
            "(\\d{4})[-\\/]\\d{2}",
            "(\\d{4})"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: dateString, range: NSRange(dateString.startIndex..., in: dateString)),
               let range = Range(match.range(at: 1), in: dateString) {
                return Int(dateString[range])
            }
        }
        
        return nil
    }

    private func sortByYear(_ albums: [Album]) -> [Album] {
        albums.sorted { album1, album2 in
            let year1 = extractYear(from: album1.year) ?? 0
            let year2 = extractYear(from: album2.year) ?? 0
            if year1 != year2 {
                return year1 > year2
            }
            return album1.displayTitle.localizedCaseInsensitiveCompare(album2.displayTitle) == .orderedAscending
        }
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

        let sorted = sortByYear(albums)

        XCTAssertEqual(sorted.map { $0.year }, ["2023", "2020", "2019"])
    }

    func testSortByYearFallsBackToTitle() {
        let albums = [
            makeAlbum(id: "1", title: "Zebra", artist: "Artist", year: "2020"),
            makeAlbum(id: "2", title: "Apple", artist: "Artist", year: "2020")
        ]

        let sorted = sortByYear(albums)

        XCTAssertEqual(sorted.map { $0.title }, ["Apple", "Zebra"])
    }

    func testSortByYearWithNilYearAtEnd() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: "Artist", year: "2020"),
            makeAlbum(id: "2", title: "Album", artist: "Artist", year: nil),
            makeAlbum(id: "3", title: "Album", artist: "Artist", year: "2023")
        ]

        let sorted = sortByYear(albums)

        XCTAssertEqual(sorted[0].year, "2023")
        XCTAssertEqual(sorted[1].year, "2020")
        XCTAssertNil(sorted[2].year)
    }

    func testSortByYearWithISODate() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: "Artist", year: "2020-05-15"),
            makeAlbum(id: "2", title: "Album", artist: "Artist", year: "2023-01-01"),
            makeAlbum(id: "3", title: "Album", artist: "Artist", year: "2019-12-31")
        ]

        let sorted = sortByYear(albums)

        XCTAssertEqual(sorted.map { $0.year }, ["2023-01-01", "2020-05-15", "2019-12-31"])
    }

    func testSortByYearWithDateAndTime() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: "Artist", year: "2020/03/15"),
            makeAlbum(id: "2", title: "Album", artist: "Artist", year: "2023/01/01"),
            makeAlbum(id: "3", title: "Album", artist: "Artist", year: "2019/12/31")
        ]

        let sorted = sortByYear(albums)

        XCTAssertEqual(sorted.map { $0.year }, ["2023/01/01", "2020/03/15", "2019/12/31"])
    }

    func testSortByYearWithMixedFormats() {
        let albums = [
            makeAlbum(id: "1", title: "Album", artist: "Artist", year: "2020"),
            makeAlbum(id: "2", title: "Album", artist: "Artist", year: "2023-06-15"),
            makeAlbum(id: "3", title: "Album", artist: "Artist", year: "2019/08/20")
        ]

        let sorted = sortByYear(albums)

        XCTAssertEqual(sorted.map { $0.year }, ["2023-06-15", "2020", "2019/08/20"])
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
