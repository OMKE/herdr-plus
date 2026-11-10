import Foundation
import HerdrKit

let home = FileManager.default.homeDirectoryForCurrentUser.path
let configDir = home + "/.config/herdr-notify"
let configPath = configDir + "/config.json"
let label = "io.github.herdr-ios.notify"

func stamp(_ s: String) {
    let f = ISO8601DateFormatter()
    FileHandle.standardError.write(Data("\(f.string(from: Date())) \(s)\n".utf8))
}

func loadConfig() -> NotifyConfig {
    guard let data = FileManager.default.contents(atPath: configPath) else {
        stamp("missing \(configPath). Create it with: herdr-notify init <topic>")
        exit(2)
    }
    do {
        return try JSONDecoder().decode(NotifyConfig.self, from: data)
    } catch {
        stamp("bad config: \(error)")
        exit(2)
    }
}

func hcPath(_ config: NotifyConfig) -> String {
    if let hc = config.hc { return (hc as NSString).expandingTildeInPath }
    return home + "/.local/bin/hc"
}

func runLoop() async -> Never {
    let config = loadConfig()
    var backoff: Double = 1
    while true {
        do {
            let transport = try ProcessTransport(executable: hcPath(config), arguments: ["connect"])
            let connection = CoreConnection(transport: transport)
            let engine = NotifyEngine(config: config, log: stamp) { n in
                do { try await Ntfy.post(n, config: config) } catch { stamp("ntfy failed: \(error)") }
            }
            backoff = 1
            try await engine.run(connection: connection)
        } catch {
            stamp("connection ended: \(error)")
        }
        try? await Task.sleep(for: .seconds(backoff))
        backoff = min(backoff * 2, 30)
    }
}

func test() async {
    let config = loadConfig()
    let n = AgentNotification(
        title: "Claude Code · herdr-ios",
        body: "Test from herdr-notify. Tap to open the app.",
        click: "herdr-ios://open",
        priority: 4,
        tags: ["hourglass"]
    )
    do {
        try await Ntfy.post(n, config: config)
        print("sent to \(config.server)/\(config.topic)")
    } catch {
        print("failed: \(error)")
        exit(1)
    }
}

func initConfig(topic: String, server: String) throws {
    try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: configPath) {
        print("\(configPath) already exists, leaving it as is")
        return
    }
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(NotifyConfig(server: server, topic: topic)).write(to: URL(fileURLWithPath: configPath))
    print("wrote \(configPath)")
}

func install() throws {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.resolvingSymlinksInPath().path
    let target = home + "/.local/bin/herdr-notify"
    if exe != target {
        try FileManager.default.createDirectory(atPath: home + "/.local/bin", withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: target) { try FileManager.default.removeItem(atPath: target) }
        try FileManager.default.copyItem(atPath: exe, toPath: target)
    }
    let plist: [String: Any] = [
        "Label": label,
        "ProgramArguments": [target, "run"],
        "RunAtLoad": true,
        "KeepAlive": true,
        "StandardErrorPath": home + "/Library/Logs/herdr-notify.log",
        "StandardOutPath": home + "/Library/Logs/herdr-notify.log",
        "EnvironmentVariables": ["PATH": home + "/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"],
    ]
    let path = home + "/Library/LaunchAgents/\(label).plist"
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
    print("start it with: launchctl bootstrap gui/$(id -u) \(path)")
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "run":
    await runLoop()
case "test":
    await test()
case "init":
    guard args.count >= 2 else { print("usage: herdr-notify init <topic> [server]"); exit(2) }
    try initConfig(topic: args[1], server: args.count > 2 ? args[2] : "https://ntfy.sh")
case "install":
    try install()
default:
    print("""
    herdr-notify: push a notification to your phone when an agent waits.

      herdr-notify init <topic> [server]   write ~/.config/herdr-notify/config.json
      herdr-notify test                    send a test notification
      herdr-notify run                     watch herdr-core and notify
      herdr-notify install                 copy to ~/.local/bin and write a LaunchAgent
    """)
}
