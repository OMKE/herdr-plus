import SwiftUI

enum ToolLabels: String, Codable, CaseIterable, Identifiable {
    case text, symbols
    var id: String { rawValue }
    var label: String { self == .text ? "Text" : "Symbols" }
}

enum ToolKey: String, Codable, CaseIterable, Identifiable {
    case esc, tab, shiftTab, ctrl, ctrlC, ctrlD, ctrlR, ctrlL, ctrlZ, ctrlU, ctrlW, ctrlO
    case slash, pipe, tilde, dash, backslash
    case up, down, left, right, home, end, pageUp, pageDown
    case one, two, three, enter, paste, joystick, keyboard
    case mic, photo, commands, terminal

    var id: String { rawValue }

    static let defaultTerminal: [ToolKey] = [.esc, .tab, .shiftTab, .ctrl, .ctrlC, .ctrlD, .ctrlR, .slash, .paste]
    static let defaultChat: [ToolKey] = [.esc, .shiftTab, .ctrlC, .one, .two, .three, .enter]

    static let terminalChoices: [ToolKey] = [.esc, .tab, .shiftTab, .ctrl, .ctrlC, .ctrlD, .ctrlR, .ctrlL, .ctrlZ, .ctrlU, .ctrlW, .ctrlO, .slash, .pipe, .tilde, .dash, .backslash, .up, .down, .left, .right, .home, .end, .pageUp, .pageDown, .one, .two, .three, .paste]
    static let chatChoices: [ToolKey] = [.esc, .tab, .shiftTab, .ctrlC, .ctrlO, .ctrlR, .one, .two, .three, .up, .down, .enter, .commands, .paste, .photo, .mic]

    var text: String {
        switch self {
        case .esc: "esc"
        case .tab: "tab"
        case .shiftTab: "⇧tab"
        case .ctrl: "ctrl"
        case .ctrlC: "^C"
        case .ctrlD: "^D"
        case .ctrlR: "^R"
        case .ctrlL: "^L"
        case .ctrlZ: "^Z"
        case .ctrlU: "^U"
        case .ctrlW: "^W"
        case .ctrlO: "^O"
        case .slash: "/"
        case .pipe: "|"
        case .tilde: "~"
        case .dash: "-"
        case .backslash: "\\"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .home: "home"
        case .end: "end"
        case .pageUp: "pgup"
        case .pageDown: "pgdn"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .enter: "⏎"
        case .paste: "paste"
        case .joystick: "arrows"
        case .keyboard: "kbd"
        case .mic: "mic"
        case .photo: "photo"
        case .commands: "/cmd"
        case .terminal: "term"
        }
    }

    var symbol: String? {
        switch self {
        case .esc: "escape"
        case .tab: "arrow.right.to.line"
        case .shiftTab: "arrow.left.to.line"
        case .ctrl: "control"
        case .ctrlC: "xmark.octagon"
        case .ctrlD: "eject"
        case .ctrlR: "clock.arrow.circlepath"
        case .ctrlL: "clear"
        case .ctrlZ: "pause"
        case .ctrlU: "delete.left"
        case .ctrlW: "delete.backward"
        case .ctrlO: "arrow.up.left.and.arrow.down.right"
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .home: "arrow.left.to.line.compact"
        case .end: "arrow.right.to.line.compact"
        case .pageUp: "chevron.up.2"
        case .pageDown: "chevron.down.2"
        case .enter: "return"
        case .paste: "doc.on.clipboard"
        case .joystick: "arrow.up.and.down.and.arrow.left.and.right"
        case .keyboard: "keyboard"
        case .mic: "mic"
        case .photo: "photo"
        case .commands: "command"
        case .terminal: "apple.terminal"
        default: nil
        }
    }

    var title: String {
        switch self {
        case .esc: "Escape"
        case .tab: "Tab"
        case .shiftTab: "Shift-Tab (mode)"
        case .ctrl: "Control (sticky)"
        case .ctrlC: "Interrupt ^C"
        case .ctrlD: "EOF ^D"
        case .ctrlR: "History search ^R"
        case .ctrlL: "Clear ^L"
        case .ctrlZ: "Suspend ^Z"
        case .ctrlU: "Kill line ^U"
        case .ctrlW: "Kill word ^W"
        case .ctrlO: "Expand ^O"
        case .slash: "Slash"
        case .pipe: "Pipe"
        case .tilde: "Tilde"
        case .dash: "Dash"
        case .backslash: "Backslash"
        case .up: "Up"
        case .down: "Down"
        case .left: "Left"
        case .right: "Right"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "Page up"
        case .pageDown: "Page down"
        case .one: "Option 1"
        case .two: "Option 2"
        case .three: "Option 3"
        case .enter: "Return"
        case .paste: "Paste"
        case .joystick: "Arrow joystick"
        case .keyboard: "Keyboard"
        case .mic: "Dictation"
        case .photo: "Photo"
        case .commands: "Slash commands"
        case .terminal: "Terminal"
        }
    }

