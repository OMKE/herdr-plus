import Foundation

public struct RepoInfo: Sendable, Hashable {
    public var top: String
    public var branch: String
    public var worktree: String?
    public var remote: String?

    public init(top: String, branch: String, worktree: String?, remote: String?) {
        self.top = top
        self.branch = branch
        self.worktree = worktree
        self.remote = remote
    }

    public var name: String {
        if let remote, let slug = RepoInfo.slug(remote) { return slug }
        return (top as NSString).lastPathComponent
    }

    public static func slug(_ url: String) -> String? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if let r = s.range(of: "github.com[:/]", options: .regularExpression) {
            return String(s[r.upperBound...])
        }
        return nil
    }

    static func parse(_ text: String) -> RepoInfo? {
        let l = text.components(separatedBy: "\n")
        guard l.count >= 4, !l[0].isEmpty else { return nil }
        let gitDir = l[2], common = l[3]
        let isWorktree = !common.isEmpty && (gitDir as NSString).standardizingPath != (common as NSString).standardizingPath && gitDir.contains("/worktrees/")
        return RepoInfo(
            top: l[0],
            branch: l[1],
            worktree: isWorktree ? (l[0] as NSString).lastPathComponent : nil,
            remote: l.count > 4 && !l[4].isEmpty ? l[4] : nil
        )
    }
}

public struct PullRequest: Sendable, Hashable, Identifiable {
    public enum CI: String, Sendable { case passing, failing, pending, none }
    public enum Review: String, Sendable { case approved, changes, required, none }

    public var repo: String
    public var number: Int
    public var title: String
    public var author: String
    public var head: String
    public var base: String
    public var draft: Bool
    public var additions: Int
    public var deletions: Int
    public var ci: CI
    public var review: Review
    public var url: String
    public var updated: Date?

    public var id: String { repo + "#\(number)" }

    static func ci(_ rollup: [JSONValue]) -> CI {
        if rollup.isEmpty { return .none }
        var pending = false
        for c in rollup {
            let concl = (c["conclusion"]?.string ?? c["state"]?.string ?? "").uppercased()
            let status = (c["status"]?.string ?? "").uppercased()
            if ["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"].contains(concl) { return .failing }
            if ["IN_PROGRESS", "QUEUED", "PENDING", "WAITING", "REQUESTED"].contains(status) || concl == "PENDING" || (concl.isEmpty && status != "COMPLETED") { pending = true }
        }
        return pending ? .pending : .passing
    }

    public static func parse(_ text: String, repo: String) -> [PullRequest] {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)), let arr = json.array else { return [] }
        let iso = ISO8601DateFormatter()
        return arr.compactMap { v in
            guard let n = v["number"]?.int else { return nil }
            let review: Review = switch v["reviewDecision"]?.string ?? "" {
            case "APPROVED": .approved
            case "CHANGES_REQUESTED": .changes
            case "REVIEW_REQUIRED": .required
            default: .none
            }
            return PullRequest(
                repo: repo,
                number: n,
                title: v["title"]?.string ?? "",
                author: v["author"]?["login"]?.string ?? "",
                head: v["headRefName"]?.string ?? "",
                base: v["baseRefName"]?.string ?? "",
                draft: v["isDraft"]?.bool ?? false,
                additions: v["additions"]?.int ?? 0,
                deletions: v["deletions"]?.int ?? 0,
                ci: ci(v["statusCheckRollup"]?.array ?? []),
                review: review,
                url: v["url"]?.string ?? "",
                updated: v["updatedAt"]?.string.flatMap { iso.date(from: $0) }
            )
        }
    }
}

public struct FileEntry: Sendable, Hashable, Identifiable {
    public var name: String
    public var isDir: Bool
    public var size: Int
    public var modified: Date?
    public var git: String?
    public var id: String { name }

    public var ext: String { (name as NSString).pathExtension.lowercased() }
}

public struct DiffLine: Sendable, Hashable {
    public enum Kind: Sendable { case context, add, del, meta }
    public var kind: Kind
    public var old: Int?
    public var new: Int?
    public var text: String
}

public struct DiffHunk: Sendable, Hashable {
    public var header: String
    public var lines: [DiffLine]
}

