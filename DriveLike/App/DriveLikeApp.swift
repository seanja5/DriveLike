import SwiftUI

@main
struct DriveLikeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var auth    = SpotifyAuthManager.shared
    @StateObject private var polling = PlaybackPollingManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(polling)
                // Handles relaunch when already authenticated — onChange never fires in that case.
                .task {
                    if auth.isAuthenticated {
                        polling.start()
                    }
                }
                // Handles the moment authentication completes for the first time.
                .onChange(of: auth.isAuthenticated) { isAuthenticated in
                    if isAuthenticated { polling.start() }
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .background {
                        AppDelegate.scheduleBackgroundRefresh()
                    }
                }
        }
    }
}
