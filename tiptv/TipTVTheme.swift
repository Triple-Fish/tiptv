//
//  TipTVTheme.swift
//  tiptv
//

import Combine
import Foundation
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case tiptvCyan = "tiptv Teal"
    case pureOLED = "Pure OLED Dark"
    case midnightEmerald = "Midnight Emerald"
    case cyberSunset = "Cyber Sunset"
    case solarAmber = "Solar Amber"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .tiptvCyan:
            return "Vibrant teal & marine sapphire matching tiptv's icon"
        case .pureOLED:
            return "Pitch black with crisp crimson neon for OLED screens"
        case .midnightEmerald:
            return "Deep forest jade with luminous mint glow"
        case .cyberSunset:
            return "Synthwave violet with vibrant hot neon magenta"
        case .solarAmber:
            return "Warm golden cinema glow with espresso tones"
        }
    }

    var accent: Color {
        switch self {
        case .tiptvCyan:
            return Color(red: 0.26, green: 0.75, blue: 0.85) // Luminous tiptv Icon Teal (#41BED9)
        case .pureOLED:
            return Color(red: 0.90, green: 0.08, blue: 0.15) // Neon Crimson
        case .midnightEmerald:
            return Color(red: 0.06, green: 0.72, blue: 0.50) // Emerald Mint
        case .cyberSunset:
            return Color(red: 0.92, green: 0.28, blue: 0.60) // Hot Magenta
        case .solarAmber:
            return Color(red: 0.96, green: 0.62, blue: 0.04) // Radiant Amber
        }
    }

    var aqua: Color {
        switch self {
        case .tiptvCyan:
            return Color(red: 0.32, green: 0.82, blue: 0.89) // Bright Sky Teal (#52D1E3)
        case .pureOLED:
            return Color(red: 0.22, green: 0.74, blue: 0.97) // Ice Blue
        case .midnightEmerald:
            return Color(red: 0.20, green: 0.83, blue: 0.60) // Mint Aqua
        case .cyberSunset:
            return Color(red: 0.55, green: 0.36, blue: 0.96) // Electric Violet
        case .solarAmber:
            return Color(red: 0.98, green: 0.57, blue: 0.24) // Tangerine
        }
    }

    var liveRed: Color {
        switch self {
        case .tiptvCyan:
            return Color(red: 0.98, green: 0.22, blue: 0.28)
        case .pureOLED:
            return Color(red: 1.0, green: 0.18, blue: 0.24)
        case .midnightEmerald:
            return Color(red: 0.98, green: 0.26, blue: 0.32)
        case .cyberSunset:
            return Color(red: 1.0, green: 0.20, blue: 0.40)
        case .solarAmber:
            return Color(red: 0.95, green: 0.25, blue: 0.20)
        }
    }

    var ink: Color {
        switch self {
        case .tiptvCyan:
            return Color(red: 0.01, green: 0.04, blue: 0.06) // Deep Marine Ink
        case .pureOLED:
            return Color.black
        case .midnightEmerald:
            return Color(red: 0.02, green: 0.06, blue: 0.04)
        case .cyberSunset:
            return Color(red: 0.05, green: 0.03, blue: 0.09)
        case .solarAmber:
            return Color(red: 0.06, green: 0.04, blue: 0.03)
        }
    }

    var surface: Color {
        switch self {
        case .tiptvCyan:
            return Color(red: 0.04, green: 0.09, blue: 0.12) // Dark Teal-Grey Surface
        case .pureOLED:
            return Color(red: 0.07, green: 0.07, blue: 0.07)
        case .midnightEmerald:
            return Color(red: 0.04, green: 0.11, blue: 0.08)
        case .cyberSunset:
            return Color(red: 0.10, green: 0.06, blue: 0.16)
        case .solarAmber:
            return Color(red: 0.11, green: 0.08, blue: 0.06)
        }
    }

    var cardBackground: Color {
        switch self {
        case .pureOLED:
            return Color(white: 0.08)
        case .tiptvCyan:
            return Color(red: 0.04, green: 0.11, blue: 0.15).opacity(0.7)
        default:
            return Color.white.opacity(0.06)
        }
    }

    var cardBorder: Color {
        switch self {
        case .pureOLED:
            return Color.white.opacity(0.14)
        case .tiptvCyan:
            return Color(red: 0.26, green: 0.75, blue: 0.85).opacity(0.22)
        default:
            return Color.white.opacity(0.10)
        }
    }

    var previewColors: [Color] {
        [accent, aqua, surface]
    }

    var artworkGradient: LinearGradient {
        switch self {
        case .tiptvCyan:
            return LinearGradient(
                colors: [Color(red: 0.26, green: 0.75, blue: 0.85), Color(red: 0.16, green: 0.48, blue: 0.52)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .pureOLED:
            return LinearGradient(
                colors: [Color(red: 0.85, green: 0.08, blue: 0.15), Color(red: 0.45, green: 0.04, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .midnightEmerald:
            return LinearGradient(
                colors: [Color(red: 0.06, green: 0.72, blue: 0.50), Color(red: 0.04, green: 0.45, blue: 0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cyberSunset:
            return LinearGradient(
                colors: [Color(red: 0.92, green: 0.28, blue: 0.60), Color(red: 0.55, green: 0.22, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .solarAmber:
            return LinearGradient(
                colors: [Color(red: 0.96, green: 0.62, blue: 0.04), Color(red: 0.88, green: 0.38, blue: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var heroGradient: LinearGradient {
        switch self {
        case .tiptvCyan:
            return LinearGradient(
                colors: [Color(red: 0.12, green: 0.38, blue: 0.44), Color(red: 0.05, green: 0.18, blue: 0.24), Color(red: 0.01, green: 0.04, blue: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .pureOLED:
            return LinearGradient(
                colors: [Color(red: 0.16, green: 0.16, blue: 0.16), Color(red: 0.08, green: 0.08, blue: 0.08), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .midnightEmerald:
            return LinearGradient(
                colors: [Color(red: 0.05, green: 0.24, blue: 0.18), Color(red: 0.04, green: 0.16, blue: 0.12), Color(red: 0.02, green: 0.06, blue: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cyberSunset:
            return LinearGradient(
                colors: [Color(red: 0.32, green: 0.08, blue: 0.35), Color(red: 0.18, green: 0.06, blue: 0.28), Color(red: 0.05, green: 0.03, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .solarAmber:
            return LinearGradient(
                colors: [Color(red: 0.28, green: 0.15, blue: 0.04), Color(red: 0.18, green: 0.09, blue: 0.03), Color(red: 0.06, green: 0.04, blue: 0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var contentBackground: LinearGradient {
        switch self {
        case .tiptvCyan:
            return LinearGradient(
                colors: [Color(red: 0.01, green: 0.04, blue: 0.06), Color(red: 0.02, green: 0.07, blue: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .pureOLED:
            return LinearGradient(
                colors: [Color.black, Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        case .midnightEmerald:
            return LinearGradient(
                colors: [Color(red: 0.02, green: 0.06, blue: 0.04), Color(red: 0.03, green: 0.09, blue: 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .cyberSunset:
            return LinearGradient(
                colors: [Color(red: 0.05, green: 0.03, blue: 0.09), Color(red: 0.08, green: 0.04, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .solarAmber:
            return LinearGradient(
                colors: [Color(red: 0.06, green: 0.04, blue: 0.03), Color(red: 0.10, green: 0.07, blue: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private let userDefaultsKey = "tiptv_selected_theme"

    @Published var currentTheme: AppTheme = .tiptvCyan {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: userDefaultsKey)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: userDefaultsKey) ?? UserDefaults.standard.string(forKey: "tivvy_selected_theme")
        if let saved = saved {
            if saved == "Obsidian Indigo" || saved == "tivvy Cyan" || saved == "tivvy Teal" || saved == "tiptv Cyan" || saved == "tiptv Teal" {
                currentTheme = .tiptvCyan
            } else if let theme = AppTheme(rawValue: saved) {
                currentTheme = theme
            }
        } else {
            currentTheme = .tiptvCyan
        }
    }

    func setTheme(_ theme: AppTheme) {
        currentTheme = theme
    }

    var accent: Color {
        currentTheme.accent
    }
}

enum tiptvTheme {
    static var current: AppTheme {
        ThemeManager.shared.currentTheme
    }

    static var accent: Color { current.accent }
    static var aqua: Color { current.aqua }
    static var liveRed: Color { current.liveRed }
    static var ink: Color { current.ink }
    static var surface: Color { current.surface }
    static var cardBackground: Color { current.cardBackground }
    static var cardBorder: Color { current.cardBorder }
    static var artworkGradient: LinearGradient { current.artworkGradient }
    static var heroGradient: LinearGradient { current.heroGradient }
    static var contentBackground: LinearGradient { current.contentBackground }
}

struct tiptvBrandLogo: View {
    var size: CGFloat = 26
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        HStack(spacing: 0) {
            Text("t")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            ZStack(alignment: .top) {
                Text("ı") // dotless i
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Circle()
                    .fill(themeManager.accent)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: size * 0.16, weight: .black))
                            .foregroundStyle(.white)
                            .offset(x: 0.5)
                    }
                    .offset(y: size * 0.02)
            }

            Text("ptv")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Compatibility Typealiases
typealias TipTVTheme = tiptvTheme
typealias tivvyTheme = tiptvTheme
typealias TivvyTheme = tiptvTheme

typealias TipTVBrandLogo = tiptvBrandLogo
typealias tivvyBrandLogo = tiptvBrandLogo
typealias TivvyBrandLogo = tiptvBrandLogo
