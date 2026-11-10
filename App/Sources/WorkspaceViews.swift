import SwiftUI
import HerdrKit

struct WorkspaceTarget: Identifiable, Hashable {
    enum Mode: Hashable { case files, diff }
    var folder: String
    var machine: String?
    var title: String
    var mode: Mode
    var id: String { (machine ?? "") + ":" + folder + ":" + (mode == .files ? "f" : "d") }
}

struct WorkspaceMenuButton: View {
    @Environment(AppModel.self) private var model
    let terminal: Terminal?
    var fallbackFolder: String = ""
    var machine: String?
    var size: CGFloat = 30
    var filled = false

    var body: some View {
        Menu {
            Button { open(.files) } label: { Label("Files", systemImage: "folder") }
            Button { open(.diff) } label: { Label("Changes", systemImage: "plusminus") }
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(filled ? Theme.text : Theme.muted)
                .frame(width: size, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(filled ? Theme.raised : .clear))
        }
        .disabled(folder.isEmpty)
        .accessibilityLabel("Files and changes")
        .accessibilityIdentifier("workspace-menu")
    }

    private var folder: String {
        if let t = terminal { let f = OverviewData.folder(t); if !f.isEmpty { return f } }
        return fallbackFolder
    }

    private func open(_ mode: WorkspaceTarget.Mode) {
        model.workspace = WorkspaceTarget(folder: folder, machine: terminal?.machine ?? machine, title: (folder as NSString).lastPathComponent, mode: mode)
    }
}

@MainActor
enum FileGlyph {
    static func symbol(_ e: FileEntry) -> String {
        if e.isDir { return "folder.fill" }
        switch e.ext {
        case "swift", "ts", "tsx", "js", "jsx", "rs", "go", "py", "rb", "kt", "java", "c", "h", "cpp", "m", "php", "sh", "zsh": return "chevron.left.forwardslash.chevron.right"
        case "md", "txt", "rst": return "doc.text"
        case "json", "yml", "yaml", "toml", "plist", "xml", "lock": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "ico": return "photo"
        case "css", "scss", "html": return "paintbrush"
        default: return "doc"
        }
    }

    static func tint(_ e: FileEntry) -> Color {
        if e.isDir { return Theme.blue }
        switch e.ext {
        case "swift", "rs": return Color(hex: "#f0883e")
        case "ts", "tsx": return Color(hex: "#3b82f6")
        case "js", "jsx", "json": return Color(hex: "#eab308")
        case "py": return Color(hex: "#60a5fa")
        case "md", "txt": return Theme.muted
        default: return Theme.dim
        }
    }

    static func gitColor(_ g: String) -> Color {
        switch g {
        case "A", "?": return Theme.green
        case "D": return Theme.red
        default: return Theme.amber
        }
    }
}

struct WorkspaceSheet: View {
    let target: WorkspaceTarget
    @State private var mode: WorkspaceTarget.Mode

    init(target: WorkspaceTarget) {
        self.target = target
        _mode = State(initialValue: target.mode)
    }

    var body: some View {
        NavigationStack {
            Group {
                if mode == .files {
                    FolderView(root: target.folder, path: target.folder, machine: target.machine)
                } else {
                    DiffReviewView(folder: target.folder, machine: target.machine)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        Text("Files").tag(WorkspaceTarget.Mode.files)
                        Text("Changes").tag(WorkspaceTarget.Mode.diff)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
        }
    }
}

struct FolderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let root: String
    let path: String
    let machine: String?
    @State private var entries: [FileEntry] = []
    @State private var error: String?
    @State private var loading = true
    @State private var showHidden = false

    private var crumbs: [(String, String)] {
        let rootName = (root as NSString).lastPathComponent
        var out = [(rootName, root)]
        guard path.hasPrefix(root), path != root else { return out }
        var cur = root
        for part in path.dropFirst(root.count).split(separator: "/") {
            cur += "/" + part
            out.append((String(part), cur))
        }
        return out
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(crumbs.enumerated()), id: \.offset) { i, c in
                            if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim) }
                            Text(c.0)
                                .font(.system(size: 12, weight: i == crumbs.count - 1 ? .semibold : .regular, design: .monospaced))
                                .foregroundStyle(i == crumbs.count - 1 ? Theme.text : Theme.muted)
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            if let error {
                Text(error).foregroundStyle(Theme.red).font(.system(size: 13))
            }
            Section {
                ForEach(visible) { e in
                    if e.isDir {
                        NavigationLink {
                            FolderView(root: root, path: path + "/" + e.name, machine: machine)
                        } label: { row(e) }
                    } else {
                        NavigationLink {
                            CodeFileView(path: path + "/" + e.name, machine: machine, git: e.git)
                        } label: { row(e) }
                    }
                }
            } footer: {
                if !loading { Text("\(visible.count) items" + (hiddenCount > 0 && !showHidden ? " · \(hiddenCount) hidden" : "")) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.terminal)
        .overlay { if loading && entries.isEmpty { ProgressView() } }
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show hidden files", isOn: $showHidden)
                    Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            if path == root {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private var hiddenCount: Int { entries.filter { $0.name.hasPrefix(".") }.count }
    private var visible: [FileEntry] { showHidden ? entries : entries.filter { !$0.name.hasPrefix(".") } }

    private func row(_ e: FileEntry) -> some View {
        HStack(spacing: 11) {
            Image(systemName: FileGlyph.symbol(e))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FileGlyph.tint(e))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name)
                    .font(.system(size: 14, weight: e.isDir ? .medium : .regular))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if !e.isDir { Text(ByteCountFormatter.string(fromByteCount: Int64(e.size), countStyle: .file)) }
                    if let m = e.modified { Text(m, format: .relative(presentation: .named)) }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 4)
            if let g = e.git {
                Text(g)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(FileGlyph.gitColor(g))
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(FileGlyph.gitColor(g).opacity(0.14)))
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        guard let c = model.connection else { error = "Not connected"; loading = false; return }
        loading = true
        do {
            entries = try await Git.list(path, via: c, on: machine)
            error = nil
        } catch {
            self.error = AppModel.describe(error)
        }
        loading = false
    }
}

