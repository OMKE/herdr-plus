import SwiftUI
import HerdrKit

enum PadDirection: CaseIterable {
    case up, down, left, right

    var code: String {
        switch self {
        case .up: "A"
        case .down: "B"
        case .right: "C"
        case .left: "D"
        }
    }

    var symbol: String {
        switch self {
        case .up: "chevron.up"
        case .down: "chevron.down"
        case .left: "chevron.left"
        case .right: "chevron.right"
        }
    }

    var offset: CGSize {
        switch self {
        case .up: CGSize(width: 0, height: -54)
        case .down: CGSize(width: 0, height: 54)
        case .left: CGSize(width: -54, height: 0)
        case .right: CGSize(width: 54, height: 0)
        }
    }

    static func from(_ t: CGSize, threshold: CGFloat = 16) -> PadDirection? {
        guard hypot(t.width, t.height) >= threshold else { return nil }
        if abs(t.width) > abs(t.height) { return t.width > 0 ? .right : .left }
        return t.height > 0 ? .down : .up
    }
}

@MainActor
final class KeyRepeater {
    private var task: Task<Void, Never>?

    func start(_ fire: @escaping @MainActor () -> Void) {
        stop()
        fire()
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            var interval = 90
            while !Task.isCancelled {
                fire()
                try? await Task.sleep(for: .milliseconds(interval))
                interval = max(45, interval - 6)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

struct KeyBar: View {
    let blocked: Bool
    let session: TerminalSession?
    var keys: [ToolKey] = ToolKey.defaultTerminal
    var labels: ToolLabels = .text
    var glass = true
    @State private var padOpen = false
    @State private var sticky = false
    @State private var active: PadDirection?
    @State private var pressStart: Date?
    @State private var closing = false
    @State private var ctrl = false
    @State private var repeater = KeyRepeater()

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if blocked {
                        ForEach([ToolKey.one, .two, .three]) { k in
                            PressKey(key: k, labels: labels, accent: true, glass: glass, disabled: session == nil) { session?.send(k.text) }
                        }
                        divider
                    }
                    ForEach(keys.filter { !(blocked && $0.answer) }) { k in
                        PressKey(key: k, labels: labels, on: k == .ctrl && ctrl, glass: glass, disabled: session == nil) { fire(k) }
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 14)
                .padding(.vertical, 3)
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 10)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 22)
                }
            }
            divider
            joystick
            PressKey(key: .enter, labels: labels, glass: glass, disabled: session == nil) { session?.send("\r") }
            PressKey(key: .keyboard, labels: .symbols, on: session?.rawKeyboard == true, glass: glass, disabled: session == nil) {
                session?.rawKeyboard.toggle()
            }
            .padding(.trailing, 10)
        }
        .frame(height: 44)
        .padding(.bottom, 4)
        .overlay(alignment: .bottomTrailing) {
            if padOpen {
                pad
                    .padding(.trailing, 64)
                    .offset(y: -50)
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwiftTerm.TerminalView.controlModifierReset"))) { _ in
            ctrl = false
        }
    }

    private func fire(_ k: ToolKey) {
        guard let s = session else { return }
        switch k {
        case .ctrl:
            ctrl.toggle()
            s.view.controlModifier = ctrl
            if ctrl, !s.rawKeyboard { s.rawKeyboard = true }
        case .paste:
            guard let t = UIPasteboard.general.string, !t.isEmpty else { return }
            Task { await s.paste(t, submit: false) }
        default:
            if let b = k.bytes(appCursor: s.applicationCursor) { s.send(b) }
        }
    }

    private var joystick: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(padOpen ? Theme.onAccent : Theme.text)
            .frame(width: 40, height: 34)
            .background(RoundedRectangle(cornerRadius: 8).fill(padOpen ? Theme.amber : Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(padOpen ? Theme.amber : Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if pressStart == nil {
                            pressStart = Date()
                            if padOpen && sticky {
                                closing = true
                                return
                            }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { padOpen = true }
                            sticky = false
                        }
                        if closing { return }
                        let d = PadDirection.from(v.translation)
                        if d != active {
                            active = d
                            if let d {
                                UISelectionFeedbackGenerator().selectionChanged()
                                repeater.start { arrow(d) }
                            } else {
                                repeater.stop()
                            }
                        }
                    }
                    .onEnded { v in
                        repeater.stop()
                        let quick = Date().timeIntervalSince(pressStart ?? Date()) < 0.3 && hypot(v.translation.width, v.translation.height) < 10
                        pressStart = nil
                        active = nil
                        if closing {
                            closing = false
                            close()
                            return
                        }
                        if quick {
                            sticky = true
                        } else {
                            close()
                        }
                    }
            )
            .disabled(session == nil)
    }

    private var pad: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(Theme.chrome.opacity(0.75)))
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                .frame(width: 170, height: 170)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            ForEach(PadDirection.allCases, id: \.self) { d in
                padArrow(d)
                    .offset(d.offset)
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                session?.send("\r")
            } label: {
                Image(systemName: "return")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Theme.amber))
            }
            .buttonStyle(.plain)
        }
        .frame(width: 170, height: 170)
    }

    private func padArrow(_ d: PadDirection) -> some View {
        let on = active == d
        return Image(systemName: d.symbol)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(on ? Theme.onAccent : Theme.text)
            .frame(width: 50, height: 50)
            .background(Circle().fill(on ? Theme.amber : Theme.raised))
            .scaleEffect(on ? 1.12 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: on)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard sticky, active != d else { return }
                        active = d
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        repeater.start { arrow(d) }
                    }
                    .onEnded { _ in
                        guard sticky else { return }
                        repeater.stop()
                        active = nil
                    }
            )
    }

    private func close() {
        sticky = false
        withAnimation(.easeOut(duration: 0.15)) { padOpen = false }
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 20).padding(.horizontal, 2)
    }

    private func arrow(_ d: PadDirection) {
        guard let s = session else { return }
        s.send((s.applicationCursor ? "\u{1b}O" : "\u{1b}[") + d.code)
    }

    private func toggleKey(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(on ? Theme.onAccent : Theme.text)
                .frame(minWidth: 40, minHeight: 34)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.amber : Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.amber : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(session == nil)
    }

    private func key(_ label: String, amber: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(amber ? Theme.amber : Theme.text)
                .frame(minWidth: 40, minHeight: 34)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 8).fill(amber ? Theme.amberBg : Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(amber ? Theme.amberBorder : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(session == nil)
    }

    private func icon(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 40, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(session == nil)
    }
}
