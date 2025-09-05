import Foundation

// MARK: - Season Summary API Response Models

struct SeasonSummaryResponse: Codable {
    let tenantName: String
    let teamName: String
    let teamCode: String
    let seasonStats: SeasonStatsData
    let calculatedAt: Date
    
    private enum CodingKeys: String, CodingKey {
        case tenantName = "tenant_club_name"
        case teamName = "team_naam"
        case teamCode = "team_code"
        case seasonStats = "season_stats"
        case calculatedAt = "calculated_at"
    }
}

struct SeasonStatsData: Codable {
    let totalHours: Double
    let totalShifts: Int
    let favoriteLocation: String?
    let mostActiveMonth: String?
    let achievements: [AchievementData]
    
    private enum CodingKeys: String, CodingKey {
        case totalHours = "total_hours"
        case totalShifts = "total_shifts"
        case favoriteLocation = "favorite_location"
        case mostActiveMonth = "most_active_month"
        case achievements
    }
}

struct AchievementData: Codable {
    let title: String
    let description: String
    let icon: String
}

// MARK: - Conversion Extensions

extension SeasonStatsData {
    /// Convert API response to existing SeasonStats model for UI compatibility
    func toSeasonStats(for tenant: DomainModel.Tenant) -> SeasonStats {
        return SeasonStats(
            totalHours: totalHours,
            totalShifts: totalShifts,
            favoriteLocation: favoriteLocation,
            mostActiveMonth: mostActiveMonth,
            teamContributions: [], // Not provided by API - would need separate endpoint
            achievements: achievements.map { Achievement(
                title: $0.title,
                description: $0.description,
                icon: $0.icon
            )}
        )
    }
}

// MARK: - Error Response Models

struct SeasonSummaryApiError: Codable {
    let error: String
}

extension SeasonSummaryApiError {
    var isDataDeleted: Bool {
        return error == "season_data_deleted"
    }
    
    var isNotFound: Bool {
        return error == "tenant_not_found" || error == "team_not_found"
    }
}
