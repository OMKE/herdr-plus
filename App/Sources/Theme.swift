import SwiftUI
import UIKit
import HerdrKit

@MainActor
enum Theme {
    static var c: ThemeStore.Resolved { ThemeStore.shared.colors }
    static var terminal: Color { c.terminal }
    static var chrome: Color { c.chrome }
    static var chromeDeep: Color { c.chromeDeep }
    static var raised: Color { c.raised }
    static var selected: Color { c.selected }
    static var selectedStrong: Color { c.selectedStrong }
    static var border: Color { c.border }
    static var text: Color { c.text }
    static var muted: Color { c.muted }
    static var dim: Color { c.dim }
    static var amber: Color { c.accent }
    static var amberBg: Color { c.accentBg }
    static var amberBorder: Color { c.accentBorder }
    static var onAccent: Color { c.accentInk }
    static var green: Color { c.green }
    static var red: Color { c.red }
    static var blue: Color { c.blue }
    static var body: Color { c.body }
    static var codeInk: Color { c.codeInk }
    static let claude = Color(hex: "#d9774f")

    static let spacePalette = ["#d9774f", "#8aa4d6", "#4cc26a", "#c678dd", "#f0b14a", "#56b6c2", "#e06c75"]

    static func stateColor(_ s: AgentState) -> Color {
        switch s {
        case .blocked: amber
        case .error: red
        case .working: blue
        case .done: green
        case .idle: dim
        case .unknown: dim
        }
    }

    static func stateLabel(_ s: AgentState) -> String {
        switch s {
        case .blocked: "Needs you"
        case .error: "Error"
        case .working: "Working"
        case .done: "Done"
        case .idle: "Idle"
        case .unknown: ""
        }
    }

    static func spaceColor(_ space: Space) -> Color {
        if let c = space.color, c.hasPrefix("#") { return Color(hex: c) }
        var h = 0
        for u in space.id.unicodeScalars { h = (h &* 31 &+ Int(u.value)) & 0x7fffffff }
        return Color(hex: spacePalette[h % spacePalette.count])
    }

    static var ansi: [String] { ThemeStore.shared.palette.ansi }
}

extension Color {
    init(hex: String) {
        let ui = UIColor(hex: hex)
        self.init(uiColor: ui)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: CGFloat
        if s.count == 3 {
            r = CGFloat((v >> 8) & 0xF) / 15
            g = CGFloat((v >> 4) & 0xF) / 15
            b = CGFloat(v & 0xF) / 15
        } else {
            r = CGFloat((v >> 16) & 0xFF) / 255
            g = CGFloat((v >> 8) & 0xFF) / 255
            b = CGFloat(v & 0xFF) / 255
        }
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

struct ProgramIcon: View {
    let program: Program?
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Color(hex: program?.tile ?? "#1c1d21"))
            if let key = program?.icon, UIImage(named: "prog-\(key)") != nil {
                Image("prog-\(key)")
                    .resizable()
                    .renderingMode(program?.tint == true ? .template : .original)
                    .foregroundStyle(Color(hex: program?.color ?? "#ffffff"))
                    .scaledToFit()
                    .padding(size * 0.18)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
    }
}

struct StateDot: View {
    let state: AgentState
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(Theme.stateColor(state))
            .frame(width: size, height: size)
            .opacity(state == .unknown ? 0 : 1)
    }
}

struct NeedsYouPill: View {
    var text = "Needs you"

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.amberBg))
            .overlay(Capsule().stroke(Theme.amberBorder, lineWidth: 1))
    }
}

struct Monogram: View {
    let space: Space
    var size: CGFloat = 26

    var body: some View {
        Text(space.monogram)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Theme.spaceColor(space).opacity(0.85)))
    }
}
