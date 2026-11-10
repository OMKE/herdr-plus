import SwiftUI
import UniformTypeIdentifiers

struct ThemeSwatch: View {
    let palette: Palette
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("~/website").foregroundStyle(Color(hex: palette.blue))
                    Text("main").foregroundStyle(Color(hex: palette.red))
                }
                HStack(spacing: 3) {
                    Text("●").foregroundStyle(Color(hex: palette.green))
                    Text("Update(nav)").foregroundStyle(Color(hex: palette.text))
                }
                Text(" ⎿ +3 -1").foregroundStyle(Color(hex: palette.muted))
                HStack(spacing: 3) {
                    Text("❯").foregroundStyle(Color(hex: palette.accent))
                    Text("_").foregroundStyle(Color(hex: palette.text))
                }
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: palette.terminal)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selected ? Theme.amber : Color(hex: palette.border), lineWidth: selected ? 2 : 1))
            .padding(selected ? 0 : 1)
            HStack(spacing: 4) {
                Text(palette.name)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.onAccent, Theme.amber)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct AppearanceSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsPage(title: "Appearance") {
            SettingsSegment(options: Appearance.allCases.map { ($0, $0.label) }, selection: $model.settings.appearance)
            SettingsFootnote(caption)
            SettingsHeader("Dark theme")
            grid(Palette.darkThemes, selection: $model.settings.darkTheme)
            SettingsHeader("Light theme")
            grid(Palette.lightThemes, selection: $model.settings.lightTheme)
        }
    }

    private var caption: String {
        switch model.settings.appearance {
        case .system: "Follows iOS. The dark theme is used at night, the light one during the day."
        case .light: "Light is on. System would follow iOS."
        case .dark: "Dark is on. System would follow iOS."
        }
    }

    private func grid(_ themes: [Palette], selection: Binding<String>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
            ForEach(themes) { p in
                ThemeSwatch(palette: p, selected: selection.wrappedValue == p.id)
                    .onTapGesture {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selection.wrappedValue = p.id
                    }
            }
        }
    }
}

struct FontSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let s = model.settings
        SettingsPage(title: "Fonts & Size") {
            SettingsHeader("Terminal")
            SettingsCard {
                terminalPreview
                    .padding(12)
                SettingsDivider(inset: 0)
                Menu {
                    Picker("Font", selection: $model.settings.terminalFont) {
                        ForEach(TermFont.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    SettingsRow(title: "Font", value: s.terminalFont.label)
                }
                .buttonStyle(.plain)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(TermFont.allCases) { f in
                            let on = f == s.terminalFont
                            Button { model.settings.terminalFont = f } label: {
                                Text(f.label)
                                    .font(f.font(13))
                                    .foregroundStyle(on ? Theme.amber : Theme.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(on ? Theme.amberBg : Theme.raised))
                                    .overlay(Capsule().stroke(on ? Theme.amber : Theme.border, lineWidth: on ? 1.5 : 0.75))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                SettingsDivider(inset: 0)
                HStack {
                    Text("Size").font(.system(size: 16)).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(Int(s.fontSize))").font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                        .padding(.trailing, 8)
                    stepper(value: $model.settings.fontSize, range: 8...22)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                Text(s.terminalFont.note.map { "\($0) · pinch the terminal to change the size" } ?? "Pinch the terminal to change the size.")
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
            SettingsHeader("Chat")
            SettingsCard {
                chatPreview
                    .padding(12)
                SettingsDivider(inset: 0)
                Menu {
                    Picker("Font", selection: $model.settings.chatFont) {
                        ForEach(ChatFont.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    SettingsRow(title: "Font", value: s.chatFont.label)
                }
                .buttonStyle(.plain)
                SettingsDivider()
                HStack(spacing: 12) {
                    Text("A").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Slider(value: $model.settings.chatSize, in: 12...22, step: 1).tint(Theme.amber)
                    Text("A").font(.system(size: 20)).foregroundStyle(Theme.muted)
                    Text("\(Int(s.chatSize))").font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                        .frame(minWidth: 24, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .onChange(of: model.settings.fontSize) { _, v in model.pool.setFont(size: CGFloat(v)) }
    }

    private var terminalPreview: some View {
        let size = CGFloat(model.settings.fontSize)
        let f = model.settings.terminalFont
        return VStack(alignment: .leading, spacing: 2) {
            (Text("~/code/website ").foregroundStyle(Theme.blue) + Text("fix/docs-nav* ").foregroundStyle(Theme.muted) + Text("❯ pnpm build").foregroundStyle(Theme.text))
            (Text("● ").foregroundStyle(Theme.green) + Text("Update").bold().foregroundStyle(Theme.text) + Text("(src/content/schema.ts)").foregroundStyle(Theme.text))
            Text("14 - order: z.number(),")
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.red.opacity(0.22))
            Text("14 + order: z.number().default(0),")
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.green.opacity(0.22))
            Text("✻ Worked for 22s · O0 lI1 {}[]").foregroundStyle(Theme.muted)
        }
        .font(f.font(size))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.terminal))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
    }

    private var chatPreview: some View {
        let size = CGFloat(model.settings.chatSize)
        let font = model.settings.chatFont
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 50)
                Text("keep 0001_init, regenerate the rest")
                    .font(font.font(size))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.raised))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
            }
            (Text("Done. The nav groups pages by ") + Text("section").font(Typo.code(size - 2)).foregroundStyle(Theme.codeInk) + Text(" and the build passes."))
                .font(font.font(size))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepper(value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 0) {
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) } label: {
                Image(systemName: "minus").frame(width: 36, height: 30)
            }
            Rectangle().fill(Theme.border).frame(width: 0.75, height: 18)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) } label: {
                Image(systemName: "plus").frame(width: 36, height: 30)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.text)
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
    }
}

