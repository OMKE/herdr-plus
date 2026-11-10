import GameController
import Observation
import SwiftUI

@MainActor
@Observable
final class HardwareKeyboard {
    static let shared = HardwareKeyboard()
    var connected = GCKeyboard.coalesced != nil

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        let nc = NotificationCenter.default
        for name in [Notification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in HardwareKeyboard.shared.connected = GCKeyboard.coalesced != nil }
            })
        }
    }
}

extension Notification.Name {
    static let herdrDictate = Notification.Name("herdr.dictate")
    static let herdrInterrupt = Notification.Name("herdr.interrupt")
}

struct ShortcutLayer: View {
    @Environment(AppModel.self) private var model
    @State private var showList = false

    var body: some View {
        ZStack {
            ForEach(1...9, id: \.self) { n in
                Button("") { selectTab(n - 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
            Button("") { toggleChat() }.keyboardShortcut("j", modifiers: .command)
            Button("") { NotificationCenter.default.post(name: .herdrDictate, object: nil) }.keyboardShortcut("m", modifiers: [.command, .shift])
            Button("") { withAnimation(.easeOut(duration: 0.2)) { model.drawerOpen.toggle() } }.keyboardShortcut("b", modifiers: .command)
            Button("") { model.showOverview = true }.keyboardShortcut("o", modifiers: .command)
            Button("") { NotificationCenter.default.post(name: .herdrInterrupt, object: nil) }.keyboardShortcut(".", modifiers: .command)
            Button("") { showList = true }.keyboardShortcut("k", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .sheet(isPresented: $showList) {
            NavigationStack {
                List(HardwareShortcuts.all, id: \.title) { s in
                    LabeledContent(s.title) {
                        Text(s.keys).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.amber)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.terminal)
                .navigationTitle("Keyboard shortcuts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showList = false } } }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(model.colorSchemeOverride)
        }
    }

    private func selectTab(_ i: Int) {
        guard let (space, _) = model.currentTab ?? model.spaces.first.flatMap({ s in s.tabs.first.map { (s, $0) } }), space.tabs.indices.contains(i) else { return }
        model.select(TabRef(spaceUID: space.uid, tabID: space.tabs[i].id))
    }

    private func toggleChat() {
        guard let (_, tab) = model.currentTab else { return }
        model.setChat(!model.showsChat(tabID: tab.id), tabID: tab.id)
    }
}
