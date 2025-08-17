//
//  TeamHelpers.swift
//  Kantine Koning
//
//  Created by AI Assistant on 16/08/2025.
//

import Foundation

// MARK: - Team Helper Functions
func teamIdToName(_ teamId: String) -> String {
	switch teamId {
	case "team_jo11_3":
		return "JO11-3"
	case "team_jo8_2jm":
		return "JO8-2JM"
	default:
		// Clean up the team ID if it follows our pattern
		if teamId.hasPrefix("team_") {
			let cleanId = String(teamId.dropFirst(5)) // Remove "team_"
			return cleanId.replacingOccurrences(of: "_", with: "-").uppercased()
		}
		return teamId
	}
}
