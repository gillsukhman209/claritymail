//
//  Theme.swift
//  ClarityMail
//
//  Design tokens for the flux-inspired UI. Colors adapt to light and dark mode.
//

import SwiftUI

enum Theme {
    enum Palette {
        static let background = Color("ThemeBackground", bundle: nil, fallbackLight: Color(red: 0.97, green: 0.98, blue: 0.98), fallbackDark: Color(red: 0.039, green: 0.055, blue: 0.071))
        static let surface = Color("ThemeSurface", bundle: nil, fallbackLight: Color.white, fallbackDark: Color(red: 0.071, green: 0.094, blue: 0.114))
        static let surfaceElevated = Color("ThemeSurfaceElevated", bundle: nil, fallbackLight: Color.white, fallbackDark: Color(red: 0.094, green: 0.122, blue: 0.149))
        static let border = Color("ThemeBorder", bundle: nil, fallbackLight: Color.black.opacity(0.08), fallbackDark: Color.white.opacity(0.08))
        static let borderStrong = Color("ThemeBorderStrong", bundle: nil, fallbackLight: Color.black.opacity(0.14), fallbackDark: Color.white.opacity(0.16))

        static let textPrimary = Color("ThemeTextPrimary", bundle: nil, fallbackLight: Color(red: 0.07, green: 0.07, blue: 0.10), fallbackDark: Color.white)
        static let textSecondary = Color("ThemeTextSecondary", bundle: nil, fallbackLight: Color(red: 0.40, green: 0.40, blue: 0.45), fallbackDark: Color.white.opacity(0.62))
        static let textTertiary = Color("ThemeTextTertiary", bundle: nil, fallbackLight: Color(red: 0.55, green: 0.55, blue: 0.60), fallbackDark: Color.white.opacity(0.40))

        static let accent = Color(red: 0.078, green: 0.580, blue: 0.541) // #14948A teal
        static let accentSoft = Color(red: 0.149, green: 0.722, blue: 0.671) // #26B8AB
        static let accentDeep = Color(red: 0.180, green: 0.224, blue: 0.443) // #2E3971 indigo
        static let warm = Color(red: 0.976, green: 0.451, blue: 0.086) // #F97316 orange (unread dot)
        static let warmSoft = Color(red: 0.984, green: 0.624, blue: 0.337) // #FB9F56
    }

    enum Gradients {
        /// Primary CTA / button gradient: teal → deep indigo. Calm, professional, no glow.
        static var primary: LinearGradient {
            LinearGradient(
                colors: [
                    Color(red: 0.149, green: 0.722, blue: 0.671), // #26B8AB
                    Color(red: 0.180, green: 0.224, blue: 0.443)  // #2E3971
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Subtle gradient for avatars and accents.
        static var accent: LinearGradient {
            LinearGradient(
                colors: [
                    Color(red: 0.149, green: 0.722, blue: 0.671),
                    Color(red: 0.078, green: 0.580, blue: 0.541)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    enum Radius {
        static let card: CGFloat = 22
        static let row: CGFloat = 18
        static let chip: CGFloat = 12
        static let button: CGFloat = 16
    }
}

private extension Color {
    /// Convenience initializer that falls back to programmatic colors when the asset catalog
    /// does not contain the named color. This lets the theme work without configuring assets.
    init(_ name: String, bundle: Bundle?, fallbackLight: Color, fallbackDark: Color) {
        #if canImport(UIKit)
        self = Color(UIColor { trait in
            UIColor(trait.userInterfaceStyle == .dark ? fallbackDark : fallbackLight)
        })
        #elseif canImport(AppKit)
        self = Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return NSColor(isDark ? fallbackDark : fallbackLight)
        })
        #else
        self = fallbackDark
        #endif
    }
}

extension View {
    func clarityCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(Theme.Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }
}
