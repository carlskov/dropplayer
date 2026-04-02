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

    static var nowPlayingAccentColor: Color {
        // Color(red: 0.6, green: 0.4, blue: 0.6)
        // Color(red: 0.5, green: 0.3, blue: 0.5)
        Color(red: 0.6, green: 0.4, blue: 0.6)
    }   

    /// White tinted with 20% of the app's purple, for text on secondary filled buttons.
    /// Derived from: white (1,1,1) × 0.8 + purple (0.686, 0.322, 0.871) × 0.2
    static var secondaryButtonTextColor: Color {
        Color(red: 0.837, green: 0.764, blue: 0.844)
    }


    // MARK: - Button Styles
    
    /// A bordered button style with adaptive background colors for light/dark mode.
    /// Background is slightly darker in light mode and slightly lighter in dark mode.
    struct AdaptiveBorderedButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    let accentColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.bold())
            .frame(maxWidth: .infinity)
            .foregroundStyle(
                colorScheme == .light ? accentColor : Theme.secondaryButtonTextColor
            )
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            // .background(
            //     // Use .continuous for system-matching curves
            //     RoundedRectangle(cornerRadius: 16, style: .continuous) 
            //         .fill(accentColor.opacity(0.15))
            // )
            .overlay(
                RoundedRectangle(cornerRadius: 100, style: .continuous)
                    .stroke(accentColor, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
    
    /// Factory method for creating the adaptive bordered button style.
    static func adaptiveBorderedButtonStyle(accentColor: Color = Theme.accentColor) -> some ButtonStyle {
        AdaptiveBorderedButtonStyle(accentColor: accentColor)
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
