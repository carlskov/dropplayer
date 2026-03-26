import Foundation
import SwiftyDropbox
import UIKit

/// Handles Dropbox OAuth sign-in and sign-out.
final class DropboxAuthManager {
    static let shared = DropboxAuthManager()
    private init() {}

    /// Kick off the OAuth flow from the given view controller.
    func signIn(from viewController: UIViewController) {
        let scopeRequest = ScopeRequest(
            scopeType: .user,
            scopes: ["files.content.read", "files.metadata.read"],
            includeGrantedScopes: false
        )
        DropboxClientsManager.authorizeFromControllerV2(
            UIApplication.shared,
            controller: viewController,
            loadingStatusDelegate: nil,
            openURL: { UIApplication.shared.open($0) },
            scopeRequest: scopeRequest
        )
    }

    func signOut() {
        DropboxClientsManager.unlinkClients()
    }

    var isAuthorized: Bool {
        DropboxClientsManager.authorizedClient != nil
    }
}