struct ToolbarSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Int
    @State private var dragging: ToolKey?

    init(initialTab: Int = 0) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        @Bindable var model = model
        let keys = tab == 0 ? $model.settings.termKeys : $model.settings.chatKeys
        let choices = tab == 0 ? ToolKey.terminalChoices : ToolKey.chatChoices
        let rest = choices.filter { !keys.wrappedValue.contains($0) }
        SettingsPage(title: "Toolbar") {
            preview(keys.wrappedValue)
            Text("Preview · \(tab == 0 ? "Terminal" : "Chat") toolbar")
                .font(.system(size: 12)).foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 12)
            SettingsSegment(options: [(1, "Chat"), (0, "Terminal")], selection: $tab)
            SettingsHeader("\(tab == 0 ? "Terminal" : "Chat") toolbar", trailing: "Hold and drag")
            SettingsCard {
                FlowLayout(spacing: 8) {
                    ForEach(keys.wrappedValue) { k in
                        chip(k, inBar: true)
                            .opacity(dragging == k ? 0.4 : 1)
                            .onDrag {
                                dragging = k
                                return NSItemProvider(object: k.rawValue as NSString)
                            }
                            .onDrop(of: [UTType.text], delegate: KeyDropDelegate(target: k, keys: keys, dragging: $dragging))
                            .onTapGesture {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation { keys.wrappedValue.removeAll { $0 == k } }
                            }
                    }
                }
                .padding(12)
                if !rest.isEmpty {
                    SettingsDivider(inset: 0)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add a key").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        FlowLayout(spacing: 8) {
                            ForEach(rest) { k in
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    withAnimation { keys.wrappedValue.append(k) }
                                } label: { chip(k, inBar: false) }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                }
            }
            SettingsFootnote("Hold a key and drag to reorder. Tap a key to take it out.")
            SettingsHeader("Style")
            SettingsCard {
                SettingsToggle(title: "Liquid Glass", subtitle: "Off uses a solid bar, easier to read over busy output.", isOn: $model.settings.toolbarGlass)
                SettingsDivider()
                HStack {
                    Text("Key labels").font(.system(size: 16)).foregroundStyle(Theme.text)
                    Spacer()
                    SettingsSegment(options: [(ToolLabels.text, "Text"), (ToolLabels.symbols, "Icons")], selection: $model.settings.toolbarLabels, compact: true)
                        .fixedSize()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                SettingsDivider()
                barRow("Top bar", $model.settings.topBar)
                SettingsDivider()
                barRow("Bottom bar", $model.settings.bottomBar)
            }
            SettingsFootnote("Floating bars hover over the content with rounded glass. Docked bars sit flush with the screen edge. Applies to chat and terminal.")
            Button {
                withAnimation { keys.wrappedValue = tab == 0 ? ToolKey.defaultTerminal : ToolKey.defaultChat }
            } label: {
                Text("Reset to defaults")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.amber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.chrome))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
        }
    }

    private func barRow(_ title: String, _ value: Binding<BarStyle>) -> some View {
        HStack {
            Text(title).font(.system(size: 16)).foregroundStyle(Theme.text)
            Spacer()
            SettingsSegment(options: BarStyle.allCases.map { ($0, $0.label) }, selection: value, compact: true)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func chip(_ k: ToolKey, inBar: Bool) -> some View {
        let accent = [.one, .two, .three].contains(k)
        return HStack(spacing: 4) {
            if inBar {
                Image(systemName: "line.3.horizontal").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.dim)
            } else {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim)
            }
            Keycap(key: k, labels: model.settings.toolbarLabels, accent: accent && inBar, glass: false, compact: true)
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(inBar ? Theme.raised.opacity(0.5) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(inBar ? Theme.border : Theme.border.opacity(0.6), style: StrokeStyle(lineWidth: 0.75, dash: inBar ? [] : [3, 2])))
    }

    private func preview(_ keys: [ToolKey]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keys) { k in
                    Keycap(key: k, labels: model.settings.toolbarLabels, accent: [.one, .two, .three].contains(k), glass: model.settings.toolbarGlass)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(model.settings.toolbarGlass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Theme.chrome)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
        .padding(.top, 4)
    }
}

private struct KeyDropDelegate: DropDelegate {
    let target: ToolKey
    let keys: Binding<[ToolKey]>
    @Binding var dragging: ToolKey?

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target,
              let from = keys.wrappedValue.firstIndex(of: d),
              let to = keys.wrappedValue.firstIndex(of: target) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            keys.wrappedValue.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
