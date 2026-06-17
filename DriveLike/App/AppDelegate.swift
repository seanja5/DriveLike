import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.drivelike.app.refresh",
            using: nil
        ) { task in
            Self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
        return true
    }

    // Called when app enters background — grab ~30 s of extra runtime for one last poll,
    // then schedule the next BGAppRefreshTask wakeup.
    func applicationDidEnterBackground(_ application: UIApplication) {
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = application.beginBackgroundTask {
            application.endBackgroundTask(bgTask)
        }
        Task {
            await PlaybackPollingManager.shared.forcePoll()
            application.endBackgroundTask(bgTask)
        }
        Self.scheduleBackgroundRefresh()
    }

    // MARK: - Background refresh

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.drivelike.app.refresh")
        // Ask to run as soon as possible; iOS will throttle to ~30 s minimum.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleBackgroundRefresh(task: BGAppRefreshTask) {
        // Immediately reschedule so the chain continues.
        scheduleBackgroundRefresh()

        let work = Task {
            await PlaybackPollingManager.shared.forcePoll()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
