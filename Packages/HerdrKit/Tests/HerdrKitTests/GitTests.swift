import Foundation
import Testing
@testable import HerdrKit

private let sampleDiff = """
diff --git a/src/a.swift b/src/a.swift
index 111..222 100644
--- a/src/a.swift
+++ b/src/a.swift
@@ -1,4 +1,5 @@ struct A {
 let x = 1
-let y = 2
+let y = 3
+let z = 4
 let w = 5
--- not a header
diff --git a/new.txt b/new.txt
new file mode 100644
--- /dev/null
+++ b/new.txt
@@ -0,0 +1,2 @@
+hello
+world
\\ No newline at end of file
diff --git a/img.png b/img.png
Binary files a/img.png and b/img.png differ
"""

@Test func diffParses() {
    let files = Git.parseDiff(sampleDiff)
    #expect(files.map(\.path) == ["src/a.swift", "new.txt", "img.png"])
    #expect(files[0].additions == 2 && files[0].deletions == 2)
    let lines = files[0].hunks[0].lines
    #expect(lines[1].kind == .del && lines[1].old == 2)
    #expect(lines[2].kind == .add && lines[2].new == 2)
    #expect(lines[4].old == 3 && lines[4].new == 4)
    #expect(files[1].status == "A" && files[1].additions == 2)
    #expect(files[2].binary)
}

@Test func listParsesWithGitMarks() {
    let text = "d|96|1700000000|src\nf|12|1700000000|README.md\nf|3|1700000000|new.txt\nf|1|1|.env\n--git--\n M sub/src/x.swift\n?? sub/new.txt\n M other/y\n--prefix--\nsub/\n"
    let e = Git.parseList(text)
    #expect(e.map(\.name) == ["src", ".env", "new.txt", "README.md"])
    #expect(e.first { $0.name == "src" }?.git == "M")
    #expect(e.first { $0.name == "new.txt" }?.git == "?")
    #expect(e.first { $0.name == "README.md" }?.git == nil)
}

@Test func prParses() {
    let json = """
    [{"number":12,"title":"Fix nav","author":{"login":"omke"},"headRefName":"fix/nav","baseRefName":"main","isDraft":false,"additions":10,"deletions":2,"reviewDecision":"APPROVED","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}],"url":"u","updatedAt":"2026-11-10T10:00:00Z"},
     {"number":13,"title":"WIP","author":{"login":"x"},"headRefName":"w","baseRefName":"main","isDraft":true,"additions":1,"deletions":0,"reviewDecision":"","statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":""},{"status":"COMPLETED","conclusion":"FAILURE"}],"url":"u2","updatedAt":"2026-11-10T10:00:00Z"}]
    """
    let prs = PullRequest.parse(json, repo: "o/r")
    #expect(prs.count == 2)
    #expect(prs[0].ci == .passing && prs[0].review == .approved && prs[0].updated != nil)
    #expect(prs[1].ci == .failing && prs[1].draft)
    #expect(PullRequest.ci([["status": "QUEUED"]]) == .pending)
}

@Test func repoSlug() {
    #expect(RepoInfo.slug("git@github.com:OMKE/flockbook.git") == "OMKE/flockbook")
    #expect(RepoInfo.slug("https://github.com/a/b") == "a/b")
    #expect(RepoInfo.slug("https://gitlab.com/a/b") == nil)
}

@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: hc)), .timeLimit(.minutes(1)))
func gitAgainstIsolatedCore() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hk-git-\(UUID().uuidString)").path
    let wt = dir + "-wt"
    let setup = """
    set -e; mkdir -p "$1/src"; cd "$1"; git init -q -b main; git config user.email t@t; git config user.name t
    printf 'a\\nb\\n' > src/x.txt; echo hi > README.md; git add .; git commit -qm init
    printf 'a\\nB\\nc\\n' > src/x.txt; echo n > new.txt
    git worktree add -q "$2" -b feature
    """
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", setup, "sh", dir, wt]
    try p.run()
    p.waitUntilExit()
    #expect(p.terminationStatus == 0)
    defer { try? FileManager.default.removeItem(atPath: dir); try? FileManager.default.removeItem(atPath: wt) }

    let transport = try ProcessTransport(executable: hc, arguments: ["connect"], environment: isolatedEnv())
    let c = CoreConnection(transport: transport)
    _ = try await c.start()
    defer { Task { await c.close() } }

    let info = try #require(try await Git.repo(at: dir + "/src", via: c, on: nil))
    #expect(info.branch == "main")
    #expect(info.worktree == nil)
    let wi = try #require(try await Git.repo(at: wt, via: c, on: nil))
    #expect(wi.branch == "feature")
    #expect(wi.worktree == (wt as NSString).lastPathComponent)
    #expect(try await Git.repo(at: "/", via: c, on: nil) == nil)

    let files = try await Git.list(dir, via: c, on: nil)
    #expect(files.map(\.name) == ["src", "new.txt", "README.md"])
    #expect(files.first { $0.name == "src" }?.git == "M")
    #expect(files.first { $0.name == "new.txt" }?.git == "?")
    let sub = try await Git.list(dir + "/src", via: c, on: nil)
    #expect(sub.first?.git == "M")

    let data = try await Git.read(dir + "/README.md", via: c, on: nil)
    #expect(String(decoding: data, as: UTF8.self) == "hi\n")

    let diff = try await Git.diff(dir, via: c, on: nil)
    #expect(diff.map(\.path).sorted() == ["new.txt", "src/x.txt"])
    #expect(diff.first { $0.path == "src/x.txt" }?.additions == 2)
    #expect(diff.first { $0.path == "new.txt" }?.status == "A")
}
