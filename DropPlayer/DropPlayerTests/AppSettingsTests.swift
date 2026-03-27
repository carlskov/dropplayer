import XCTest
@testable import DropPlayer

final class AppSettingsTests: XCTestCase {
    private let authKey = "isAuthenticated"
    private let folderKey = "musicFolderPath"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: authKey)
        UserDefaults.standard.removeObject(forKey: folderKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: authKey)
        UserDefaults.standard.removeObject(forKey: folderKey)
        super.tearDown()
    }

    func testInitialIsAuthenticatedIsFalse() {
        let settings = AppSettings()
        XCTAssertFalse(settings.isAuthenticated)
    }

    func testInitialMusicFolderPathIsNil() {
        let settings = AppSettings()
        XCTAssertNil(settings.musicFolderPath)
    }

    func testLogOutSetsIsAuthenticatedToFalse() {
        let settings = AppSettings()
        settings.isAuthenticated = true
        settings.logOut()
        XCTAssertFalse(settings.isAuthenticated)
    }

    func testLogOutSetsMusicFolderPathToNil() {
        let settings = AppSettings()
        settings.musicFolderPath = "/Music"
        settings.logOut()
        XCTAssertNil(settings.musicFolderPath)
    }

    func testIsAuthenticatedPersistsToUserDefaults() {
        let settings = AppSettings()
        settings.isAuthenticated = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: authKey))
    }

    func testMusicFolderPathPersistsToUserDefaults() {
        let settings = AppSettings()
        settings.musicFolderPath = "/Dropbox/Music"
        XCTAssertEqual(UserDefaults.standard.string(forKey: folderKey), "/Dropbox/Music")
    }

    func testInitReadsIsAuthenticatedFromUserDefaults() {
        UserDefaults.standard.set(true, forKey: authKey)
        let settings = AppSettings()
        XCTAssertTrue(settings.isAuthenticated)
    }

    func testInitReadsMusicFolderPathFromUserDefaults() {
        UserDefaults.standard.set("/Jazz", forKey: folderKey)
        let settings = AppSettings()
        XCTAssertEqual(settings.musicFolderPath, "/Jazz")
    }
}
