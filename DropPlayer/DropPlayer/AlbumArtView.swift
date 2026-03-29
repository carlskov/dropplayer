import SwiftUI

/// Shared album artwork view — shows artwork or a placeholder.
struct AlbumArtView: View {
    enum SizeMode {
        case fixed(CGFloat)
        case flexible
    }

    let image: UIImage?
    var size: SizeMode = .flexible

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                    Image(systemName: "music.note")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                }
                .aspectRatio(1, contentMode: .fit)
            }
        }
        .applySize(size)
        .clipped()
    }
}

private extension View {
    @ViewBuilder
    func applySize(_ mode: AlbumArtView.SizeMode) -> some View {
        switch mode {
        case .fixed(let s):
            self.frame(width: s, height: s)
        case .flexible:
            self
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }
}
