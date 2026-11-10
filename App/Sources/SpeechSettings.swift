import SwiftUI

struct MicLevel: View {
    let level: Float
    var bars = 5
    var color: Color = Theme.amber

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<bars, id: \.self) { i in
                let mid = Float(bars - 1) / 2
                let w = 1 - abs(Float(i) - mid) / (mid + 1)
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: CGFloat(4 + 16 * min(1, level * (0.5 + w))))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }
}

struct SpeechSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var dictation = Dictation.shared

    var body: some View {
        @Bindable var model = model
        SettingsPage(title: "Speech") {
            SettingsCard {
                Menu {
                    Picker("Language", selection: $model.settings.speechLocale) {
                        Text("Phone language").tag("")
                        ForEach(Dictation.languages, id: \.identifier) { l in
                            Text(Locale.current.localizedString(forIdentifier: l.identifier) ?? l.identifier).tag(l.identifier)
                        }
                    }
                } label: {
                    SettingsRow(title: "Language", value: languageLabel)
                }
                .buttonStyle(.plain)
                SettingsDivider()
                SettingsToggle(title: "On-device only", subtitle: "Speech never leaves this iPhone. Fewer languages.", isOn: $model.settings.speechOnDevice)
                SettingsDivider()
                SettingsToggle(title: "Send when I stop", subtitle: "Sends the message when you stop dictating. Off: review before sending.", isOn: $model.settings.speechAutoSend)
            }
            SettingsHeader("Try it")
            SettingsCard {
                VStack(spacing: 14) {
                    Text(transcript)
                        .font(.system(size: 16))
                        .foregroundStyle(dictation.text.isEmpty ? Theme.muted : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.raised))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
                    MicLevel(level: dictation.listening ? dictation.level : 0, bars: 15)
                        .frame(height: 22)
                        .opacity(dictation.listening ? 1 : 0.35)
                    Button(action: toggle) {
                        Image(systemName: dictation.listening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(Theme.amber))
                            .overlay(Circle().stroke(Theme.amber.opacity(0.35), lineWidth: 6).padding(-6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictation.listening ? "Stop" : "Start dictation")
                    Text(statusLine)
                        .font(.system(size: 12))
                        .foregroundStyle(failed ? Theme.amber : Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
            }
            SettingsFootnote("Uses Apple's speech engine. Whisper models are planned.")
        }
        .onDisappear { dictation.cancel() }
    }

    private var failed: Bool {
        if case .failed = dictation.state { return true }
        return false
    }

    private var languageLabel: String {
        let id = model.settings.speechLocale
        return id.isEmpty ? "Phone language" : (Locale.current.localizedString(forIdentifier: id) ?? id)
    }

    private var transcript: String {
        if !dictation.text.isEmpty { return dictation.text }
        return dictation.listening ? "Listening…" : "Tap the mic and say something"
    }

    private var statusLine: String {
        if case .failed(let msg) = dictation.state { return msg }
        let where_ = model.settings.speechOnDevice ? "on-device" : "Apple servers allowed"
        return dictation.listening ? "Listening · \(where_) · tap to stop" : "Tap to start · \(where_)"
    }

    private func toggle() {
        if dictation.listening {
            dictation.stop()
        } else {
            Task { await dictation.start(locale: model.settings.speechLocale, onDevice: model.settings.speechOnDevice) }
        }
    }
}

struct KeyboardSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsPage(title: "Hardware Keyboard") {
            SettingsHeader("Hardware keyboard", trailing: HardwareKeyboard.shared.connected ? "Connected" : "Not connected")
            SettingsCard {
                SettingsToggle(title: "Hide toolbar with a keyboard", subtitle: "The key strip comes back when you disconnect it.", isOn: $model.settings.hideBarWithKeyboard)
                SettingsDivider()
                SettingsToggle(title: "Option as Meta", subtitle: "Sends ⌥ as Esc-prefix for shell and Emacs keys. Off: Option types special characters.", isOn: $model.settings.optionAsMeta)
            }
            SettingsHeader("Shortcuts")
            SettingsCard {
                ForEach(Array(HardwareShortcuts.all.enumerated()), id: \.offset) { i, s in
                    if i > 0 { SettingsDivider() }
                    HStack(spacing: 12) {
                        Text(s.keys)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .frame(minWidth: 44)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 4)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.raised))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
                        Text(s.title).font(.system(size: 15)).foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                }
            }
        }
    }
}

enum HardwareShortcuts {
    static let all: [(title: String, keys: String)] = [
        ("Switch to tab 1–9", "⌘1…9"),
        ("Chat ⇄ terminal", "⌘J"),
        ("Dictation", "⌘⇧M"),
        ("Spaces", "⌘B"),
        ("Overview", "⌘O"),
        ("Send message", "⌘⏎"),
        ("Interrupt agent", "⌘."),
        ("Shortcut list", "⌘K"),
    ]
}