public struct DiffFile: Sendable, Hashable, Identifiable {
    public var path: String
    public var oldPath: String?
    public var status: String
    public var hunks: [DiffHunk]
    public var binary: Bool
    public var id: String { path }
    public var additions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .add }.count } }
    public var deletions: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .del }.count } }
}

public enum Git {
    static let path = "PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin\"; export PATH; "

    static let repoScript = path + """
    cd "$1" 2>/dev/null || exit 1
    top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1
    echo "$top"
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo
    cd "$top"
    git rev-parse --absolute-git-dir 2>/dev/null || echo
    c=$(git rev-parse --git-common-dir 2>/dev/null); case "$c" in /*) echo "$c";; *) echo "$top/$c";; esac
    git remote get-url origin 2>/dev/null || echo
    """

    static let prScript = path + """
    cd "$1" || exit 1
    command -v gh >/dev/null 2>&1 || { echo "gh-missing" >&2; exit 3; }
    gh pr list --state open --limit 40 --json number,title,author,headRefName,baseRefName,isDraft,additions,deletions,reviewDecision,statusCheckRollup,url,updatedAt
    """

    static let listScript = path + """
    cd "$1" || exit 1
    for f in .* *; do
      [ "$f" = "." ] || [ "$f" = ".." ] || [ "$f" = ".git" ] && continue
      [ -e "$f" ] || [ -L "$f" ] || continue
      if [ -d "$f" ]; then t=d; else t=f; fi
      s=$(stat -f '%z|%m' "$f" 2>/dev/null || stat -c '%s|%Y' "$f" 2>/dev/null)
      printf '%s|%s|%s\\n' "$t" "$s" "$f"
    done
    echo "--git--"
    git status --porcelain=v1 --untracked-files=normal -- . 2>/dev/null
    echo "--prefix--"
    git rev-parse --show-prefix 2>/dev/null
    exit 0
    """

    static let readScript = """
    f="$1"; [ -f "$f" ] || exit 1
    head -c 400000 "$f"
    """

    static let diffScript = path + """
    cd "$1" || exit 1
    git -c core.quotepath=off diff HEAD --no-color --no-ext-diff -M -U3 2>/dev/null || git -c core.quotepath=off diff --no-color --no-ext-diff -U3
    git -c core.quotepath=off ls-files --others --exclude-standard | head -50 | while IFS= read -r f; do
      git diff --no-color --no-index -- /dev/null "$f" 2>/dev/null | head -400
    done
    """

    public static func repo(at dir: String, via c: CoreConnection, on machine: String?) async throws -> RepoInfo? {
        let r = try await c.shell(repoScript, [dir], on: machine)
        guard r.code == 0 else { return nil }
        return RepoInfo.parse(r.text.trimmingCharacters(in: .newlines))
    }

