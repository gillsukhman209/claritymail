//
//  Theme.swift
//  ClarityMail
//
//  Design tokens for the flux-inspired UI. Colors adapt to light and dark mode.
//

import SwiftUI

enum Theme {
    enum Palette {
        static let background = Color("ThemeBackground", bundle: nil, fallbackLight: Color(red: 0.97, green: 0.97, blue: 0.99), fallbackDark: Color(red: 0.043, green: 0.031, blue: 0.078))
        static let surface = Color("ThemeSurface", bundle: nil, fallbackLight: Color.white, fallbackDark: Color(red: 0.082, green: 0.063, blue: 0.118))
        static let surfaceElevated = Color("ThemeSurfaceElevated", bundle: nil, fallbackLight: Color.white, fallbackDark: Color(red: 0.110, green: 0.086, blue: 0.157))
        static let border = Color("ThemeBorder", bundle: nil, fallbackLight: Color.black.opacity(0.08), fallbackDark: Color.white.opacity(0.08))
        static let borderStrong = Color("ThemeBorderStrong", bundle: nil, fallbackLight: Color.black.opacity(0.14), fallbackDark: Color.white.opacity(0.16))

        static let textPrimary = Color("ThemeTextPrimary", bundle: nil, fallbackLight: Color(red: 0.07, green: 0.07, blue: 0.10), fallbackDark: Color.white)
        static let textSecondary = Color("ThemeTextSecondary", bundle: nil, fallbackLight: Color(red: 0.40, green: 0.40, blue: 0.45), fallbackDark: Color.white.opacity(0.62))
        static let textTertiary = Color("ThemeTextTertiary", bundle: nil, fallbackLight: Color(red: 0.55, green: 0.55, blue: 0.60), fallbackDark: Color.white.opacity(0.40))

        static let accent = Color(red: 0.486, green: 0.380, blue: 1.0) // #7C61FF
        static let accentSoft = Color(red: 0.612, green: 0.510, blue: 1.0) // #9C82FF
        static let glow = Color(red: 0.541, green: 0.341, blue: 0.969) // #8A57F7
        static let warm = Color(red: 1.0, green: 0.541, blue: 0.349) // #FF8A59 (orange unread dot)
        static let warmSoft = Color(red: 1.0, green: 0.671, blue: 0.467) // #FFAB77
    }

    enum Gradients {
        static var orb: LinearGradient {
            LinearGradient(
                colors: [
                    Color(red: 0.541, green: 0.341, blue: 0.969).opacity(0.95),
                    Color(red: 1.0, green: 0.541, blue: 0.349).opacity(0.85)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        static var voiceButton: LinearGradient {
            LinearGradient(
                colors: [
                    Color(red: 0.612, green: 0.510, blue: 1.0),
                    Color(red: 0.412, green: 0.290, blue: 0.953)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        static var pulseCardBorder: LinearGradient {
            LinearGradient(
                colors: [
                    Color(red: 0.612, green: 0.510, blue: 1.0).opacity(0.55),
                    Color(red: 1.0, green: 0.541, blue: 0.349).opacity(0.30)
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
