import Foundation
import HerdrKit

struct AgentInfo: Equatable {
    var repo: RepoInfo?
    var usage: AgentUsage?
}

struct RepoPRs: Identifiable, Equatable {
    var repo: RepoInfo
    var machine: String?
    var prs: [PullRequest]
    var error: String?
    var id: String { (machine ?? "") + ":" + repo.top }
}

@MainActor
@Observable
final class OverviewData {
    var infos: [String: AgentInfo] = [:]
    var accounts: [AccountUsage] = []
    var repos: [RepoPRs] = []
    var prsLoading = false
    var prsUpdated: Date?
    var todos: [TodoItem] = []
    var todosLoaded = false
    var todoError: String?
    var agentsLoading = false

    @ObservationIgnored private var repoCache: [String: RepoInfo?] = [:]

    static func folder(_ t: Terminal) -> String {
        if let c = t.foreground?.cwd, !c.isEmpty { return c }
        return t.cwd
    }

    private func repo(_ dir: String, machine: String?, via c: CoreConnection) async -> RepoInfo? {
        let key = (machine ?? "") + ":" + dir
        if let hit = repoCache[key] { return hit }
        let r = try? await Git.repo(at: dir, via: c, on: machine)
        repoCache[key] = r
        return r
    }

    func refreshAgents(_ model: AppModel) async {
        guard let c = model.connection, !agentsLoading else { return }
        agentsLoading = true
        defer { agentsLoading = false }
        repoCache.removeAll()
        let agents = model.agents
        var usageByMachine: [String: [AgentUsage]] = [:]
        let machines = Set(agents.map { $0.terminal.machine ?? "" })
        for m in machines {
            if let all = try? await UsageReader.all(via: c, on: m.isEmpty ? nil : m) { usageByMachine[m] = all }
        }
        accounts = UsageReader.accounts(usageByMachine.values.flatMap { $0 })
        for e in agents {
            let t = e.terminal
            var info = infos[t.address] ?? AgentInfo()
            let dir = Self.folder(t)
            if !dir.isEmpty { info.repo = await repo(dir, machine: t.machine, via: c) }
            if AgentKind.isClaude(t), let log = try? await Locator.locate(t, via: c), let pid = log.pid {
                info.usage = usageByMachine[t.machine ?? ""]?.first { $0.pid == pid }
            }
            infos[t.address] = info
        }
    }

    func refreshPRs(_ model: AppModel) async {
        guard let c = model.connection, !prsLoading else { return }
        prsLoading = true
        defer { prsLoading = false }
        var dirs: [(String, String?)] = []
        var seen = Set<String>()
        for s in model.spaces {
            var candidates = [s.folder]
            for t in s.tabs { for l in t.terminals { if let term = model.terminal(l, in: s) { candidates.append(Self.folder(term)) } } }
            for d in candidates where !d.isEmpty && seen.insert((s.machine ?? "") + ":" + d).inserted { dirs.append((d, s.machine)) }
        }
        var withGit = Set<String>()
        for m in Set(dirs.map { $0.1 ?? "" }) {
            let list = dirs.filter { ($0.1 ?? "") == m }.map(\.0)
            if let r = try? await c.shell(#"for d in "$@"; do [ -e "$d/.git" ] && printf '%s\n' "$d"; done; exit 0"#, list, on: m.isEmpty ? nil : m, timeout: .seconds(10)) {
                for d in r.text.split(separator: "\n") { withGit.insert(m + ":" + d) }
            }
        }
        var tops: [String: (RepoInfo, String?)] = [:]
        for (d, m) in dirs where withGit.contains((m ?? "") + ":" + d) {
            if let r = await repo(d, machine: m, via: c), let remote = r.remote, RepoInfo.slug(remote) != nil { tops[(m ?? "") + ":" + r.top] = (r, m) }
        }
        var out: [RepoPRs] = []
        for (_, (r, m)) in tops.sorted(by: { $0.key < $1.key }) {
            do {
                let prs = try await Git.pulls(repo: r, via: c, on: m)
                out.append(RepoPRs(repo: r, machine: m, prs: prs))
            } catch {
                let msg = AppModel.describe(error)
                if msg.contains("no git remotes") || msg.contains("known GitHub host") { continue }
                out.append(RepoPRs(repo: r, machine: m, prs: [], error: msg))
            }
        }
        var byName: [String: RepoPRs] = [:]
        var order: [String] = []
        for r in out {
            let k = r.repo.name
            if byName[k] == nil { order.append(k); byName[k] = r } else if byName[k]!.prs.isEmpty, !r.prs.isEmpty { byName[k] = r }
        }
        repos = order.compactMap { byName[$0] }
        prsUpdated = Date()
    }

    func sessionBranches(_ model: AppModel) -> [String: AgentEntry] {
        var out: [String: AgentEntry] = [:]
        for e in model.agents { if let b = infos[e.terminal.address]?.repo?.branch { out[b] = e } }
        return out
    }

    func loadTodos(_ model: AppModel) async {
        guard let c = model.connection else { return }
        do {
            todos = try await c.todos().items
            todosLoaded = true
            todoError = nil
        } catch {
            todoError = AppModel.describe(error)
        }
    }

    func editTodos(_ model: AppModel, _ f: @escaping ([TodoItem]) -> [TodoItem]) {
        todos = f(todos)
        guard let c = model.connection else { todoError = "Not connected"; return }
        Task {
            do {
                todos = try await c.editTodos(f)
                todoError = nil
            } catch {
                todoError = "Couldn't save: " + AppModel.describe(error)
            }
        }
    }
}

enum AgentKind {
    static func isClaude(_ t: Terminal) -> Bool { Locator.agentKind(t) == .claude }
}
