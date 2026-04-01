import SwiftUI
import UIKit

/// Landing screen when the user is not yet signed in.
struct SetupView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "music.note.house.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.accentColor.gradient)

            VStack(spacing: 8) {
                Text("DropPlayer")
                    .font(.largeTitle.bold())
                Text("Stream your music from Dropbox")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                connectDropbox()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link.cloud.fill")
                    Text(isConnecting ? "Connecting…" : "Connect Dropbox")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isConnecting)
            .padding(.horizontal, 32)

            Spacer()

            Text("You'll be asked to authorise DropPlayer\nin your browser.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.bottom)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dropboxAuthSucceeded)) { _ in
            isConnecting = false
            settings.isAuthenticated = true
        }
    }

    private func connectDropbox() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        isConnecting = true
        errorMessage = nil
        DropboxAuthManager.shared.signIn(from: rootVC)

        // If the user cancels OAuth, detect it after a short window
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if isConnecting {
                isConnecting = false
                errorMessage = "Sign-in timed out. Please try again."
            }
        }
    }
}
