import SwiftUI

struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.terminal.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsHeader: View {
    let text: String
    var trailing: String? = nil

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.muted)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }
}

struct SettingsCard<Content: View>: View {
    var danger = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(danger ? Theme.red.opacity(0.07) : Theme.chrome))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(danger ? Theme.red.opacity(0.45) : Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SettingsDivider: View {
    var inset: CGFloat = 14

    var body: some View {
        Rectangle().fill(Theme.border).frame(height: 0.5).padding(.leading, inset)
    }
}

struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(tint.opacity(0.3), lineWidth: 0.75))
    }
}

struct SettingsRow: View {
    let title: String
    var value: String? = nil
    var icon: String? = nil
    var tint: Color = Theme.amber
    var chevron = true

    var body: some View {
        HStack(spacing: 12) {
            if let icon { SettingsIcon(symbol: icon, tint: tint) }
            Text(title).font(.system(size: 16)).foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.system(size: 14)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: icon == nil ? 46 : 50)
        .contentShape(Rectangle())
    }
}

struct SettingsToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16)).foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.amber)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

struct SettingsSegment<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                let on = selection == value
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeOut(duration: 0.15)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: compact ? 13 : 14, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.text : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 5 : 7)
                        .padding(.horizontal, compact ? 12 : 0)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Theme.raised : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(on ? Theme.border : Color.clear, lineWidth: 0.75))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.chromeDeep))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
    }
}

struct SettingsPill: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.raised))
            .overlay(Capsule().stroke(Theme.border, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsFootnote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}
