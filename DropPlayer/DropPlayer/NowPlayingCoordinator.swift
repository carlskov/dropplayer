import SwiftUI

@MainActor
final class NowPlayingCoordinator: ObservableObject {
    static let shared = NowPlayingCoordinator()

    @Published var isPresented = false

    private init() {}
}
