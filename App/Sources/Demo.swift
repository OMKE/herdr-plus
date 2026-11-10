#if DEBUG
import Foundation
import UIKit
import HerdrKit

enum Demo {
    static let args = ProcessInfo.processInfo.arguments
    static var on: Bool { args.contains("-demo") }

    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static let layout = """
    {"spaces":[
     {"id":"web","name":"web-app","folder":"/Users/dev/code/web-app","color":"#e8a33d","tabs":[
      {"id":"auth","name":"auth refactor","root":{"id":"p1","type":"block","content":{"terminal":"t1"}}},
      {"id":"e2e","name":"e2e tests","root":{"id":"p2","type":"block","content":{"terminal":"t2"}}},
      {"id":"dev","name":"dev server","root":{"id":"p3","type":"block","content":{"terminal":"t3"}}}
     ]},
     {"id":"api","name":"api-server","folder":"/Users/dev/code/api-server","color":"#5aa9e6","tabs":[
      {"id":"rate","name":"rate limiter","root":{"id":"p4","type":"block","content":{"terminal":"t4"}}},
      {"id":"docs","name":"openapi docs","root":{"id":"p5","type":"block","content":{"terminal":"t5"}}},
      {"id":"sh","name":"shell","root":{"id":"p6","type":"block","content":{"terminal":"t6"}}}
     ]}
    ]}
    """

    static let remoteLayout = """
    {"spaces":[
     {"id":"infra","name":"infra","folder":"/home/dev/infra","color":"#7bc47f","tabs":[
      {"id":"deploy","name":"deploy staging","root":{"id":"p7","type":"block","content":{"terminal":"t1"}}}
     ]}
    ]}
    """

    static func terminal(_ address: String, _ argv: [String], _ cwd: String, _ state: String?, app: String?, title: String = "", msg: String? = nil, kind: String? = nil) -> Terminal {
        let status = state.map { Status(state: $0, kind: kind, app: app, title: title.isEmpty ? nil : title, msg: msg) }
        var t = Terminal(address: address, argv: argv, cwd: cwd, title: title, status: status)
        t.cols = 60
        t.rows = 40
        t.createdMs = UInt64((Date().timeIntervalSince1970 - 3600) * 1000)
        t.statusMs = UInt64((Date().timeIntervalSince1970 - 40) * 1000)
        return t
    }

    static var terminals: [Terminal] {
        [
            terminal("t1", ["claude"], "/Users/dev/code/web-app", "blocked", app: "claude", title: "auth refactor", msg: "Wants to run npm test", kind: "permission"),
            terminal("t2", ["codex"], "/Users/dev/code/web-app", "working", app: "codex", title: "e2e tests"),
            terminal("t3", ["npm", "run", "dev"], "/Users/dev/code/web-app", nil, app: nil, title: "dev server"),
            terminal("t4", ["claude"], "/Users/dev/code/api-server", "working", app: "claude", title: "rate limiter"),
            terminal("t5", ["opencode"], "/Users/dev/code/api-server", "done", app: "opencode", title: "openapi docs"),
            terminal("t6", ["zsh"], "/Users/dev/code/api-server", nil, app: nil, title: "shell"),
            terminal("devbox/t1", ["claude"], "/home/dev/infra", "done", app: "claude", title: "deploy staging"),
        ]
    }

    @MainActor
    static func load(_ model: AppModel) {
        var s = model.settings
        s.host = "macbook-pro"
        s.hostLabel = "MacBook Pro"
        s.username = "dev"
        s.fingerprint = "SHA256:demo"
        s.onboarded = true
        s.appearance = value("-demo-appearance").flatMap(Appearance.init(rawValue:)) ?? .dark
        model.settings = s
        model.store.reset(seq: 1, terminals: terminals)
        let local = LayoutDocument(value: parse(layout), version: 1).spaces
        let remote = LayoutDocument(value: parse(remoteLayout), version: 1, machine: "devbox").spaces
        model.spaces = local + remote
        model.terminalTabs = ["dev", "sh"]
        let tab = value("-demo-tab") ?? "rate"
        if let sp = model.spaces.first(where: { $0.tabs.contains { $0.id == tab } }) {
            model.selectedTab = TabRef(spaceUID: sp.uid, tabID: tab)
        }
        if args.contains("-demo-terminal") { model.setChat(false, tabID: tab) }
        if onboardingStep != nil {
            model.phase = .onboarding
            return
        }
        model.coreInfo = CoreInfo(id: "demo", name: "herdr-core", version: "0.1.19", generation: 1, features: [])
        model.latencyMs = 38
        model.phase = .connected
        if args.contains("-demo-drawer") { model.drawerOpen = true }
        if args.contains("-demo-overview") { model.showOverview = true }
    }

