import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

struct Theme {

    static var baseBackground: Color {
        Color(hex: 0xffffff)
    }

    static var libraryGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(hex: 0x180A55, alpha: 0.2),
                Color(hex: 0x180A55, alpha: 0.1),
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var accentColor: Color {
        // Color(red: 0.308, green: 0.208, blue: 0.308)
        // Color(red: 0.408, green: 0.308, blue: 0.408)
        
        // Color(red: 0.208, green: 0.108, blue: 0.208)
        //Color(red: 0.108, green: 0.108, blue: 0.208)
        Color(red: 0.308, green: 0.308, blue: 0.871)


    }

    static var lighterAccentColor: Color {
        // Color(red: 0.686, green: 0.322, blue: 0.871)
        Color(red: 0.9, green: 0.9, blue: 0.9)
        // Color(red: 0.871, green: 0.686, blue: 0.322)
        // Color(red: 0.871, green: 0.686, blue: 0)
    }

    /// A darker shade of `accentColor` for secondary filled buttons.
    static var darkAccentColor: Color {
        // Color(red: 0.15, green: 0.08, blue: 0.15)
        Color(red: 0.1, green: 0.1, blue: 0.1)
    }

    static var nowPlayingAccentColor: Color {
        // Color(red: 0.6, green: 0.4, blue: 0.6)
        // Color(red: 0.5, green: 0.3, blue: 0.5)
        // Color(red: 0.6, green: 0.4, blue: 0.6)
        // Color(red: 0.871, green: 0.686, blue: 0)
        // Color(red: 0.686, green: 0.322, blue: 0.871)
        // Color(red: 0.408, green: 0.308, blue: 0.408)
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                // ? UIColor(red: 0.686, green: 0.322, blue: 0.871, alpha: 1)   // lighterAccentColor
                ? UIColor(red: 0.322, green: 0.322, blue: 0.871, alpha: 1)   // accentColor
                // : UIColor(red: 0.408, green: 0.308, blue: 0.408, alpha: 1) // accentColor
                // : UIColor(red: 0.208, green: 0.108, blue: 0.20, alpha: 1)
                : UIColor(red: 0.322, green: 0.322, blue: 0.871, alpha: 1)  // accentColor
        })
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
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(
                // Use .continuous for system-matching curves
                RoundedRectangle(cornerRadius: 100, style: .continuous) 
                    .fill(accentColor.opacity( colorScheme == .light ? 0.20 : 0.45))
            )
            // .overlay(
            //     RoundedRectangle(cornerRadius: 100, style: .continuous)
            //         .stroke(accentColor, lineWidth: 1)
            // )
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
