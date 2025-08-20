import Foundation

// MARK: - Leaderboard Domain Models
struct LeaderboardData: Equatable {
    let tenantSlug: String
    let tenantName: String
    let clubName: String?
    let clubLogoUrl: String?
    let period: String
    let teams: [LeaderboardTeam]
    let leaderboardOptOut: Bool
    let lastUpdated: Date
}

struct LeaderboardTeam: Equatable, Identifiable {
    let id: String
    let name: String
    let code: String?
    let rank: Int
    let points: Int
    let totalHours: Double
    let recentChange: Int
    let positionChange: Int
    let highlighted: Bool
}
