import SwiftData
import SwiftUI

@main
struct SpeakApp: App {
    let container: ModelContainer

    init() {
        #if DEBUG
        // `-demoData` launches with an in-memory store of sample sessions (for screenshots/UI checks).
        if ProcessInfo.processInfo.arguments.contains("-demoData") {
            UserDefaults.standard.set(true, forKey: AppSettings.Keys.hasCompletedOnboarding)
            container = PreviewData.makeContainer(sessionCount: 28, includeEdgeStates: false)
            return
        }
        #endif
        do {
            container = try ModelContainer(for: PracticeSession.self)
        } catch {
            fatalError("Could not create the data store: \(error)")
        }
        SessionProcessor.recoverInterruptedSessions(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(WhisperModelManager.shared)
                .task {
                    // Warm the speech model in the background so the first analysis is fast.
                    await WhisperModelManager.shared.prepare()
                }
        }
        .modelContainer(container)
    }
}
