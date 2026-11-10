import Foundation
import BackgroundTasks
import UserNotifications
import HerdrKit
import HerdrSSH

enum BackgroundRefresh {
    static let id = "io.github.herdr-ios.app.refresh"

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    static func run() async {
        schedule()
        let s = AppSettings.load()
        guard s.isComplete, let key = try? KeyStore.loadOrCreate() else { return }
        guard let transport = try? await SSHTransport.connect(s.target, fingerprint: s.fingerprint, key: key) else { return }
        let c = CoreConnection(transport: transport)
        defer { Task { await c.close() } }
        guard (try? await c.start()) != nil, let ts = try? await c.terminals() else { return }
        let n = ts.filter { $0.isAgent && $0.agentState == .blocked }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(n)
    }
}
