import SwiftUI
import HerdrKit

extension TabRef: Identifiable {
    var id: String { spaceUID + "|" + tabID }
}

struct NewTabSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let space: Space
    @State private var name = ""
    @State private var busy: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Tab name (optional)", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    option(nil, title: "Terminal", subtitle: "Your shell in " + folderName)
                    Text("AGENT TAB")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(AgentCatalog.agents(model.programs), id: \.key) { p in
                            option(p, title: p.name, subtitle: p.run.joined(separator: " "))
                        }
                    }
                    if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(Theme.red)
                    }
                }
                .padding(16)
            }
            .background(Theme.terminal)
            .navigationTitle("New tab in " + space.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var folderName: String {
        let f = (space.folder as NSString).lastPathComponent
        return f.isEmpty ? space.displayName : f
    }

    private func option(_ p: Program?, title: String, subtitle: String) -> some View {
        let key = p?.key ?? "shell"
        return Button {
            guard busy == nil else { return }
            busy = key
            error = nil
            Task {
                do {
                    try await model.newTab(in: space, program: p, name: name, after: model.selectedTab?.spaceUID == space.uid ? model.selectedTab?.tabID : nil)
                    dismiss()
                } catch {
                    self.error = "Couldn't open the tab: " + AppModel.describe(error)
                }
                busy = nil
            }
        } label: {
            HStack(spacing: 10) {
                ProgramIcon(program: p ?? model.programs.programs["shell"], size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(subtitle).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.dim).lineLimit(1)
                }
                Spacer(minLength: 0)
                if busy == key { ProgressView().controlSize(.small) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(busy != nil && busy != key ? 0.5 : 1)
        .accessibilityIdentifier("newtab-" + key)
    }
}

struct RenameTabSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ref: TabRef
    @State private var name = ""
    @State private var renameSession = true
    @State private var busy = false
    @State private var error: String?

    private var agent: Program? {
        guard let (s, t) = model.tab(ref), let term = model.primaryTerminal(t, in: s), term.isAgent else { return nil }
        return model.programs.program(for: term)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tab name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier("rename-field")
                }
                if AgentCatalog.canRenameSession(agent) {
                    Section {
                        Toggle("Also rename the \(agent?.name ?? "agent") session", isOn: $renameSession)
                    } footer: {
                        Text("Sends /rename to the agent so its session gets the same name.")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.terminal)
            .navigationTitle("Rename tab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button("Save", action: save).accessibilityIdentifier("rename-save") }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { name = model.tab(ref)?.1.name ?? "" }
    }

    private func save() {
        guard !busy else { return }
        busy = true
        Task {
            do {
                try await model.renameTab(ref, to: name, renameSession: renameSession && AgentCatalog.canRenameSession(agent))
                dismiss()
            } catch {
                self.error = "Couldn't rename: " + AppModel.describe(error)
            }
            busy = false
        }
    }
}