    public static func pulls(repo: RepoInfo, via c: CoreConnection, on machine: String?) async throws -> [PullRequest] {
        let r = try await c.shell(prScript, [repo.top], on: machine, timeout: .seconds(30))
        if r.code == 3 { throw GitError.ghMissing }
        guard r.code == 0 else { throw GitError.failed(String(decoding: r.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
        return PullRequest.parse(r.text, repo: repo.name)
    }

    public static func list(_ dir: String, via c: CoreConnection, on machine: String?) async throws -> [FileEntry] {
        let r = try await c.shell(listScript, [dir], on: machine)
        guard r.code == 0 else { throw GitError.failed("Can't open \(dir)") }
        return parseList(r.text)
    }

    static func parseList(_ text: String) -> [FileEntry] {
        let parts = text.components(separatedBy: "--git--\n")
        var entries: [FileEntry] = []
        for line in parts[0].split(separator: "\n") {
            let f = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            guard f.count == 4 else { continue }
            entries.append(FileEntry(name: String(f[3]), isDir: f[0] == "d", size: Int(f[1]) ?? 0, modified: Double(f[2]).map { Date(timeIntervalSince1970: $0) }, git: nil))
        }
        if parts.count > 1 {
            let rest = parts[1].components(separatedBy: "--prefix--\n")
            let prefix = rest.count > 1 ? rest[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            var marks: [String: String] = [:]
            for line in rest[0].split(separator: "\n") where line.count > 3 {
                let code = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
                var p = String(line.dropFirst(3))
                if let arrow = p.range(of: " -> ") { p = String(p[arrow.upperBound...]) }
                p = p.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard p.hasPrefix(prefix) else { continue }
                let rel = String(p.dropFirst(prefix.count))
                let first = rel.split(separator: "/").first.map(String.init) ?? rel
                let letter = code == "??" ? "?" : String(code.first ?? "M")
                if marks[first] == nil || rel == first { marks[first] = rel == first ? letter : "M" }
            }
            for i in entries.indices { entries[i].git = marks[entries[i].name] }
        }
        return entries.sorted { a, b in a.isDir != b.isDir ? a.isDir : a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }

    public static func read(_ path: String, via c: CoreConnection, on machine: String?) async throws -> Data {
        let r = try await c.shell(readScript, [path], on: machine)
        guard r.code == 0 else { throw GitError.failed("Can't read the file") }
        return r.stdout
    }

    public static func diff(_ dir: String, via c: CoreConnection, on machine: String?) async throws -> [DiffFile] {
        let r = try await c.shell(diffScript, [dir], on: machine, timeout: .seconds(30))
        return parseDiff(r.text)
    }

    public static func parseDiff(_ text: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var cur: DiffFile?
        var hunk: DiffHunk?
        var old = 0, new = 0
        func flushHunk() { if let h = hunk { cur?.hunks.append(h) }; hunk = nil }
        func flushFile() { flushHunk(); if let f = cur { files.append(f) }; cur = nil }
        for raw in text.components(separatedBy: "\n") {
            let line = raw
            if line.hasPrefix("diff --git ") {
                flushFile()
                let rest = line.dropFirst("diff --git ".count)
                var path = String(rest)
                if let r = rest.range(of: " b/") { path = String(rest[r.upperBound...]) }
                cur = DiffFile(path: path, oldPath: nil, status: "M", hunks: [], binary: false)
                continue
            }
            guard cur != nil else { continue }
            if hunk == nil || line.hasPrefix("@@") {
                if line.hasPrefix("new file") { cur?.status = "A"; continue }
                if line.hasPrefix("deleted file") { cur?.status = "D"; continue }
                if line.hasPrefix("rename from ") { cur?.oldPath = String(line.dropFirst(12)); cur?.status = "R"; continue }
                if line.hasPrefix("rename to ") { cur?.path = String(line.dropFirst(10)); continue }
                if line.hasPrefix("Binary files") { cur?.binary = true; continue }
                if line.hasPrefix("+++ ") {
                    let p = String(line.dropFirst(4))
                    if p.hasPrefix("b/") { cur?.path = String(p.dropFirst(2)) }
                    continue
                }
                if line.hasPrefix("--- ") || line.hasPrefix("index ") || line.hasPrefix("similarity") || line.hasPrefix("old mode") || line.hasPrefix("new mode") { continue }
                if line.hasPrefix("@@") {
                    flushHunk()
                    let nums = line.split(separator: " ")
                    if nums.count >= 3 {
                        old = Int(nums[1].dropFirst().split(separator: ",").first ?? "0") ?? 0
                        new = Int(nums[2].dropFirst().split(separator: ",").first ?? "0") ?? 0
                    }
                    hunk = DiffHunk(header: line, lines: [])
                    continue
                }
                continue
            }
            switch line.first {
            case "+": hunk?.lines.append(DiffLine(kind: .add, old: nil, new: new, text: String(line.dropFirst()))); new += 1
            case "-": hunk?.lines.append(DiffLine(kind: .del, old: old, new: nil, text: String(line.dropFirst()))); old += 1
            case " ": hunk?.lines.append(DiffLine(kind: .context, old: old, new: new, text: String(line.dropFirst()))); old += 1; new += 1
            case "\\": hunk?.lines.append(DiffLine(kind: .meta, old: nil, new: nil, text: line))
            default: break
            }
        }
        flushFile()
        return files
    }
}

public enum GitError: Error, CustomStringConvertible {
    case ghMissing
    case failed(String)

    public var description: String {
        switch self {
        case .ghMissing: "GitHub CLI (gh) isn't installed on that machine."
        case .failed(let s): s.isEmpty ? "Command failed" : s
        }
    }
}
