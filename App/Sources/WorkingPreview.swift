#if DEBUG
import SwiftUI
import HerdrKit

struct WorkingPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkingRow(since: Date().addingTimeInterval(-290), activity: ScreenActivity(label: "Deliberating…", detail: "4m 50s · ↓ 3.4k tokens")) {}
            WorkingRow(since: Date().addingTimeInterval(-12), activity: ScreenActivity(label: "Combobulating…")) {}
            WorkingRow(since: Date().addingTimeInterval(-75), activity: nil) {}
            Spacer()
        }
        .padding(16)
        .padding(.top, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.chrome)
    }
}
#endif
