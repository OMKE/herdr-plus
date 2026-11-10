import SwiftUI
import UIKit
import Observation

struct Palette: Identifiable, Equatable {
    let id: String
    let name: String
    let dark: Bool
    let terminal: String
    let chrome: String
    let raised: String
    let border: String
    let text: String
    let muted: String
    let accent: String
    let green: String
    let red: String
    let blue: String
    let ansi: [String]
    var onAccent: String? = nil

    var accentInk: String { onAccent ?? (dark ? "#000000" : "#ffffff") }

    static let herdr = Palette(id: "herdr", name: "Herdr", dark: true,
        terminal: "#0d0d0f", chrome: "#161618", raised: "#1c1c1f", border: "#2e2e32",
        text: "#ececee", muted: "#8a8a90", accent: "#f0b14a", green: "#4cc26a", red: "#e5534b", blue: "#8aa4d6",
        ansi: ["#3f4451", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#d7dae0",
               "#5c6370", "#ef7b85", "#a9d48a", "#f0cd8c", "#74bdf7", "#d68ae8", "#67c7d3", "#ffffff"])

    static let dracula = Palette(id: "dracula", name: "Dracula", dark: true,
        terminal: "#282a36", chrome: "#21222c", raised: "#343746", border: "#44475a",
        text: "#f8f8f2", muted: "#9ea8c7", accent: "#ffb86c", green: "#50fa7b", red: "#ff5555", blue: "#bd93f9",
        ansi: ["#21222c", "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
               "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff", "#ffffff"])

    static let nord = Palette(id: "nord", name: "Nord", dark: true,
        terminal: "#2e3440", chrome: "#272c36", raised: "#3b4252", border: "#4c566a",
        text: "#eceff4", muted: "#a3acbd", accent: "#ebcb8b", green: "#a3be8c", red: "#bf616a", blue: "#81a1c1",
        ansi: ["#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
               "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"])

    static let tokyoNight = Palette(id: "tokyo-night", name: "Tokyo Night", dark: true,
        terminal: "#1a1b26", chrome: "#16161e", raised: "#24283b", border: "#2f334d",
        text: "#c0caf5", muted: "#8089b3", accent: "#e0af68", green: "#9ece6a", red: "#f7768e", blue: "#7aa2f7",
        ansi: ["#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
               "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5"])

    static let mocha = Palette(id: "catppuccin-mocha", name: "Catppuccin Mocha", dark: true,
        terminal: "#1e1e2e", chrome: "#181825", raised: "#313244", border: "#45475a",
        text: "#cdd6f4", muted: "#a6adc8", accent: "#fab387", green: "#a6e3a1", red: "#f38ba8", blue: "#89b4fa",
        ansi: ["#45475a", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
               "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"])

    static let gruvbox = Palette(id: "gruvbox", name: "Gruvbox", dark: true,
        terminal: "#282828", chrome: "#1d2021", raised: "#3c3836", border: "#504945",
        text: "#ebdbb2", muted: "#a89984", accent: "#fabd2f", green: "#b8bb26", red: "#fb4934", blue: "#83a598",
        ansi: ["#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984",
               "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2"])

    static let oneDark = Palette(id: "one-dark", name: "One Dark", dark: true,
        terminal: "#282c34", chrome: "#21252b", raised: "#2c313a", border: "#3e4451",
        text: "#abb2bf", muted: "#7f8693", accent: "#e5c07b", green: "#98c379", red: "#e06c75", blue: "#61afef",
        ansi: ["#3f4451", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#d7dae0",
               "#5c6370", "#ef7b85", "#a9d48a", "#f0cd8c", "#74bdf7", "#d68ae8", "#67c7d3", "#ffffff"])

