import SwiftData
import SwiftUI

struct RootView: View {
    @AppStorage(AppSettings.Keys.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showLatestReport") {
            LatestReportDebugView()
        } else {
            content
        }
        #else
        content
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

enum AppTab: String, Hashable {
    case practice, progress, history, settings
}

struct MainTabView: View {
    @State private var selection: AppTab = MainTabView.initialTab

    var body: some View {
        TabView(selection: $selection) {
            Tab("Practice", systemImage: "mic.fill", value: AppTab.practice) {
                NavigationStack { PracticeHomeView() }
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                NavigationStack { ProgressDashboardView() }
            }
            Tab("History", systemImage: "clock.arrow.circlepath", value: AppTab.history) {
                NavigationStack { HistoryListView() }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
    }

    private static var initialTab: AppTab {
        #if DEBUG
        // `-startTab progress` (UserDefaults argument domain) opens a specific tab, for UI checks.
        if let raw = UserDefaults.standard.string(forKey: "startTab"), let tab = AppTab(rawValue: raw) {
            return tab
        }
        #endif
        return .practice
    }
}

#if DEBUG
/// `-showLatestReport` opens the most recent completed session's detail screen directly.
private struct LatestReportDebugView: View {
    @Query(sort: \PracticeSession.date, order: .reverse) private var sessions: [PracticeSession]

    var body: some View {
        NavigationStack {
            if let session = sessions.first(where: { $0.status == .complete }) {
                SessionDetailView(session: session)
            } else {
                Text("No completed sessions")
            }
        }
    }
}
#endif
