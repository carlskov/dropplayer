import XCTest
@testable import DropPlayer

final class NowPlayingCoordinatorTests: XCTestCase {

    func testIsPresentedDefaultsToFalse() {
        let coordinator = NowPlayingCoordinator()
        XCTAssertFalse(coordinator.isPresented)
    }

    func testIsPresentedCanBeToggled() {
        let coordinator = NowPlayingCoordinator()
        coordinator.isPresented = true
        XCTAssertTrue(coordinator.isPresented)
        coordinator.isPresented = false
        XCTAssertFalse(coordinator.isPresented)
    }

    func testSharedInstanceIsNotNil() {
        XCTAssertNotNil(NowPlayingCoordinator.shared)
    }
}
