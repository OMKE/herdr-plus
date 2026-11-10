import Foundation
import HerdrSSH

enum BarStyle: String, Codable, CaseIterable, Identifiable {
    case floating, docked
    var id: String { rawValue }
    var label: String { self == .floating ? "Floating" : "Docked" }
}

struct AppSettings: Codable, Equatable {
    var host = ""
    var port = 22
    var username = ""
    var command = SSHTarget.defaultCommand
    var fingerprint = ""
    var hostLabel = ""
    var ntfyServer = "https://ntfy.sh"
    var ntfyTopic = ""
    var onboarded = false
    var fontSize: Double = 12
    var appearance: Appearance = .dark
    var darkTheme = Palette.herdr.id
    var lightTheme = Palette.herdrLight.id
    var terminalFont: TermFont = .sfMono
    var chatFont: ChatFont = .system
    var chatSize: Double = 15
    var termKeys: [ToolKey] = ToolKey.defaultTerminal
    var chatKeys: [ToolKey] = ToolKey.defaultChat
    var toolbarGlass = true
    var toolbarLabels: ToolLabels = .text
    var speechLocale = ""
    var speechOnDevice = true
    var speechAutoSend = false
    var hideBarWithKeyboard = true
    var optionAsMeta = true
    var auth: SSHAuthMode = .key
    var topBar: BarStyle = .floating
    var bottomBar: BarStyle = .floating

    var target: SSHTarget { SSHTarget(host: host, port: port, username: username, command: command, auth: auth) }
    var isComplete: Bool { onboarded && !host.isEmpty && !username.isEmpty && !fingerprint.isEmpty }
    var displayHost: String { hostLabel.isEmpty ? host : hostLabel }

    static let key = "settings.v1"

    static func load() -> AppSettings {
        guard let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(AppSettings.self, from: d) else {
            var s = AppSettings()
            s.ntfyTopic = randomTopic()
            return s
        }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    static func randomTopic() -> String {
        let chars = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return "herdr-" + String((0..<18).map { _ in chars.randomElement()! })
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        command = try c.decodeIfPresent(String.self, forKey: .command) ?? SSHTarget.defaultCommand
        fingerprint = try c.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
        auth = (try? c.decodeIfPresent(SSHAuthMode.self, forKey: .auth)) ?? .key
        hostLabel = try c.decodeIfPresent(String.self, forKey: .hostLabel) ?? ""
        ntfyServer = try c.decodeIfPresent(String.self, forKey: .ntfyServer) ?? "https://ntfy.sh"
        ntfyTopic = try c.decodeIfPresent(String.self, forKey: .ntfyTopic) ?? AppSettings.randomTopic()
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 12
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .dark
        darkTheme = try c.decodeIfPresent(String.self, forKey: .darkTheme) ?? Palette.herdr.id
        lightTheme = try c.decodeIfPresent(String.self, forKey: .lightTheme) ?? Palette.herdrLight.id
        terminalFont = (try? c.decodeIfPresent(TermFont.self, forKey: .terminalFont)) ?? .sfMono
        chatFont = (try? c.decodeIfPresent(ChatFont.self, forKey: .chatFont)) ?? .system
        chatSize = try c.decodeIfPresent(Double.self, forKey: .chatSize) ?? 15
        termKeys = ((try? c.decodeIfPresent([ToolKey?].self, forKey: .termKeys)) ?? nil)?.compactMap { $0 } ?? ToolKey.defaultTerminal
        chatKeys = ((try? c.decodeIfPresent([ToolKey?].self, forKey: .chatKeys)) ?? nil)?.compactMap { $0 } ?? ToolKey.defaultChat
        toolbarGlass = try c.decodeIfPresent(Bool.self, forKey: .toolbarGlass) ?? true
        toolbarLabels = (try? c.decodeIfPresent(ToolLabels.self, forKey: .toolbarLabels)) ?? .text
        speechLocale = try c.decodeIfPresent(String.self, forKey: .speechLocale) ?? ""
        speechOnDevice = try c.decodeIfPresent(Bool.self, forKey: .speechOnDevice) ?? true
        speechAutoSend = try c.decodeIfPresent(Bool.self, forKey: .speechAutoSend) ?? false
        hideBarWithKeyboard = try c.decodeIfPresent(Bool.self, forKey: .hideBarWithKeyboard) ?? true
        optionAsMeta = try c.decodeIfPresent(Bool.self, forKey: .optionAsMeta) ?? true
        topBar = (try? c.decodeIfPresent(BarStyle.self, forKey: .topBar)) ?? .floating
        bottomBar = (try? c.decodeIfPresent(BarStyle.self, forKey: .bottomBar)) ?? .floating
    }
}
