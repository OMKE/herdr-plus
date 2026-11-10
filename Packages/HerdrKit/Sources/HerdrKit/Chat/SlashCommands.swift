import Foundation

public struct SlashCommand: Sendable, Hashable, Identifiable {
    public enum Source: String, Sendable { case builtin, user, project, plugin, skill }
    public var id: String { name }
    public var name: String
    public var detail: String
    public var source: Source

    public init(name: String, detail: String, source: Source) {
        self.name = name
        self.detail = detail
        self.source = source
    }
}

public enum SlashCommands {
    public static let claude: [SlashCommand] = [
        ("clear", "Clear the conversation and start fresh"),
        ("compact", "Summarize the conversation to free context"),
        ("context", "Show what fills the context window"),
        ("usage", "Show plan usage and limits"),
        ("cost", "Show the session's cost and duration"),
        ("model", "Pick the model"),
        ("resume", "Resume an earlier conversation"),
        ("rewind", "Go back to an earlier point"),
        ("review", "Review a pull request"),
        ("security-review", "Security review of pending changes"),
        ("init", "Write a CLAUDE.md for this project"),
        ("memory", "Edit memory files"),
        ("permissions", "View or change tool permissions"),
        ("mcp", "Manage MCP servers"),
        ("agents", "Manage subagents"),
        ("hooks", "Manage hooks"),
        ("config", "Open settings"),
        ("status", "Show version, model and account"),
        ("todos", "Show the current todo list"),
        ("export", "Export the conversation"),
        ("add-dir", "Add a working directory"),
        ("help", "Show help"),
    ].map { SlashCommand(name: $0.0, detail: $0.1, source: .builtin) }

    public static let codex: [SlashCommand] = [
        ("new", "Start a new chat"),
        ("compact", "Summarize the conversation to free context"),
        ("model", "Pick the model and reasoning effort"),
        ("approvals", "Choose what Codex may do without asking"),
        ("review", "Review the current changes"),
        ("diff", "Show the git diff"),
        ("status", "Show session settings and token usage"),
        ("init", "Write an AGENTS.md for this project"),
        ("mention", "Mention a file"),
        ("mcp", "List MCP tools"),
        ("quit", "Exit Codex"),
    ].map { SlashCommand(name: $0.0, detail: $0.1, source: .builtin) }

    static let claudePanels: Set<String> = ["context", "usage", "cost", "model", "resume", "rewind", "memory", "permissions", "mcp", "agents", "hooks", "config", "settings", "status", "stats", "todos", "tasks", "export", "add-dir", "help", "doctor", "plugin", "plugins", "skills", "statusline", "theme", "output-style", "privacy-settings", "login", "logout", "ide", "bashes", "release-notes", "terminal-setup", "sandbox", "effort", "fast", "vim", "feedback", "bug", "upgrade", "workflows", "artifacts"]
    static let codexPanels: Set<String> = ["model", "approvals", "status", "diff", "mention", "mcp", "resume", "permissions"]

    public static func showsPanel(_ name: String, kind: AgentLog.Kind) -> Bool {
        let n = name.lowercased()
        return kind == .claude ? claudePanels.contains(n) : codexPanels.contains(n)
    }

    static let script = #"""
    d="$1"; cwd="$2"
    desc() { sed -n '1,30{s/^description:[[:space:]]*//p;}' "$1" 2>/dev/null | head -n 1 | tr -d '"' | cut -c1-140; }
    emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$(desc "$3")"; }
    for f in "$d"/commands/*.md "$d"/commands/*/*.md; do
      [ -f "$f" ] || continue
      r="${f#"$d"/commands/}"; r="${r%.md}"; emit user "$(printf '%s' "$r" | tr '/' ':')" "$f"
    done
    for f in "$d"/skills/*/SKILL.md; do [ -f "$f" ] && emit skill "$(basename "$(dirname "$f")")" "$f"; done
    if [ -n "$cwd" ]; then
      for f in "$cwd"/.claude/commands/*.md; do [ -f "$f" ] && emit project "$(basename "$f" .md)" "$f"; done
      for f in "$cwd"/.claude/skills/*/SKILL.md; do [ -f "$f" ] && emit project "$(basename "$(dirname "$f")")" "$f"; done
    fi
    for f in "$d"/plugins/cache/*/*/*/commands/*.md "$d"/plugins/cache/*/*/*/skills/*/SKILL.md; do
      [ -f "$f" ] || continue
      case "$f" in
        */commands/*) p="${f%/commands/*}"; n="$(basename "$f" .md)";;
        *) p="${f%/skills/*}"; n="$(basename "$(dirname "$f")")";;
      esac
      p="$(basename "$(dirname "$p")")"
      emit plugin "$p:$n" "$f"
    done
    """#

    public static func load(kind: AgentLog.Kind, configDir: String?, cwd: String?, via core: CoreConnection, on machine: String?) async -> [SlashCommand] {
        let base = kind == .claude ? claude : codex
        guard kind == .claude, let configDir else { return base }
        guard let r = try? await core.shell(script, [configDir, cwd ?? ""], on: machine, timeout: .seconds(15)) else { return base }
        var seen = Set(base.map(\.name))
        var extra: [SlashCommand] = []
        for line in r.text.split(separator: "\n") {
            let f = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 2, !f[1].isEmpty, seen.insert(f[1]).inserted else { continue }
            let src = SlashCommand.Source(rawValue: f[0]) ?? .user
            extra.append(SlashCommand(name: f[1], detail: f.count > 2 ? f[2] : "", source: src))
        }
        return base + extra.sorted { $0.name < $1.name }
    }

    public static func matches(_ query: String, in all: [SlashCommand], limit: Int = 8) -> [SlashCommand] {
        let q = query.lowercased()
        if q.isEmpty { return Array(all.prefix(limit)) }
        let prefix = all.filter { $0.name.lowercased().hasPrefix(q) || $0.name.lowercased().split(separator: ":").last?.hasPrefix(q) == true }
        let rest = all.filter { c in !prefix.contains(c) && c.name.lowercased().contains(q) }
        return Array((prefix + rest).prefix(limit))
    }
}
