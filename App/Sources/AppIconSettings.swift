import SwiftUI

struct AppIconSettingsView: View {
    @State private var current = UIApplication.shared.alternateIconName
    @State private var error: String?

    static var currentName: String {
        UIApplication.shared.alternateIconName.map { String($0.dropFirst("AppIcon-".count)) } ?? "Default"
    }

    private var icons: [(id: String?, name: String)] {
        var out: [(String?, String)] = [(nil, "Default")]
        let alt = (Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])?["CFBundleAlternateIcons"] as? [String: Any]
        let names = (alt?.keys.map { $0 } ?? []).sorted { a, b in
            let ca = a.hasPrefix("AppIcon-Custom"), cb = b.hasPrefix("AppIcon-Custom")
            return ca == cb ? a < b : !ca
        }
        for n in names { out.append((n, String(n.dropFirst("AppIcon-".count)))) }
        return out
    }

    var body: some View {
        SettingsPage(title: "App Icon") {
            SettingsHeader("App icon")
            SettingsCard {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 14) {
                    ForEach(icons, id: \.name) { icon in
                        let on = current == icon.id
                        Button { set(icon.id) } label: {
                            VStack(spacing: 6) {
                                preview(icon.name)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border, lineWidth: 0.75))
                                    .padding(3)
                                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(on ? Theme.amber : Color.clear, lineWidth: 2))
                                Text(icon.name)
                                    .font(.system(size: 11, weight: on ? .semibold : .regular))
                                    .foregroundStyle(on ? Theme.text : Theme.muted)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            SettingsFootnote(error ?? "To add your own icon, put a square PNG into App/Resources/CustomIcons and build a new IPA. iOS only allows icons that ship inside the app.")
        }
    }

    @ViewBuilder
    private func preview(_ name: String) -> some View {
        if let img = UIImage(named: "iconpreview-\(name)") {
            Image(uiImage: img).resizable()
        } else {
            RoundedRectangle(cornerRadius: 13).fill(Theme.raised)
        }
    }

    private func set(_ id: String?) {
        guard UIApplication.shared.supportsAlternateIcons else {
            error = "This device doesn't support changing the icon."
            return
        }
        UIApplication.shared.setAlternateIconName(id) { e in
            Task { @MainActor in
                if let e { error = e.localizedDescription } else { current = id }
            }
        }
    }
}
