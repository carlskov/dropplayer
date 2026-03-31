import XCTest
@testable import DropPlayer

@MainActor
final class NowPlayingCoordinatorTests: XCTestCase {

    private var coordinator: NowPlayingCoordinator!

    override func setUp() {
        super.setUp()
        coordinator = NowPlayingCoordinator.shared
    }

    override func tearDown() {
        coordinator = nil
        super.tearDown()
    }

    func testIsPresentedDefaultsToFalse() {
        XCTAssertFalse(coordinator.isPresented)
    }

    func testIsPresentedCanBeToggled() {
        coordinator.isPresented = true
        XCTAssertTrue(coordinator.isPresented)
        coordinator.isPresented = false
        XCTAssertFalse(coordinator.isPresented)
    }

    func testSharedInstanceIsNotNil() {
        XCTAssertNotNil(NowPlayingCoordinator.shared)
    }
}
