import SwiftUI

@main
struct HerdrApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, p in
                    switch p {
                    case .active: model.becameActive()
                    case .background: model.enteredBackground()
                    default: break
                    }
                }
                .task { model.becameActive() }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.id)) {
            await BackgroundRefresh.run()
        }
    }
}
