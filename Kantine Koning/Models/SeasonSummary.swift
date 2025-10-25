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
    
    // Custom decoder to handle ISO8601 string from backend
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        tenantName = try container.decode(String.self, forKey: .tenantName)
        teamName = try container.decode(String.self, forKey: .teamName)
        teamCode = try container.decode(String.self, forKey: .teamCode)
        seasonStats = try container.decode(SeasonStatsData.self, forKey: .seasonStats)
        
        // Handle calculated_at as ISO8601 string or timestamp
        if let dateString = try? container.decode(String.self, forKey: .calculatedAt) {
            // Try ISO8601 with fractional seconds first
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            if let date = formatter.date(from: dateString) {
                calculatedAt = date
            } else {
                // Fallback to ISO8601 without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) {
                    calculatedAt = date
                } else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .calculatedAt,
                        in: container,
                        debugDescription: "Date string does not match expected ISO8601 format"
                    )
                }
            }
        } else if let timestamp = try? container.decode(Double.self, forKey: .calculatedAt) {
            // Handle as Unix timestamp
            calculatedAt = Date(timeIntervalSince1970: timestamp)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .calculatedAt,
                in: container,
                debugDescription: "calculated_at must be either ISO8601 string or Unix timestamp"
            )
        }
    }
    
    // Custom encoder for Codable conformance
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(tenantName, forKey: .tenantName)
        try container.encode(teamName, forKey: .teamName)
        try container.encode(teamCode, forKey: .teamCode)
        try container.encode(seasonStats, forKey: .seasonStats)
        
        // Encode as Unix timestamp
        try container.encode(calculatedAt.timeIntervalSince1970, forKey: .calculatedAt)
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