struct CodeFileView: View {
    @Environment(AppModel.self) private var model
    let path: String
    let machine: String?
    var git: String?
    @State private var lines: [String] = []
    @State private var image: UIImage?
    @State private var error: String?
    @State private var loading = true
    @State private var wrap = false

    var body: some View {
        Group {
            if let image {
                ScrollView { Image(uiImage: image).resizable().scaledToFit().padding() }
            } else if let error {
                Text(error).foregroundStyle(Theme.muted).padding()
            } else if loading {
                ProgressView()
            } else {
                ScrollView(wrap ? .vertical : [.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.dim)
                                    .frame(width: gutter, alignment: .trailing)
                                Text(SyntaxColor.line(l))
                                    .font(.system(size: 12, design: .monospaced))
                                    .fixedSize(horizontal: !wrap, vertical: true)
                                    .frame(maxWidth: wrap ? .infinity : nil, alignment: .leading)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(12)
                    .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.terminal)
        .navigationTitle((path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { wrap.toggle() } label: { Image(systemName: wrap ? "text.alignleft" : "arrow.left.and.right.text.vertical") }
            }
        }
        .task { await load() }
    }

    private var gutter: CGFloat { CGFloat(String(lines.count).count) * 7.5 + 4 }

    private func load() async {
        guard let c = model.connection else { error = "Not connected"; loading = false; return }
        do {
            let data = try await Git.read(path, via: c, on: machine)
            if let img = UIImage(data: data), ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains((path as NSString).pathExtension.lowercased()) {
                image = img
            } else if data.prefix(8000).contains(0) {
                error = "Binary file · " + ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            } else {
                lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
                if lines.last == "" { lines.removeLast() }
            }
        } catch {
            self.error = AppModel.describe(error)
        }
        loading = false
    }
}

@MainActor
enum SyntaxColor {
    static let keywords: Set<String> = ["func", "let", "var", "if", "else", "for", "while", "return", "import", "struct", "class", "enum", "case", "switch", "guard", "in", "fn", "pub", "use", "mod", "impl", "const", "function", "export", "default", "from", "async", "await", "try", "catch", "throw", "throws", "def", "self", "Self", "true", "false", "nil", "null", "none", "None", "True", "False", "match", "type", "interface", "extends", "new", "static", "private", "public", "protocol", "extension", "where", "do", "break", "continue", "package", "go", "defer", "mut", "trait", "elif", "lambda", "yield", "with", "as", "is", "not", "and", "or"]

    static func line(_ s: String) -> AttributedString {
        var out = AttributedString()
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("--") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
            var a = AttributedString(s)
            a.foregroundColor = Theme.dim
            return a
        }
        var token = ""
        var inString: Character?
        func flush() {
            guard !token.isEmpty else { return }
            var a = AttributedString(token)
            if keywords.contains(token) { a.foregroundColor = Color(hex: "#c678dd") }
            else if token.first?.isNumber == true { a.foregroundColor = Color(hex: "#d19a66") }
            else if token.first?.isUppercase == true { a.foregroundColor = Color(hex: "#e5c07b") }
            else { a.foregroundColor = Theme.text }
            out += a
            token = ""
        }
        var str = ""
        for ch in s {
            if let q = inString {
                str.append(ch)
                if ch == q {
                    var a = AttributedString(str)
                    a.foregroundColor = Color(hex: "#98c379")
                    out += a
                    str = ""
                    inString = nil
                }
                continue
            }
            if ch == "\"" || ch == "'" || ch == "`" {
                flush()
                inString = ch
                str = String(ch)
                continue
            }
            if ch.isLetter || ch.isNumber || ch == "_" {
                token.append(ch)
            } else {
                flush()
                var a = AttributedString(String(ch))
                a.foregroundColor = Theme.muted
                out += a
            }
        }
        flush()
        if !str.isEmpty {
            var a = AttributedString(str)
            a.foregroundColor = Color(hex: "#98c379")
            out += a
        }
        return out
    }
}

struct DiffReviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let folder: String
    let machine: String?
    @State private var files: [DiffFile] = []
    @State private var collapsed: Set<String> = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: []) {
                    summary(proxy)
                    ForEach(files) { f in fileSection(f).id(f.id) }
                    if !loading && files.isEmpty && error == nil {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle").font(.system(size: 30)).foregroundStyle(Theme.green)
                            Text("No uncommitted changes").foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                    if let error { Text(error).foregroundStyle(Theme.red).font(.system(size: 13)) }
                }
                .padding(12)
            }
        }
        .background(Theme.terminal)
        .overlay { if loading && files.isEmpty { ProgressView() } }
        .navigationTitle("Changes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func summary(_ proxy: ScrollViewProxy) -> some View {
        let adds = files.reduce(0) { $0 + $1.additions }
        let dels = files.reduce(0) { $0 + $1.deletions }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(files.count) file\(files.count == 1 ? "" : "s") changed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("+\(adds)").foregroundStyle(Theme.green)
                Text("−\(dels)").foregroundStyle(Theme.red)
                Spacer()
                DiffBar(adds: adds, dels: dels)
            }
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            ForEach(files) { f in
                Button {
                    collapsed.remove(f.id)
                    withAnimation { proxy.scrollTo(f.id, anchor: .top) }
                } label: {
                    HStack(spacing: 8) {
                        Text(f.status)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(FileGlyph.gitColor(f.status))
                            .frame(width: 16)
                        Text(f.path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Text("+\(f.additions)").foregroundStyle(Theme.green)
                        Text("−\(f.deletions)").foregroundStyle(Theme.red)
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private func fileSection(_ f: DiffFile) -> some View {
        let open = !collapsed.contains(f.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if open { collapsed.insert(f.id) } else { collapsed.remove(f.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.dim)
                    Text(f.path)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    DiffBar(adds: f.additions, dels: f.deletions)
                }
                .padding(10)
                .background(Theme.chrome)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                if f.binary {
                    Text("Binary file").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(10)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(f.hunks.enumerated()), id: \.offset) { _, h in
                                Text(h.header)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Theme.blue.opacity(0.08))
                                ForEach(Array(h.lines.enumerated()), id: \.offset) { _, l in lineRow(l) }
                            }
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    private func lineRow(_ l: DiffLine) -> some View {
        let bg: Color = l.kind == .add ? Theme.green.opacity(0.13) : l.kind == .del ? Theme.red.opacity(0.13) : .clear
        let sign = l.kind == .add ? "+" : l.kind == .del ? "−" : " "
        return HStack(spacing: 0) {
            Text(l.old.map(String.init) ?? "").frame(width: 34, alignment: .trailing)
            Text(l.new.map(String.init) ?? "").frame(width: 34, alignment: .trailing)
            Text(sign)
                .foregroundStyle(l.kind == .add ? Theme.green : l.kind == .del ? Theme.red : Theme.dim)
                .frame(width: 18)
            Text(l.text.isEmpty ? " " : l.text)
                .foregroundStyle(l.kind == .meta ? Theme.dim : Theme.text)
                .fixedSize()
                .padding(.trailing, 12)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(Theme.dim)
        .padding(.vertical, 1)
        .frame(minWidth: 0, alignment: .leading)
        .background(bg)
    }

    private func load() async {
        guard let c = model.connection else { error = "Not connected"; loading = false; return }
        loading = true
        do {
            files = try await Git.diff(folder, via: c, on: machine)
            error = nil
        } catch {
            self.error = AppModel.describe(error)
        }
        loading = false
    }
}

struct DiffBar: View {
    let adds: Int
    let dels: Int

    var body: some View {
        let total = max(adds + dels, 1)
        let g = Int((Double(adds) / Double(total) * 5).rounded())
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(adds + dels == 0 ? Theme.border : i < g ? Theme.green : Theme.red)
                    .frame(width: 7, height: 7)
            }
        }
    }
}
