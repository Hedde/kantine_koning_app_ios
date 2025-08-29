import Foundation

// MARK: - Season Statistics Models (Spotify-style Personal Performance)
struct SeasonStats {
    let totalHours: Double
    let totalShifts: Int
    let favoriteLocation: String?
    let mostActiveMonth: String?
    let teamContributions: [TeamContribution]
    let achievements: [Achievement]
}

struct TeamContribution {
    let teamCode: String
    let teamName: String
    let hoursWorked: Double
    let shiftsCompleted: Int
    // NOTE: NO leaderboard position - focus on personal performance only
}

struct Achievement {
    let title: String  // "Kantine Kampioen", "Vroege Vogel", "Weekend Warrior"
    let description: String
    let icon: String
}

// MARK: - Season Stats Calculator
extension SeasonStats {
    static func calculate(from diensten: [Dienst], for tenantSlug: String, with tenant: DomainModel.Tenant) -> SeasonStats {
        let tenantDiensten = diensten.filter { $0.tenantId == tenantSlug }
        
        return SeasonStats(
            totalHours: calculateTotalHours(tenantDiensten),
            totalShifts: tenantDiensten.count,
            favoriteLocation: findMostFrequentLocation(tenantDiensten),
            mostActiveMonth: findMostActiveMonth(tenantDiensten),
            teamContributions: calculateTeamContributions(tenantDiensten, with: tenant),
            achievements: generateAchievements(tenantDiensten)
        )
    }
    
    private static func calculateTotalHours(_ diensten: [Dienst]) -> Double {
        return diensten.reduce(0.0) { total, dienst in
            let duration = dienst.endTime.timeIntervalSince(dienst.startTime)
            return total + (duration / 3600.0) // Convert seconds to hours
        }
    }
    
    private static func findMostFrequentLocation(_ diensten: [Dienst]) -> String? {
        let locationCounts = Dictionary(grouping: diensten) { $0.locationName ?? "Kantine" }
            .mapValues { $0.count }
        
        return locationCounts.max(by: { $0.value < $1.value })?.key
    }
    
    private static func findMostActiveMonth(_ diensten: [Dienst]) -> String? {
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "nl_NL")
        monthFormatter.dateFormat = "MMMM"
        
        let monthCounts = Dictionary(grouping: diensten) { dienst in
            monthFormatter.string(from: dienst.startTime)
        }.mapValues { $0.count }
        
        return monthCounts.max(by: { $0.value < $1.value })?.key
    }
    
    private static func calculateTeamContributions(_ diensten: [Dienst], with tenant: DomainModel.Tenant) -> [TeamContribution] {
        let teamGroups = Dictionary(grouping: diensten) { $0.teamId ?? "Onbekend" }
        
        return teamGroups.map { teamId, teamDiensten in
            let hours = teamDiensten.reduce(0.0) { total, dienst in
                let duration = dienst.endTime.timeIntervalSince(dienst.startTime)
                return total + (duration / 3600.0)
            }
            
            // Find the actual team name from the tenant's teams
            let teamName = tenant.teams.first { $0.id == teamId }?.name ?? teamId
            
            return TeamContribution(
                teamCode: teamId,
                teamName: teamName, // Now use the actual team name!
                hoursWorked: hours,
                shiftsCompleted: teamDiensten.count
            )
        }.sorted { $0.hoursWorked > $1.hoursWorked }
    }
    
    private static func generateAchievements(_ diensten: [Dienst]) -> [Achievement] {
        var achievements: [Achievement] = []
        
        // Kantine Kampioen - many hours
        let totalHours = calculateTotalHours(diensten)
        if totalHours >= 40 {
            achievements.append(Achievement(
                title: "Kantine Kampioen",
                description: "Meer dan 40 uur gewerkt dit seizoen!",
                icon: "crown.fill"
            ))
        }
        
        // Vroege Vogel - early morning shifts
        let morningShifts = diensten.filter { Calendar.current.component(.hour, from: $0.startTime) < 10 }
        if morningShifts.count >= 5 {
            achievements.append(Achievement(
                title: "Vroege Vogel",
                description: "\(morningShifts.count) ochtend diensten voltooid",
                icon: "sunrise.fill"
            ))
        }
        
        // Weekend Warrior - weekend shifts
        let weekendShifts = diensten.filter { 
            let weekday = Calendar.current.component(.weekday, from: $0.startTime)
            return weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
        }
        if weekendShifts.count >= 10 {
            achievements.append(Achievement(
                title: "Weekend Warrior",
                description: "\(weekendShifts.count) weekend diensten voltooid",
                icon: "gamecontroller.fill"
            ))
        }
        
        // Trouwe Vrijwilliger - consistent shifts
        if diensten.count >= 20 {
            achievements.append(Achievement(
                title: "Trouwe Vrijwilliger",
                description: "\(diensten.count) diensten voltooid dit seizoen",
                icon: "heart.fill"
            ))
        }
        
        return achievements
    }
}
