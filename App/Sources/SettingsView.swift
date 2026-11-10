import SwiftUI
import HerdrKit
import HerdrSSH

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var publicKey = ""
    @State private var keyError: String?
    @State private var confirmReset = false
    @State private var confirmNewKey = false
    @State private var copied: String?

    var body: some View {
        NavigationStack {
            SettingsPage(title: "Settings") {
                hero
                SettingsHeader("App")
                appRows
                SettingsHeader("Security")
                security
                SettingsHeader("Notifications")
                notifications
                SettingsHeader("Danger zone")
                danger
                footer
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Set up again?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Disconnect and set up again", role: .destructive) {
                    dismiss()
                    model.resetOnboarding()
                }
            } message: {
                Text("Your SSH key stays. You'll pick the Mac and trust its host key again.")
            }
            .confirmationDialog("Make a new SSH key?", isPresented: $confirmNewKey, titleVisibility: .visible) {
                Button("Replace key", role: .destructive) {
                    do {
                        publicKey = KeyStore.openSSHPublicKey(try KeyStore.reset())
                        keyError = nil
                    } catch {
                        keyError = "Couldn't make a new key: \(AppModel.describe(error))"
                    }
                }
            } message: {
                Text("The old key stops working. You'll need to add the new public key to ~/.ssh/authorized_keys on your Mac.")
            }
        }
        .tint(Theme.amber)
        .preferredColorScheme(model.colorSchemeOverride)
        .onAppear {
            do {
                publicKey = KeyStore.openSSHPublicKey(try KeyStore.loadOrCreate())
                keyError = nil
            } catch {
                keyError = "Couldn't read the SSH key from the Keychain: \(AppModel.describe(error))"
            }
        }
        .task { await model.measureLatency() }
    }

    private var connected: Bool { model.phase == .connected }

    private var statusLabel: (String, Color) {
        switch model.phase {
        case .connected: ("Connected", Theme.green)
        case .connecting: ("Connecting", Theme.amber)
        case .reconnecting: ("Reconnecting", Theme.amber)
        case .failed: ("Offline", Theme.red)
        case .onboarding: ("Not set up", Theme.muted)
        }
    }

    private var hero: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.raised))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.settings.displayHost)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text("\(model.settings.username)@\(model.settings.host)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 6)
                    let s = statusLabel
                    HStack(spacing: 5) {
                        Circle().fill(s.1).frame(width: 6, height: 6)
                        Text(s.0).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(s.1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(s.1.opacity(0.14)))
                    .overlay(Capsule().stroke(s.1.opacity(0.3), lineWidth: 0.75))
                }
                HStack(spacing: 8) {
                    stat("Login", model.settings.auth == .tailscale ? "Tailscale" : "SSH key")
                    stat("herdr-core", model.coreInfo?.version ?? "—")
                    stat("Latency", connected ? (model.latencyMs.map { "\($0) ms" } ?? "…") : "—")
                }
            }
            .padding(14)
            if !model.machines.isEmpty {
                SettingsDivider(inset: 0)
                ForEach(Array(model.machines.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { SettingsDivider() }
                    machineRow(m, first: i == 0)
                }
            }
            SettingsDivider(inset: 0)
            HStack(spacing: 8) {
                SettingsPill(title: "Reconnect", icon: "arrow.clockwise") {
                    model.disconnect()
                    model.connect()
                    dismiss()
                }
                Spacer()
            }
            .padding(12)
            SettingsDivider(inset: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text("Host key").font(.system(size: 11)).foregroundStyle(Theme.dim)
                Text(model.settings.fingerprint)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
    }

    private func machineRow(_ m: Machine, first: Bool) -> some View {
        HStack(spacing: 10) {
            if m.isConnected {
                Circle().fill(Theme.green).frame(width: 7, height: 7)
            } else {
                Circle().stroke(Theme.dim, lineWidth: 1.2).frame(width: 7, height: 7)
            }
            Text(m.name).font(.system(size: 15)).foregroundStyle(m.isConnected ? Theme.text : Theme.muted)
            Text(machineDetail(m, first: first)).font(.system(size: 12)).foregroundStyle(Theme.dim).lineLimit(1)
            Spacer()
            if first {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.amber)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
    }

    private func machineDetail(_ m: Machine, first: Bool) -> String {
        var parts: [String] = []
        if first { parts.append("this core") } else if !m.host.isEmpty { parts.append(m.host) }
        if !m.isConnected { parts.append(m.state ?? "offline") }
        if m.temporary { parts.append("temporary") }
        return parts.joined(separator: " · ")
    }

    private var appRows: some View {
        let s = model.settings
        let palette = ThemeStore.shared.palette
        return SettingsCard {
            NavigationLink { AppearanceSettingsView() } label: {
                SettingsRow(title: "Appearance", value: "\(s.appearance.label) · \(palette.name)", icon: "circle.lefthalf.filled", tint: Theme.blue)
            }
            SettingsDivider(inset: 54)
            NavigationLink { FontSettingsView() } label: {
                SettingsRow(title: "Fonts & Size", value: "\(s.terminalFont.label) · \(Int(s.fontSize))", icon: "textformat", tint: Color(hex: "#b48ead"))
            }
            SettingsDivider(inset: 54)
            NavigationLink { ToolbarSettingsView() } label: {
                SettingsRow(title: "Toolbar", value: "\(s.termKeys.count) keys", icon: "keyboard.badge.ellipsis", tint: Theme.amber)
            }
            SettingsDivider(inset: 54)
            NavigationLink { SpeechSettingsView() } label: {
                SettingsRow(title: "Speech", value: speechValue, icon: "waveform", tint: Theme.green)
            }
            SettingsDivider(inset: 54)
            NavigationLink { KeyboardSettingsView() } label: {
                SettingsRow(title: "Hardware Keyboard", value: s.hideBarWithKeyboard ? "On" : "Off", icon: "command", tint: Color(hex: "#56b6c2"))
            }
            SettingsDivider(inset: 54)
            NavigationLink { AppIconSettingsView() } label: {
                SettingsRow(title: "App Icon", value: AppIconSettingsView.currentName, icon: "app.badge", tint: Theme.red)
            }
        }
        .buttonStyle(.plain)
    }

    private var speechValue: String {
        let id = model.settings.speechLocale
        if id.isEmpty { return "Phone language" }
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }

    private var keyType: String {
        publicKey.split(separator: " ").first.map { String($0).replacingOccurrences(of: "ssh-", with: "") } ?? ""
    }

    private var security: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("This phone's SSH key").font(.system(size: 16)).foregroundStyle(Theme.text)
                    Spacer()
                    Text(keyType).font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
                HStack(spacing: 10) {
                    Text(publicKey)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    SettingsPill(title: copied == "key" ? "Copied" : "Copy") { copy(publicKey, "key") }
                }
                if let keyError {
                    Text(keyError).font(.system(size: 13)).foregroundStyle(Theme.amber)
                }
                if model.settings.auth == .tailscale {
                    Text("You log in with Tailscale SSH, so the Mac doesn't need this key.")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
            }
            .padding(14)
            SettingsDivider(inset: 0)
            Button { confirmNewKey = true } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Make a new key").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.red)
                    Text("Your Macs will stop accepting this phone until you add the new key.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var macCommands: String {
        "herdr-notify init \(model.settings.ntfyTopic)\nherdr-notify test\nherdr-notify install"
    }

    private var notifications: some View {
        SettingsCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ntfy topic").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Text(model.settings.ntfyTopic)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 4)
                SettingsPill(title: copied == "topic" ? "Copied" : "Copy topic") { copy(model.settings.ntfyTopic, "topic") }
            }
            .padding(14)
            SettingsDivider(inset: 0)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Mac commands").font(.system(size: 16)).foregroundStyle(Theme.text)
                    Spacer()
                    SettingsPill(title: copied == "cmds" ? "Copied" : "Copy all") { copy(macCommands, "cmds") }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(macCommands.split(separator: "\n").map(String.init), id: \.self) { line in
                        Text("$ \(line)").lineLimit(1).truncationMode(.tail)
                    }
                }
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.chromeDeep))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
                Text("Subscribe to this topic in the ntfy app. herdr-notify on your Mac posts to it when an agent waits.")
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }

    private var danger: some View {
        Button { confirmReset = true } label: {
            SettingsCard(danger: true) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Set up again").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.red)
                        Text("Forgets \(model.settings.displayHost) on this phone. Nothing changes on your Mac.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.red)
                }
                .padding(14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return Text("Herdr iOS \(v) (\(b)) · Apache-2.0\nNot affiliated with the Herdr maintainers.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.dim)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }

    private func copy(_ text: String, _ tag: String) {
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copied = tag
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == tag { copied = nil }
        }
    }
}
