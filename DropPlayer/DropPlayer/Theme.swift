import SwiftUI

struct Theme {
    static var accentColor: Color = .green
}

private struct AccentColorKey: EnvironmentKey {
    static let defaultValue: Color = Theme.accentColor
}

extension EnvironmentValues {
    var accentColor: Color {
        get { self[AccentColorKey.self] }
        set { self[AccentColorKey.self] = newValue }
    }
}

extension View {
    func accentColor(_ color: Color) -> some View {
        environment(\.accentColor, color)
    }
}