    func bytes(appCursor: Bool) -> String? {
        let csi = appCursor ? "\u{1b}O" : "\u{1b}["
        switch self {
        case .esc: return "\u{1b}"
        case .tab: return "\t"
        case .shiftTab: return "\u{1b}[Z"
        case .ctrlC: return "\u{03}"
        case .ctrlD: return "\u{04}"
        case .ctrlR: return "\u{12}"
        case .ctrlL: return "\u{0c}"
        case .ctrlZ: return "\u{1a}"
        case .ctrlU: return "\u{15}"
        case .ctrlW: return "\u{17}"
        case .ctrlO: return "\u{0f}"
        case .slash: return "/"
        case .pipe: return "|"
        case .tilde: return "~"
        case .dash: return "-"
        case .backslash: return "\\"
        case .up: return csi + "A"
        case .down: return csi + "B"
        case .right: return csi + "C"
        case .left: return csi + "D"
        case .home: return "\u{1b}[H"
        case .end: return "\u{1b}[F"
        case .pageUp: return "\u{1b}[5~"
        case .pageDown: return "\u{1b}[6~"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .enter: return "\r"
        default: return nil
        }
    }

    var coreName: String? {
        switch self {
        case .esc: "esc"
        case .tab: "tab"
        case .shiftTab: "shift+tab"
        case .ctrlC: "ctrl+c"
        case .ctrlD: "ctrl+d"
        case .ctrlR: "ctrl+r"
        case .ctrlL: "ctrl+l"
        case .ctrlZ: "ctrl+z"
        case .ctrlU: "ctrl+u"
        case .ctrlW: "ctrl+w"
        case .ctrlO: "ctrl+o"
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        case .home: "home"
        case .end: "end"
        case .pageUp: "pageup"
        case .pageDown: "pagedown"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .enter: "enter"
        case .slash: "/"
        case .pipe: "|"
        case .tilde: "~"
        case .dash: "-"
        case .backslash: "\\"
        default: nil
        }
    }

    var repeats: Bool {
        switch self {
        case .up, .down, .left, .right, .pageUp, .pageDown, .ctrlW: true
        default: false
        }
    }

    var answer: Bool { self == .one || self == .two || self == .three }
}

struct Keycap: View {
    let key: ToolKey
    var labels: ToolLabels = .text
    var on = false
    var accent = false
    var glass = true
    var compact = false

    var body: some View {
        let useSymbol = labels == .symbols ? key.symbol != nil : (key.symbol != nil && key.text.count > 4)
        Group {
            if useSymbol, let s = key.symbol {
                Image(systemName: s).font(.system(size: compact ? 12 : 14, weight: .semibold))
            } else {
                Text(key.text).font(.system(size: compact ? 12 : 14, weight: .semibold, design: .monospaced))
            }
        }
        .foregroundStyle(on ? Theme.onAccent : accent ? Theme.amber : Theme.text)
        .frame(minWidth: compact ? 32 : 40, minHeight: compact ? 28 : 34)
        .padding(.horizontal, 4)
        .background {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 9).fill(on ? Theme.amber : Theme.border.opacity(0.9)).offset(y: 1.5)
                RoundedRectangle(cornerRadius: 9)
                    .fill(on ? AnyShapeStyle(Theme.amber) : accent ? AnyShapeStyle(Theme.amberBg) : glass ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Theme.raised))
                    .overlay(RoundedRectangle(cornerRadius: 9).fill(on || accent || !glass ? Color.clear : Theme.raised.opacity(0.55)))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? Theme.amber : accent ? Theme.amberBorder : Theme.border.opacity(0.8), lineWidth: 0.75))
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct PressKey: View {
    let key: ToolKey
    var labels: ToolLabels = .text
    var on = false
    var accent = false
    var glass = true
    var disabled = false
    let fire: () -> Void
    @State private var repeater = KeyRepeater()
    @State private var hold: Task<Void, Never>?
    @State private var repeated = false

    var body: some View {
        Button {
            guard !disabled else { return }
            if !repeated { fire() }
            repeated = false
        } label: {
            Keycap(key: key, labels: labels, on: on, accent: accent, glass: glass)
                .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(PressStyle(onPress: pressed))
        .accessibilityLabel(key.title)
    }

    private func pressed(_ isDown: Bool) {
        hold?.cancel()
        repeater.stop()
        guard isDown, !disabled else { return }
        repeated = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard key.repeats else { return }
        hold = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            repeated = true
            repeater.start(fire)
        }
    }
}

struct PressStyle: ButtonStyle {
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, v in onPress(v) }
    }
}