    static let solarizedDark = Palette(id: "solarized-dark", name: "Solarized Dark", dark: true,
        terminal: "#002b36", chrome: "#00212b", raised: "#073642", border: "#0f4b5a",
        text: "#93a1a1", muted: "#738a8f", accent: "#b58900", green: "#859900", red: "#dc322f", blue: "#268bd2",
        ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
               "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"])

    static let herdrLight = Palette(id: "herdr-light", name: "Herdr Light", dark: false,
        terminal: "#fbfbfa", chrome: "#f1f1ef", raised: "#ffffff", border: "#dcdcd8",
        text: "#1c1c1f", muted: "#66666c", accent: "#b8730c", green: "#2f8f47", red: "#cf3a31", blue: "#3a64b0",
        ansi: ["#383a42", "#e45649", "#50a14f", "#c18401", "#4078f2", "#a626a4", "#0184bc", "#a0a1a7",
               "#4f525e", "#e06c75", "#3f953e", "#a77300", "#3366d6", "#b33db1", "#0f7fa8", "#ffffff"])

    static let githubLight = Palette(id: "github-light", name: "GitHub Light", dark: false,
        terminal: "#ffffff", chrome: "#f6f8fa", raised: "#ffffff", border: "#d0d7de",
        text: "#1f2328", muted: "#656d76", accent: "#9a6700", green: "#1a7f37", red: "#cf222e", blue: "#0969da",
        ansi: ["#24292f", "#cf222e", "#116329", "#4d2d00", "#0969da", "#8250df", "#1b7c83", "#6e7781",
               "#57606a", "#a40e26", "#1a7f37", "#633c01", "#218bff", "#a475f9", "#3192aa", "#8c959f"])

    static let oneLight = Palette(id: "one-light", name: "One Light", dark: false,
        terminal: "#fafafa", chrome: "#f0f0f1", raised: "#ffffff", border: "#dbdbdc",
        text: "#383a42", muted: "#696c77", accent: "#c18401", green: "#50a14f", red: "#e45649", blue: "#4078f2",
        ansi: ["#383a42", "#e45649", "#50a14f", "#c18401", "#4078f2", "#a626a4", "#0184bc", "#a0a1a7",
               "#4f525e", "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2", "#ffffff"])

    static let latte = Palette(id: "catppuccin-latte", name: "Catppuccin Latte", dark: false,
        terminal: "#eff1f5", chrome: "#e6e9ef", raised: "#f7f8fa", border: "#ccd0da",
        text: "#4c4f69", muted: "#6c6f85", accent: "#df8e1d", green: "#40a02b", red: "#d20f39", blue: "#1e66f5",
        ansi: ["#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#acb0be",
               "#6c6f85", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#bcc0cc"])

    static let solarizedLight = Palette(id: "solarized-light", name: "Solarized Light", dark: false,
        terminal: "#fdf6e3", chrome: "#eee8d5", raised: "#f7f0dc", border: "#d9d2bf",
        text: "#586e75", muted: "#7f8f91", accent: "#b58900", green: "#859900", red: "#dc322f", blue: "#268bd2",
        ansi: ["#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5",
               "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"])

    static let darkThemes = [herdr, dracula, nord, tokyoNight, mocha, gruvbox, oneDark, solarizedDark]
    static let lightThemes = [herdrLight, githubLight, oneLight, latte, solarizedLight]
    static let all = darkThemes + lightThemes

    static func named(_ id: String, dark: Bool) -> Palette {
        all.first { $0.id == id } ?? (dark ? herdr : herdrLight)
    }
}

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var palette: Palette = .herdr
    var systemDark = true
    var terminalFont: TermFont = .sfMono
    var chatFont: ChatFont = .system
    var chatSize: Double = 15
    var optionAsMeta = true

    private(set) var colors = Resolved(.herdr)

    func apply(_ s: AppSettings) {
        let dark = s.appearance == .dark || (s.appearance == .system && systemDark)
        let p = dark ? Palette.named(s.darkTheme, dark: true) : Palette.named(s.lightTheme, dark: false)
        if p != palette {
            palette = p
            colors = Resolved(p)
        }
        if terminalFont != s.terminalFont { terminalFont = s.terminalFont }
        if chatFont != s.chatFont { chatFont = s.chatFont }
        if chatSize != s.chatSize { chatSize = s.chatSize }
        if optionAsMeta != s.optionAsMeta { optionAsMeta = s.optionAsMeta }
    }

    struct Resolved {
        let terminal, chrome, chromeDeep, raised, selected, selectedStrong, border, text, muted, dim: Color
        let accent, accentBg, accentBorder, accentInk, green, red, blue, body, codeInk: Color

        init(_ p: Palette) {
            func mix(_ a: String, _ b: String, _ t: CGFloat) -> Color { Color(uiColor: UIColor.mix(a, b, t)) }
            terminal = Color(hex: p.terminal)
            chrome = Color(hex: p.chrome)
            chromeDeep = mix(p.terminal, p.chrome, 0.6)
            raised = Color(hex: p.raised)
            selected = mix(p.raised, p.text, p.dark ? 0.06 : 0.05)
            selectedStrong = mix(p.raised, p.text, p.dark ? 0.1 : 0.09)
            border = Color(hex: p.border)
            text = Color(hex: p.text)
            muted = Color(hex: p.muted)
            dim = mix(p.muted, p.terminal, 0.22)
            accent = Color(hex: p.accent)
            accentBg = mix(p.terminal, p.accent, p.dark ? 0.18 : 0.14)
            accentBorder = mix(p.terminal, p.accent, p.dark ? 0.34 : 0.4)
            accentInk = Color(hex: p.accentInk)
            green = Color(hex: p.green)
            red = Color(hex: p.red)
            blue = Color(hex: p.blue)
            body = mix(p.text, p.terminal, 0.1)
            codeInk = mix(p.accent, p.text, 0.25)
        }
    }
}

