//
//  Theme.swift
//  ClarityMail
//
//  Dossier design language — editorial newsroom aesthetic.
//  Bone paper, ink type, saffron accent, hairline rules, sharp radii.
//
//  Public token names (Palette/Gradients/Radius/Button styles) are deliberately
//  preserved so legacy call sites continue to compile while inheriting the
//  new identity. New modifiers (`dossierRow`, `dossierDivider`, `dossierField`,
//  `pageGutter`) extend the language for redesigned surfaces.
//

import SwiftUI

enum Theme {
    enum Palette {
        // Surfaces — warm paper in light, deep ink in dark
        static let background = adaptive(
            light: Color(red: 0.961, green: 0.949, blue: 0.922),   // bone        #F5F2EC
            dark:  Color(red: 0.055, green: 0.051, blue: 0.043)    // pitch       #0E0D0B
        )
        static let backgroundElevated = adaptive(
            light: Color(red: 0.988, green: 0.980, blue: 0.961),   // cream       #FCFAF5
            dark:  Color(red: 0.082, green: 0.075, blue: 0.063)    // ink-1       #151310
        )
        static let surface = adaptive(
            light: Color(red: 0.996, green: 0.992, blue: 0.980),   // paper       #FEFDFA — barely-warm white
            dark:  Color(red: 0.094, green: 0.090, blue: 0.082)    // charcoal    #181715
        )
        static let surfaceElevated = adaptive(
            light: Color.white,                                     // pure white only on raised panels
            dark:  Color(red: 0.122, green: 0.114, blue: 0.102)    // charcoal-2  #1F1D1A
        )
        static let surfaceMuted = adaptive(
            light: Color(red: 0.933, green: 0.918, blue: 0.886),   // putty       #EEEAE2
            dark:  Color(red: 0.071, green: 0.067, blue: 0.055)    // pitch-2     #12110E
        )

        // Hairlines — thin ink rules, the whole language is built on these
        static let border = adaptive(
            light: Color(red: 0.078, green: 0.067, blue: 0.059).opacity(0.12),
            dark:  Color(red: 0.937, green: 0.925, blue: 0.890).opacity(0.10)
        )
        static let borderStrong = adaptive(
            light: Color(red: 0.078, green: 0.067, blue: 0.059).opacity(0.26),
            dark:  Color(red: 0.937, green: 0.925, blue: 0.890).opacity(0.22)
        )
        static let hairline = adaptive(
            light: Color(red: 0.078, green: 0.067, blue: 0.059).opacity(0.06),
            dark:  Color(red: 0.937, green: 0.925, blue: 0.890).opacity(0.06)
        )

        /// Drop-shadow color tuned per mode — soft warm ink in light, deep black in dark.
        static let shadow = adaptive(
            light: Color(red: 0.078, green: 0.067, blue: 0.059).opacity(0.10),
            dark:  Color.black.opacity(0.45)
        )
        static let shadowSoft = adaptive(
            light: Color(red: 0.078, green: 0.067, blue: 0.059).opacity(0.06),
            dark:  Color.black.opacity(0.30)
        )

        // Type — ink on bone, bone on pitch
        static let textPrimary = adaptive(
            light: Color(red: 0.063, green: 0.055, blue: 0.047),   // ink         #100E0C — slightly deeper for crispness
            dark:  Color(red: 0.937, green: 0.925, blue: 0.890)    // bone-bright #EFECE3
        )
        static let textSecondary = adaptive(
            light: Color(red: 0.376, green: 0.349, blue: 0.310),   // graphite    #605950 — bumped for AA contrast on bone
            dark:  Color(red: 0.604, green: 0.580, blue: 0.541)    // pewter      #9A948A
        )
        static let textTertiary = adaptive(
            light: Color(red: 0.541, green: 0.514, blue: 0.467),   // stone       #8A8377 — tighter than before
            dark:  Color(red: 0.420, green: 0.392, blue: 0.353)    // graphite    #6B645A
        )

