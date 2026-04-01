import SwiftUI

struct Theme {
    static var accentColor: Color {
        Color(red: 0.308, green: 0.208, blue: 0.308)
    }

    /// A darker shade of `accentColor` for secondary filled buttons.
    static var darkAccentColor: Color {
        // Color(red: 0.15, green: 0.08, blue: 0.15)
        Color(red: 0.10, green: 0.03, blue: 0.10)
    }

    /// White tinted with 20% of the app's purple, for text on secondary filled buttons.
    /// Derived from: white (1,1,1) × 0.8 + purple (0.686, 0.322, 0.871) × 0.2
    static var secondaryButtonTextColor: Color {
        Color(red: 0.837, green: 0.764, blue: 0.844)
    }
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