    static var onboardingStep: Int? { value("-demo-onboarding").flatMap(Int.init) }

    static let publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDemoKeyForScreenshotsOnly0000000000000000 herdr-ios"

    static let foundMacs = [
        FoundMac(name: "MacBook Pro", short: "macbook-pro", host: "macbook-pro.tail1234.ts.net", address: "100.101.12.34", viaTailscale: true),
        FoundMac(name: "Mac mini", short: "mac-mini", host: "mac-mini.local", address: "192.168.1.20", viaTailscale: false),
    ]

    static let checkLines: [(Bool, String)] = [
        (true, "Logged in as dev"),
        (true, "hc 0.1.19"),
        (true, "herdr-core 0.1.19: 6 terminals, machines: devbox"),
    ]

    static func parse(_ s: String) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8))) ?? .null
    }

    static func stamp(_ minutesAgo: Double) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date().addingTimeInterval(-minutesAgo * 60))
    }

    static func line(_ o: [String: Any]) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
        return String(decoding: d, as: UTF8.self)
    }

    static func user(_ text: String, _ ago: Double) -> String {
        line(["type": "user", "uuid": UUID().uuidString, "timestamp": stamp(ago), "message": ["role": "user", "content": text]])
    }

    static func say(_ text: String, _ ago: Double, id: String = UUID().uuidString) -> String {
        line(["type": "assistant", "uuid": UUID().uuidString, "timestamp": stamp(ago), "message": ["id": id, "role": "assistant", "model": "claude-opus-5-5", "content": [["type": "text", "text": text]]]])
    }

    static func tool(_ id: String, _ name: String, _ input: [String: Any], _ ago: Double) -> String {
        line(["type": "assistant", "uuid": UUID().uuidString, "timestamp": stamp(ago), "message": ["id": "m-\(id)", "role": "assistant", "model": "claude-opus-5-5", "content": [["type": "tool_use", "id": id, "name": name, "input": input]]]])
    }

    static func result(_ id: String, _ text: String, _ ago: Double) -> String {
        line(["type": "user", "uuid": UUID().uuidString, "timestamp": stamp(ago), "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "content": text]]]])
    }

    static func chatLines(_ address: String) -> [String] {
        switch address {
        case "t1":
            return [
                user("Move the session check out of each route into one auth middleware. Keep the cookie name.", 14),
                say("I'll look at how routes check the session today.", 13.8),
                tool("a1", "Grep", ["pattern": "getSession\\(", "path": "src/routes"], 13.7),
                result("a1", "src/routes/billing.ts\nsrc/routes/projects.ts\nsrc/routes/settings.ts\nsrc/routes/team.ts", 13.6),
                tool("a2", "Read", ["file_path": "src/routes/projects.ts"], 13.5),
                result("a2", "export async function GET(req) {\n  const s = await getSession(req)\n  if (!s) return unauthorized()\n  ...", 13.4),
                say("Four routes repeat the same check. I'll add `requireSession()` in `src/middleware/auth.ts` and remove the copies.", 12),
                tool("a3", "Write", ["file_path": "src/middleware/auth.ts", "content": "export function requireSession() {}"], 11),
                result("a3", "File created", 10.9),
                tool("a4", "Edit", ["file_path": "src/routes/projects.ts", "old_string": "const s = await getSession(req)", "new_string": ""], 10),
                result("a4", "ok", 9.9),
                tool("a5", "Edit", ["file_path": "src/routes/billing.ts", "old_string": "const s = await getSession(req)", "new_string": ""], 9.5),
                result("a5", "ok", 9.4),
                say("The middleware is in place and the four routes use it. Now I'd like to run the auth tests.", 1),
                tool("a6", "Bash", ["command": "npm test -- auth", "description": "Run the auth tests"], 0.8),
            ]
        case "devbox/t1":
            return [
                user("Deploy the staging stack with the new image tag and check health.", 30),
                tool("d1", "Bash", ["command": "./deploy.sh staging v2.14.0", "description": "Deploy staging"], 29),
                result("d1", "staging: 3/3 services healthy", 25),
                say("Staging runs **v2.14.0**. All three services pass their health checks.", 24),
            ]
        default:
            return [
                user("Add a rate limiter to the public API: 100 requests per minute per key, return 429 with Retry-After.", 9),
                say("I'll check how requests reach the handlers first.", 8.9),
                tool("r1", "Read", ["file_path": "src/server.ts"], 8.8),
                result("r1", "app.use(cors())\napp.use(json())\napp.use('/v1', router)", 8.7),
                tool("r2", "Grep", ["pattern": "apiKey", "path": "src"], 8.6),
                result("r2", "src/auth/keys.ts\nsrc/server.ts", 8.5),
                say("""
                Plan:

                1. A token bucket per API key, kept in Redis so it holds across instances.
                2. Middleware in front of `/v1` that answers **429** with `Retry-After`.
                3. Tests for the limit and the reset.
                """, 8.4),
                tool("r3", "Write", ["file_path": "src/middleware/rateLimit.ts", "content": "export const rateLimit = ..."], 7),
                result("r3", "File created", 6.9),
                tool("r4", "Edit", ["file_path": "src/server.ts", "old_string": "app.use('/v1', router)", "new_string": "app.use('/v1', rateLimit(), router)"], 6.5),
                result("r4", "ok", 6.4),
                say("""
                The limiter is wired in:

                ```ts
                app.use('/v1', rateLimit({ limit: 100, window: '1m' }), router)
                ```

                Over the limit, clients get `429` and `Retry-After: <seconds>`.
                """, 6),
                user("Nice. Also exempt the /v1/health endpoint.", 2),
                say("Good call, I'll skip `/v1/health` and add a test for it.", 1.8),
                tool("r5", "Edit", ["file_path": "src/middleware/rateLimit.ts", "old_string": "export const", "new_string": "const skip = ['/v1/health']"], 1.5),
                result("r5", "ok", 1.4),
                tool("r6", "Bash", ["command": "npm test -- rateLimit", "description": "Run the rate limit tests"], 0.4),
            ]
        }
    }

    static let approvalScreen = """
     ────────────────────────────────────────────
      Bash command

        npm test -- auth

      Do you want to proceed?
      ❯ 1. Yes
        2. Yes, and don't ask again for npm test commands
        3. No, and tell Claude what to do differently (esc)

     Esc to cancel
    """

    static func usage(_ address: String) -> AgentUsage {
        var u = AgentUsage()
        u.pid = address.hashValue & 0xffff
        u.account = address == "devbox/t1" ? "work@example.com" : "me@example.com"
        u.model = "claude-opus-5-5"
        u.contextPercent = address == "t1" ? 38 : 61
        u.contextTokens = address == "t1" ? 76_000 : 122_000
        u.contextSize = 200_000
        u.fiveHour = UsageLimit(percent: 42, resetsAt: Date().addingTimeInterval(2 * 3600 + 900))
        u.sevenDay = UsageLimit(percent: 18, resetsAt: Date().addingTimeInterval(4 * 86400))
        u.updated = Date()
        return u
    }

    static let terminalScreen: String = {
        let g = "\u{1b}[32m", d = "\u{1b}[2m", b = "\u{1b}[1m", c = "\u{1b}[36m", y = "\u{1b}[33m", m = "\u{1b}[35m", x = "\u{1b}[0m"
        let prompt = "\(c)api-server\(x) \(m)main\(x) \(g)❯\(x) "
        var s = ""
        s += "\(prompt)npm test\r\n\r\n"
        s += "\(d)> api-server@2.14.0 test\r\n> vitest run\(x)\r\n\r\n"
        s += " \(g)✓\(x) src/auth/keys.test.ts \(d)(12 tests)\(x)\r\n"
        s += " \(g)✓\(x) src/routes/projects.test.ts \(d)(8 tests)\(x)\r\n"
        s += " \(g)✓\(x) src/middleware/rateLimit.test.ts \(d)(6 tests)\(x)\r\n"
        s += " \(g)✓\(x) src/routes/health.test.ts \(d)(2 tests)\(x)\r\n"
        s += " \(y)↓\(x) src/legacy/v0.test.ts \(d)(3 skipped)\(x)\r\n\r\n"
        s += " \(b)Test Files\(x)  \(g)4 passed\(x) \(d)| 1 skipped\(x)\r\n"
        s += "      \(b)Tests\(x)  \(g)28 passed\(x) \(d)| 3 skipped\(x)\r\n"
        s += "   \(b)Duration\(x)  1.84s\r\n\r\n"
        s += "\(prompt)git status --short\r\n"
        s += " \(y)M\(x) src/server.ts\r\n"
        s += "\(g)??\(x) src/middleware/rateLimit.ts\r\n"
        s += "\(g)??\(x) src/middleware/rateLimit.test.ts\r\n\r\n"
        s += "\(prompt)git log --oneline -4\r\n"
        s += "\(y)3f9c2e1\(x) add token bucket limiter\r\n"
        s += "\(y)a71d0b4\(x) health endpoint skips auth\r\n"
        s += "\(y)9e04c7a\(x) move session check to middleware\r\n"
        s += "\(y)52b8f13\(x) bump vitest to 3.2\r\n\r\n"
        s += "\(prompt)redis-cli ping\r\n\(g)PONG\(x)\r\n\r\n"
        s += prompt
        return s
    }()

    static let devScreen: String = {
        let g = "\u{1b}[32m", d = "\u{1b}[2m", c = "\u{1b}[36m", b = "\u{1b}[1m", x = "\u{1b}[0m"
        var s = "\(b)\(g)  ▲ Next.js 15.4\(x)\r\n"
        s += "  - Local:   \(c)http://localhost:3000\(x)\r\n\r\n"
        s += " \(g)✓\(x) Ready in 1.2s\r\n"
        s += " \(d)○ Compiling /dashboard ...\(x)\r\n"
        s += " \(g)✓\(x) Compiled /dashboard in 640ms\r\n"
        s += " GET /dashboard \(g)200\(x) \(d)in 712ms\(x)\r\n"
        s += " GET /api/projects \(g)200\(x) \(d)in 38ms\(x)\r\n"
        return s
    }()

    static func screen(_ address: String) -> String {
        address == "t3" ? devScreen : terminalScreen
    }

    @MainActor
    static func fill(_ data: OverviewData, _ model: AppModel) {
        let usages = model.agents.filter { AgentKind.isClaude($0.terminal) }.map { usage($0.terminal.address) }
        data.accounts = UsageReader.accounts(usages)
        for e in model.agents {
            var info = data.infos[e.terminal.address] ?? AgentInfo()
            let folder = OverviewData.folder(e.terminal)
            info.repo = RepoInfo(top: folder, branch: e.terminal.address == "t1" ? "auth-middleware" : e.terminal.address == "t4" ? "rate-limit" : "main", worktree: nil, remote: nil)
            if AgentKind.isClaude(e.terminal) { info.usage = usage(e.terminal.address) }
            data.infos[e.terminal.address] = info
        }
        let iso = ISO8601DateFormatter()
        func pr(_ n: Int, _ title: String, _ head: String, _ add: Int, _ del: Int, _ ci: String, _ review: String, _ draft: Bool = false, _ ago: Double) -> [String: Any] {
            ["number": n, "title": title, "author": ["login": "dev"], "headRefName": head, "baseRefName": "main", "isDraft": draft, "additions": add, "deletions": del,
             "statusCheckRollup": [["status": ci == "pending" ? "IN_PROGRESS" : "COMPLETED", "conclusion": ci == "pending" ? "" : ci]],
             "reviewDecision": review, "url": "https://github.com/example/\(n)", "updatedAt": iso.string(from: Date().addingTimeInterval(-ago * 60))]
        }
        func list(_ items: [[String: Any]]) -> String {
            String(decoding: (try? JSONSerialization.data(withJSONObject: items)) ?? Data(), as: UTF8.self)
        }
        let web = PullRequest.parse(list([
            pr(412, "Auth middleware for all routes", "auth-middleware", 184, 97, "pending", "REVIEW_REQUIRED", false, 12),
            pr(408, "Dashboard: project activity chart", "activity-chart", 422, 31, "SUCCESS", "APPROVED", false, 180),
        ]), repo: "example/web-app")
        let api = PullRequest.parse(list([
            pr(97, "Rate limit the public API", "rate-limit", 236, 12, "SUCCESS", "REVIEW_REQUIRED", true, 6),
            pr(95, "OpenAPI 3.1 docs", "openapi-docs", 610, 88, "FAILURE", "CHANGES_REQUESTED", false, 300),
        ]), repo: "example/api-server")
        data.repos = [
            RepoPRs(repo: RepoInfo(top: "/Users/dev/code/web-app", branch: "main", worktree: nil, remote: "git@github.com:example/web-app.git"), machine: nil, prs: web, error: nil),
            RepoPRs(repo: RepoInfo(top: "/Users/dev/code/api-server", branch: "main", worktree: nil, remote: "git@github.com:example/api-server.git"), machine: nil, prs: api, error: nil),
        ]
        data.prsUpdated = Date()
        let web0 = model.spaces.first { $0.id == "web" }
        let api0 = model.spaces.first { $0.id == "api" }
        data.todos = [
            TodoItem(text: "Review the auth middleware PR before merging", spaceUID: web0?.uid, tabID: "auth", label: "auth refactor", program: "claude"),
            TodoItem(text: "Decide the rate limit for free keys", spaceUID: api0?.uid, tabID: "rate", label: "rate limiter", program: "claude"),
            TodoItem(text: "Rotate the staging Redis password"),
            TodoItem(text: "Write release notes for v2.14", done: true),
        ]
        data.todosLoaded = true
    }
}
#endif