        // Brand — saffron is the singular voice
        static let accent       = Color(red: 0.761, green: 0.255, blue: 0.047)   // saffron #C2410C
        static let accentSoft   = Color(red: 0.851, green: 0.467, blue: 0.114)   // amber   #D9771D
        static let accentDeep   = Color(red: 0.545, green: 0.122, blue: 0.059)   // oxblood #8B1F0F
        static let accentVivid  = Color(red: 0.851, green: 0.467, blue: 0.114)   // amber   #D9771D (alias)
        static let accentCyan   = Color(red: 0.180, green: 0.369, blue: 0.310)   // pine    #2E5E4F (calm secondary)

        // Functional
        static let warm     = Color(red: 0.851, green: 0.467, blue: 0.114)        // amber  #D9771D
        static let warmSoft = Color(red: 0.953, green: 0.706, blue: 0.404)        // wheat  #F3B467
        static let success  = Color(red: 0.255, green: 0.510, blue: 0.376)        // moss   #418260
        static let danger   = Color(red: 0.682, green: 0.149, blue: 0.149)        // crimson#AE2626
    }

    enum Gradients {
        /// Primary CTA — solid ink to charcoal. No vibrant rainbows.
        static var primary: LinearGradient {
            LinearGradient(
                colors: [
                    Color(red: 0.078, green: 0.067, blue: 0.059),   // ink
                    Color(red: 0.149, green: 0.133, blue: 0.114)    // charcoal
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// "Aurora" reborn — warm sunset reserved for AI-touched surfaces.
        static var aurora: LinearGradient {
            LinearGradient(
                colors: [
                    Color(red: 0.851, green: 0.467, blue: 0.114),   // amber
                    Color(red: 0.761, green: 0.255, blue: 0.047),   // saffron
                    Color(red: 0.545, green: 0.122, blue: 0.059)    // oxblood
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Secondary accent — saffron into oxblood for icon medallions.
        static var accent: LinearGradient {
            LinearGradient(
                colors: [
                    Color(red: 0.761, green: 0.255, blue: 0.047),
                    Color(red: 0.545, green: 0.122, blue: 0.059)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Ambient page wash — barely-there warm glow at the masthead.
        static var ambient: RadialGradient {
            RadialGradient(
                colors: [
                    Color(red: 0.851, green: 0.467, blue: 0.114).opacity(0.10),
                    Color(red: 0.761, green: 0.255, blue: 0.047).opacity(0.04),
                    .clear
                ],
                center: .topLeading,
                startRadius: 60,
                endRadius: 720
            )
        }

        /// Paper texture — used for chrome panels.
        static var glass: LinearGradient {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.04),
                    Color.white.opacity(0.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Sharper editorial radii. Cards are nearly rectangular; pills survive only
    /// for status chips and avatars.
    enum Radius {
        static let card: CGFloat   = 8
        static let row: CGFloat    = 4
        static let chip: CGFloat   = 2
        static let button: CGFloat = 6
        static let pill: CGFloat   = 999
    }

    enum Motion {
        static let snappy   = Animation.spring(response: 0.30, dampingFraction: 0.88)
        static let soft     = Animation.easeOut(duration: 0.18)
        static let entrance = Animation.spring(response: 0.40, dampingFraction: 0.86)
    }

    enum Typography {
        /// Editorial display — serif, like a masthead.
        static func display(_ size: CGFloat = 36) -> Font {
            .system(size: size, weight: .bold, design: .serif).italic()
        }
        /// Section title — serif, no italic.
        static func title(_ size: CGFloat = 22) -> Font {
            .system(size: size, weight: .semibold, design: .serif)
        }
        /// Body — clean system sans.
        static func body(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
        /// Metadata — small caps mono for timestamps, counts, labels.
        static func mono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        /// Section eyebrow label — wide-tracked uppercase.
        static func eyebrow(_ size: CGFloat = 10) -> Font {
            .system(size: size, weight: .heavy)
        }
    }

    /// Standard horizontal page gutter on iOS / macOS.
    enum Layout {
        static let gutter: CGFloat = 22
        static let rowVertical: CGFloat = 14
        static let sectionSpacing: CGFloat = 28
    }
}

// MARK: - Adaptive color helper

private func adaptive(light: Color, dark: Color) -> Color {
    #if canImport(UIKit)
    return Color(UIColor { trait in
        UIColor(trait.userInterfaceStyle == .dark ? dark : light)
    })
    #elseif canImport(AppKit)
    return Color(NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
        return NSColor(isDark ? dark : light)
    })
    #else
    return dark
    #endif
}

// MARK: - Surface modifiers

extension View {
    /// Editorial card — flat surface, hairline rule, sharp radius, no shadow.
    /// Replaces the legacy Aurora cushy card.
    func auroraCard(padding: CGFloat = 16, radius: CGFloat = Theme.Radius.card) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
    }

    /// Backwards-compatible alias for older call sites.
    func clarityCard(padding: CGFloat = 16) -> some View {
        auroraCard(padding: padding)
    }

    /// Floating panel — used for the composer dock and modal sheets.
    /// Solid surface with a single hairline rule, very subtle drop.
    func auroraGlass(radius: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
            )
            .shadow(color: Theme.Palette.shadow, radius: 30, x: 0, y: 18)
    }

    /// AI-touched surface — single saffron underline, no swirling rainbows.
    func auroraGlow(radius: CGFloat = Theme.Radius.card, intensity: CGFloat = 1.0) -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.accent)
                .frame(height: 1.5 * intensity)
                .opacity(0.85 * intensity)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A list row with no fill, just a hairline divider beneath. Tap target only.
    func dossierRow(verticalPadding: CGFloat = Theme.Layout.rowVertical) -> some View {
        self
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// Hairline divider — the workhorse separator of the language.
    func dossierDivider() -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.border)
                .frame(height: 0.5)
        }
    }

    /// Editorial input field — flat surface, hairline, no rounded pill.
    func dossierField() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Palette.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
    }

    /// Standard horizontal gutter for the page column.
    func pageGutter() -> some View {
        self.padding(.horizontal, Theme.Layout.gutter)
    }
}

// MARK: - Eyebrow label (small caps section header)

struct EyebrowLabel: View {
    let text: String
    var trailing: String? = nil
    var accent: Color = Theme.Palette.accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Rectangle()
                .fill(accent)
                .frame(width: 18, height: 1.5)
                .padding(.bottom, 4)
            Text(text.uppercased())
                .font(Theme.Typography.eyebrow())
                .tracking(2.4)
                .foregroundStyle(Theme.Palette.textPrimary)
            if let trailing {
                Spacer()
                Text(trailing.uppercased())
                    .font(Theme.Typography.mono(10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
        }
    }
}

// MARK: - Button styles (names preserved; behavior re-imagined)

/// Primary CTA — solid ink rectangle, serif label. The opposite of a gradient pill.
struct AuroraPrimaryButtonStyle: ButtonStyle {
    var isProminent: Bool = true
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold, design: .serif))
            .tracking(0.6)
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 14 : 22)
            .padding(.vertical, compact ? 9 : 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Palette.textPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Color.white.opacity(isProminent ? 0.06 : 0), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

/// Secondary — flat hairline-bordered rectangle, no fill, ink type.
struct AuroraSecondaryButtonStyle: ButtonStyle {
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(Theme.Palette.textPrimary)
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Palette.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

/// Icon button — small SQUARE (not circle), thin hairline border, no fill.
/// This single change makes the entire chrome look different at a glance.
struct AuroraIconButtonStyle: ButtonStyle {
    var size: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size <= 30 ? 12 : 13, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Palette.surface.opacity(0.0001))   // hit area
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

/// Accent icon button — saffron-filled square. Use sparingly for primary actions.
struct AuroraAccentIconButtonStyle: ButtonStyle {
    var size: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size <= 30 ? 12 : 13, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Palette.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Appearance preference (System / Light / Dark)

/// User-selectable color scheme override, persisted via @AppStorage.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Storage key shared between the modifier and the settings UI.
enum AppearanceStorage {
    static let key = "appearancePreference"
}

/// Applies the user's persisted appearance preference at the root of the view tree.
private struct AppearancePreferenceModifier: ViewModifier {
    @AppStorage(AppearanceStorage.key) private var raw: String = AppearancePreference.system.rawValue

    func body(content: Content) -> some View {
        let preference = AppearancePreference(rawValue: raw) ?? .system
        content.preferredColorScheme(preference.colorScheme)
    }
}

extension View {
    /// Apply the user's saved Light/Dark/System preference.
    func appearancePreference() -> some View {
        modifier(AppearancePreferenceModifier())
    }
}
