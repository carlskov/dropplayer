import XCTest
@testable import DropPlayer

final class AppSettingsTests: XCTestCase {
    private let authKey = "isAuthenticated"
    private let folderPathsKey = "musicFolderPaths"
    private let legacyFolderKey = "musicFolderPath"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: authKey)
        UserDefaults.standard.removeObject(forKey: folderPathsKey)
        UserDefaults.standard.removeObject(forKey: legacyFolderKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: authKey)
        UserDefaults.standard.removeObject(forKey: folderPathsKey)
        UserDefaults.standard.removeObject(forKey: legacyFolderKey)
        super.tearDown()
    }

    func testInitialIsAuthenticatedIsFalse() {
        let settings = AppSettings()
        XCTAssertFalse(settings.isAuthenticated)
    }

    func testInitialMusicFolderPathsIsEmpty() {
        let settings = AppSettings()
        XCTAssertTrue(settings.musicFolderPaths.isEmpty)
    }

    func testLogOutSetsIsAuthenticatedToFalse() {
        let settings = AppSettings()
        settings.isAuthenticated = true
        settings.logOut()
        XCTAssertFalse(settings.isAuthenticated)
    }

    func testLogOutClearsMusicFolderPaths() {
        let settings = AppSettings()
        settings.musicFolderPaths = ["/Music"]
        settings.logOut()
        XCTAssertTrue(settings.musicFolderPaths.isEmpty)
    }

    func testIsAuthenticatedPersistsToUserDefaults() {
        let settings = AppSettings()
        settings.isAuthenticated = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: authKey))
    }

    func testMusicFolderPathsPersistToUserDefaults() {
        let settings = AppSettings()
        settings.musicFolderPaths = ["/Music", "/Audiobooks"]
        let data = UserDefaults.standard.data(forKey: folderPathsKey)!
        let decoded = try! JSONDecoder().decode([String].self, from: data)
        XCTAssertEqual(decoded, ["/Music", "/Audiobooks"])
    }

    func testInitReadsMusicFolderPathsFromUserDefaults() {
        let data = try! JSONEncoder().encode(["/Jazz", "/Rock"])
        UserDefaults.standard.set(data, forKey: folderPathsKey)
        let settings = AppSettings()
        XCTAssertEqual(settings.musicFolderPaths, ["/Jazz", "/Rock"])
    }

    func testInitReadsIsAuthenticatedFromUserDefaults() {
        UserDefaults.standard.set(true, forKey: authKey)
        let settings = AppSettings()
        XCTAssertTrue(settings.isAuthenticated)
    }

    func testLegacySingleFolderMigration() {
        UserDefaults.standard.set("/Jazz", forKey: legacyFolderKey)
        let settings = AppSettings()
        XCTAssertEqual(settings.musicFolderPaths, ["/Jazz"])
    }
}
