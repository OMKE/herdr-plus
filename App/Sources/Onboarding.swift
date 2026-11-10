import SwiftUI
import Network
import HerdrKit
import HerdrSSH

enum PortCheck {
    static func reachable(host: String, port: Int, timeout: Double = 5) async -> Bool {
        guard let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        return await withCheckedContinuation { cont in
            let done = OnceFlag()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if done.set() { conn.cancel(); cont.resume(returning: true) }
                case .failed, .cancelled:
                    if done.set() { conn.cancel(); cont.resume(returning: false) }
                case .waiting:
                    if done.set() { conn.cancel(); cont.resume(returning: false) }
                default:
                    break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if done.set() { conn.cancel(); cont.resume(returning: false) }
            }
        }
    }
}

final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func set() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable { case welcome, find, key, trust, check, notify }

    @Environment(AppModel.self) private var model
    @State private var step: Step = .welcome
    @State private var draft = AppSettings()
    @State private var reach: Bool?
    @State private var checkingReach = false
    @State private var publicKey = ""
    @State private var keyError: String?
    @State private var fingerprint: String?
    @State private var trustError: String?
    @State private var fetchingFingerprint = false
    @State private var checkLines: [(Bool, String)] = []
    @State private var checking = false
    @State private var checkPassed = false
    @State private var discovery = MacDiscovery()

    var body: some View {
        VStack(spacing: 0) {
            progress
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case .welcome: welcome
                    case .find: find
                    case .key: keyStep
                    case .trust: trust
                    case .check: check
                    case .notify: notify
                    }
                }
                .padding(22)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(Theme.terminal.ignoresSafeArea())
        .onAppear {
            draft = model.settings
            if draft.ntfyTopic.isEmpty { draft.ntfyTopic = AppSettings.randomTopic() }
            #if DEBUG
            if let s = Demo.onboardingStep {
                draft.ntfyTopic = "herdr-7f3k2qx9"
                draft.host = Demo.foundMacs[0].host
                publicKey = Demo.publicKey
                fingerprint = "SHA256:q3Vt8mX0aKdLr2pE7nYcJwF5sH1uZgB9oTiR4vMkN6c"
                checkLines = Demo.checkLines
                checkPassed = true
                reach = true
                step = Step(rawValue: s) ?? .welcome
                return
            }
            #endif
            loadKey()
        }
    }

    private func loadKey() {
        do {
            publicKey = KeyStore.openSSHPublicKey(try KeyStore.loadOrCreate())
            keyError = nil
        } catch {
            publicKey = ""
            keyError = "Couldn't create the SSH key in the Keychain: \(AppModel.describe(error))"
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Theme.amber : Theme.raised)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
            Text(sub).font(.system(size: 15)).foregroundStyle(Theme.muted)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image("prog-claude")
                .resizable()
                .frame(width: 56, height: 56)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.raised))
                .padding(.top, 30)
            title("Your agents, in your pocket", "Herdr on iOS connects to herdr-core on your Mac over Tailscale and SSH. You see the same spaces, tabs and agents, and you can answer an agent that waits for you.")
            bullet("lock.shield", "Everything stays between this phone and your Mac. No server in the middle.")
            bullet("bell.badge", "Get a notification when an agent needs you, and tap it to land in that terminal.")
            bullet("network", "You need Tailscale on this phone and on your Mac, and Remote Login turned on on the Mac.")
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.amber).frame(width: 22)
            Text(text).font(.system(size: 14.5)).foregroundStyle(Theme.text.opacity(0.9))
        }
    }

    private var find: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Find your Mac", "Pick your Mac below, or type its Tailscale name or address.")
            discoveryCard
            authCard
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("Host")
                    TextField("mac-studio or 100.x.y.z", text: $draft.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .modifier(FieldStyle())
                        .onChange(of: draft.host) { _, _ in reach = nil }
                    label("Mac username")
                    TextField("your short name (run whoami)", text: $draft.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .modifier(FieldStyle())
                        .accessibilityIdentifier("username-field")
                    if draft.username.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Run whoami in Terminal on the Mac. It prints the name to use here.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    }
                    label("Name to show (optional)")
                    TextField("mac-studio", text: $draft.hostLabel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .modifier(FieldStyle())
                    HStack(spacing: 8) {
                        Button {
                            Task { await checkReach() }
                        } label: {
                            if checkingReach { ProgressView().tint(Theme.onAccent) } else { Text("Check port 22") }
                        }
                        .buttonStyle(PillButton(secondary: true))
                        .disabled(draft.host.isEmpty || checkingReach)
                        if let reach {
                            Label(reach ? "Reachable" : "Not reachable", systemImage: reach ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(reach ? Theme.green : Theme.red)
                        }
                    }
                    if reach == false {
                        Text("Turn on Tailscale on this phone, and on the Mac turn on System Settings → General → Sharing → Remote Login.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private var discoveryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    label("Macs nearby")
                    if discovery.searching { ProgressView().controlSize(.mini) }
                    Spacer()
                    Button("Search again") { discovery.start() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.amber)
                        .disabled(discovery.searching)
                }
                HStack(spacing: 6) {
                    Circle().fill(discovery.tailnetIP == nil ? Theme.red : Theme.green).frame(width: 6, height: 6)
                    Text(discovery.tailnetIP.map { "Tailscale is on · this phone is \($0)" } ?? "Tailscale looks off on this phone")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    if discovery.tailnetIP == nil, let u = URL(string: "tailscale://") {
                        Spacer()
                        Button("Open Tailscale") { UIApplication.shared.open(u) }
                            .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.amber)
                    }
                }
                ForEach(discovery.found) { mac in
                    Button { pick(mac) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "desktopcomputer").foregroundStyle(Theme.muted).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mac.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                Text(([mac.host] + [mac.address].compactMap { $0 }.filter { $0 != mac.host }).joined(separator: " · "))
                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(mac.viaTailscale ? "Tailscale" : "Local network")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(mac.viaTailscale ? Theme.green : Theme.muted)
                            if draft.host == mac.host { Image(systemName: "checkmark").foregroundStyle(Theme.amber) }
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("found-mac")
                }
                if discovery.found.isEmpty, !discovery.searching {
                    Text(discovery.denied
                         ? "Allow Local Network for Herdr in Settings → Privacy & Security to find your Mac."
                         : "No Mac found on this Wi-Fi. Search only works when the phone and Mac are on the same network; over Tailscale alone, type the Mac's name below.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
            }
        }
        .onAppear {
            #if DEBUG
            if Demo.on {
                discovery.found = Demo.foundMacs
                discovery.tailnetIP = "100.88.4.12"
                return
            }
            #endif
            if discovery.found.isEmpty { discovery.start() }
        }
        .onDisappear { discovery.stop() }
    }

    private var authCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                label("How to log in")
                Picker("Login", selection: $draft.auth) {
                    Text("SSH key").tag(SSHAuthMode.key)
                    Text("Tailscale SSH").tag(SSHAuthMode.tailscale)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("auth-mode")
                Text(draft.auth == .key
                     ? "Works with any Mac or Linux machine running sshd (Remote Login on a Mac). You add this phone's key once."
                     : "No key to copy. The Mac must have Tailscale SSH turned on, and your tailnet policy must allow this phone to log in.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func pick(_ mac: FoundMac) {
        UISelectionFeedbackGenerator().selectionChanged()
        draft.host = mac.host
        if draft.hostLabel.trimmingCharacters(in: .whitespaces).isEmpty { draft.hostLabel = mac.short.isEmpty ? mac.host : mac.short }
        reach = nil
        Task { await checkReach() }
    }

    @ViewBuilder private var keyStep: some View {
        if draft.auth == .tailscale { tailscaleStep } else { sshKeyStep }
    }

    private var tailscaleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Turn on Tailscale SSH", "Tailscale checks who you are, so this phone needs no key on the Mac.")
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("1. On the Mac")
                    Text("tailscale set --ssh")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.terminal))
                    Button("Copy command") { UIPasteboard.general.string = "tailscale set --ssh" }
                        .buttonStyle(PillButton(secondary: true))
                    Text("On macOS this needs the open-source tailscaled (for example from Homebrew). The App Store and standalone Tailscale apps may not offer Tailscale SSH server.")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    label("2. In the Tailscale admin console → Access controls")
                    Text(tailscaleACL)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.terminal))
                    Button("Copy rule") { UIPasteboard.general.string = tailscaleACL }
                        .buttonStyle(PillButton(secondary: true))
                    Text("Use \"accept\". With \"check\", Tailscale asks you to log in again in a browser from time to time, and the app can't do that.")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    Text("Prefer a key after all? Go back and pick SSH key.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var tailscaleACL: String {
        let user = draft.username.trimmingCharacters(in: .whitespaces)
        return """
        "ssh": [{
          "action": "accept",
          "src":    ["autogroup:member"],
          "dst":    ["autogroup:self"],
          "users":  ["\(user.isEmpty ? "autogroup:nonroot" : user)"]
        }]
        """
    }

    private var sshKeyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Let this phone in", "This app made its own SSH key. Add its public key to your Mac once.")
            if let keyError {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(keyError).font(.system(size: 13)).foregroundStyle(Theme.amber)
                        Button("Try again") { loadKey() }.buttonStyle(PillButton())
                    }
                }
            }
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("Run this on your Mac")
                    Text(authorizeCommand)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.terminal))
                    HStack {
                        Button("Copy command") { UIPasteboard.general.string = authorizeCommand }
                            .buttonStyle(PillButton())
                        Button("Copy key only") { UIPasteboard.general.string = publicKey }
                            .buttonStyle(PillButton(secondary: true))
                    }
                    .disabled(publicKey.isEmpty)
                    Text("Tip: send it to your Mac with Universal Clipboard or AirDrop, then paste it in Terminal.")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var authorizeCommand: String {
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '\(publicKey)' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    }

    private var trust: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Trust your Mac", "Check that this fingerprint matches your Mac. The app will refuse to connect if it ever changes.")
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label(draft.displayHost)
                    if fetchingFingerprint {
                        ProgressView().tint(Theme.muted)
                    } else if let fingerprint {
                        Text(fingerprint)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Theme.amber)
                            .textSelection(.enabled)
                    }
                    if let trustError {
                        Text(trustError).font(.system(size: 13)).foregroundStyle(Theme.red)
                        Button("Try again") { Task { await fetchFingerprint() } }.buttonStyle(PillButton(secondary: true))
                    }
                    if draft.auth == .key {
                        label("Compare on the Mac with")
                        Text("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                    } else {
                        Text("Tailscale SSH uses its own host key, not the one from Remote Login, so this fingerprint differs from ssh-keygen on the Mac.")
                            .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    }
                }
            }
        }
        .task { if fingerprint == nil { await fetchFingerprint() } }
    }

    private var check: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Checking", "Logging in and talking to herdr-core.")
            card {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(checkLines.enumerated()), id: \.offset) { _, l in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: l.0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(l.0 ? Theme.green : Theme.red)
                            Text(l.1).font(.system(size: 13.5)).foregroundStyle(Theme.text).textSelection(.enabled)
                        }
                    }
                    if checking { ProgressView().tint(Theme.muted) }
                    if !checking && !checkPassed {
                        Button("Run again") { Task { await runCheck() } }.buttonStyle(PillButton(secondary: true))
                    }
                    label("hc command")
                    TextField(SSHTarget.defaultCommand, text: $draft.command)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 13, design: .monospaced))
                        .modifier(FieldStyle())
                }
            }
        }
        .task { if checkLines.isEmpty { await runCheck() } }
    }

    private var notify: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Notifications", "herdr-notify runs on your Mac and pushes to the ntfy app when an agent waits. Tapping the notification opens that terminal here.")
            card {
                VStack(alignment: .leading, spacing: 10) {
                    label("1. Install ntfy from the App Store and subscribe to this topic")
                    HStack {
                        Text(draft.ntfyTopic)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Theme.amber)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy") { UIPasteboard.general.string = draft.ntfyTopic }.buttonStyle(PillButton(secondary: true))
                    }
                    label("2. On your Mac")
                    Text(notifyCommands)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.terminal))
                    Button("Copy commands") { UIPasteboard.general.string = notifyCommands }.buttonStyle(PillButton())
                    Text("Anyone who knows the topic can read these notifications. Keep it secret, or use your own ntfy server.")
                        .font(.system(size: 12)).foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var notifyCommands: String {
        "herdr-notify init \(draft.ntfyTopic)\nherdr-notify test\nherdr-notify install"
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .welcome } }
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button(step == .notify ? "Done" : "Continue") { next() }
                .buttonStyle(PillButton())
                .disabled(!canContinue)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Theme.chrome)
    }

    private var canContinue: Bool {
        switch step {
        case .welcome: true
        case .find: !draft.host.trimmingCharacters(in: .whitespaces).isEmpty && !draft.username.trimmingCharacters(in: .whitespaces).isEmpty
        case .key: draft.auth == .tailscale || !publicKey.isEmpty
        case .trust: fingerprint != nil
        case .check: checkPassed
        case .notify: true
        }
    }

    private func next() {
        switch step {
        case .find:
            draft.host = draft.host.trimmingCharacters(in: .whitespaces)
            draft.username = draft.username.trimmingCharacters(in: .whitespaces)
            if draft.hostLabel.isEmpty { draft.hostLabel = draft.host.split(separator: ".").first.map(String.init) ?? draft.host }
            if draft.host != model.settings.host || draft.auth != model.settings.auth { fingerprint = nil }
        case .trust:
            draft.fingerprint = fingerprint ?? ""
            checkLines = []
            checkPassed = false
        case .notify:
            model.finishOnboarding(draft)
            return
        default:
            break
        }
        withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .notify }
    }

    private func checkReach() async {
        checkingReach = true
        reach = await PortCheck.reachable(host: draft.host.trimmingCharacters(in: .whitespaces), port: draft.port)
        checkingReach = false
    }

    private func fetchFingerprint() async {
        fetchingFingerprint = true
        trustError = nil
        defer { fetchingFingerprint = false }
        do {
            let key = try KeyStore.loadOrCreate()
            fingerprint = try await SSHProbe.hostFingerprint(host: draft.host, port: draft.port, username: draft.username, key: key)
        } catch {
            trustError = AppModel.describe(error)
        }
    }

    private func runCheck() async {
        checking = true
        checkLines = []
        checkPassed = false
        defer { checking = false }
        let key: Curve25519Key
        do { key = try KeyStore.loadOrCreate() } catch {
            checkLines.append((false, "Keychain: \(error)"))
            return
        }
        let hcBinary = draft.command.split(separator: " ").first.map(String.init) ?? "hc"
        do {
            let out = try await SSHProbe.run(draft.target, fingerprint: draft.fingerprint, key: key, command: "\(hcBinary) --version 2>&1 || echo HC_MISSING")
            if out.contains("HC_MISSING") || out.contains("not found") {
                checkLines.append((true, "Logged in as \(draft.username)"))
                checkLines.append((false, "hc not found at \(hcBinary). Install herdr on the Mac or change the command below, then run again."))
                return
            }
            checkLines.append((true, "Logged in as \(draft.username)"))
            checkLines.append((true, "hc " + out.trimmingCharacters(in: .whitespacesAndNewlines)))
        } catch {
            checkLines.append((false, AppModel.describe(error)))
            return
        }
        do {
            let t = try await SSHTransport.connect(draft.target, fingerprint: draft.fingerprint, key: key)
            let c = CoreConnection(transport: t)
            let info = try await c.start()
            let ts = try await c.terminals()
            let ms = (try? await c.machines()) ?? []
            await c.close()
            checkLines.append((true, "herdr-core \(info.version): \(ts.count) terminals" + (ms.isEmpty ? "" : ", machines: " + ms.map(\.name).joined(separator: ", "))))
            checkPassed = true
        } catch {
            checkLines.append((false, "herdr-core: " + AppModel.describe(error)))
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.chrome))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.muted)
    }
}

struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.text)
            .tint(Theme.amber)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }
}

struct PillButton: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(secondary ? Theme.text : Theme.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(secondary ? Theme.raised : Theme.amber))
            .overlay(Capsule().stroke(secondary ? Theme.border : .clear))
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
