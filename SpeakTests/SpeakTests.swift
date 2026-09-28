import XCTest
@testable import Speak

final class SpeakTests: XCTestCase {
    func testProgressStatsEmpty() {
        let stats = ProgressStats(sessions: [])
        XCTAssertEqual(stats.totalSessions, 0)
        XCTAssertEqual(stats.currentStreak, 0)
    }
}