extension UIColor {
    static func mix(_ a: String, _ b: String, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(hex: a).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(hex: b).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}

enum TermFont: String, Codable, CaseIterable, Identifiable {
    case sfMono, menlo, courier, jetbrains, hack, meslo
    var id: String { rawValue }

    var label: String {
        switch self {
        case .sfMono: "SF Mono"
        case .menlo: "Menlo"
        case .courier: "Courier New"
        case .jetbrains: "JetBrains Mono"
        case .hack: "Hack Nerd Font"
        case .meslo: "MesloLGS NF"
        }
    }

    var note: String? {
        switch self {
        case .hack, .meslo: "Nerd Font glyphs"
        default: nil
        }
    }

    private var postScript: (regular: String, bold: String)? {
        switch self {
        case .sfMono: nil
        case .menlo: ("Menlo-Regular", "Menlo-Bold")
        case .courier: ("CourierNewPSMT", "CourierNewPS-BoldMT")
        case .jetbrains: ("JetBrainsMono-Regular", "JetBrainsMono-Bold")
        case .hack: ("HackNFM-Regular", "HackNFM-Bold")
        case .meslo: ("MesloLGS-NF-Regular", "MesloLGS-NF-Bold")
        }
    }

    func uiFont(_ size: CGFloat, bold: Bool = false) -> UIFont {
        if let ps = postScript, let f = UIFont(name: bold ? ps.bold : ps.regular, size: size) { return f }
        return UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    func font(_ size: CGFloat, bold: Bool = false) -> Font {
        if let ps = postScript, UIFont(name: ps.regular, size: size) != nil { return .custom(bold ? ps.bold : ps.regular, fixedSize: size) }
        return .system(size: size, weight: bold ? .bold : .regular, design: .monospaced)
    }
}

enum ChatFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, mono
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "San Francisco"
        case .rounded: "SF Rounded"
        case .serif: "New York"
        case .mono: "Terminal font"
        }
    }

    @MainActor func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system: .system(size: size, weight: weight)
        case .rounded: .system(size: size, weight: weight, design: .rounded)
        case .serif: .system(size: size, weight: weight, design: .serif)
        case .mono: ThemeStore.shared.terminalFont.font(size - 1.5, bold: weight == .semibold || weight == .bold)
        }
    }
}

enum Typo {
    @MainActor static var scale: CGFloat { CGFloat(ThemeStore.shared.chatSize / 15) }
    @MainActor static func chat(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        ThemeStore.shared.chatFont.font(size * scale, weight: weight)
    }
    @MainActor static func code(_ size: CGFloat) -> Font {
        ThemeStore.shared.terminalFont.font(size * scale)
    }
}
