import SwiftUI

/// Persistent mini player bar shown above the tab bar.
struct MiniPlayerView: View {
    @EnvironmentObject var player: PlayerEngine
    @State private var showNowPlaying = false

    var body: some View {
        Button {
            showNowPlaying = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.displayTitle ?? "")
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if player.isBuffering {
                        Text("Buffering…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Play/pause
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }

                // Skip
                Button {
                    player.skipForward()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 4, y: -1)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
    }
}
