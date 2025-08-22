import Foundation

// MARK: - Leaderboard Repository Protocol
protocol LeaderboardRepository {
    func fetchLeaderboard(tenant: String, period: String, teamId: String?, auth: String, completion: @escaping (Result<LeaderboardResponse, Error>) -> Void)
}

// MARK: - Default Implementation
final class DefaultLeaderboardRepository: LeaderboardRepository {
    private let client: BackendClient
    
    init(client: BackendClient = BackendClient()) {
        self.client = client
    }
    
    func fetchLeaderboard(tenant: String, period: String, teamId: String?, auth: String, completion: @escaping (Result<LeaderboardResponse, Error>) -> Void) {
        client.authToken = auth
        client.fetchLeaderboard(tenant: tenant, period: period, teamId: teamId, completion: completion)
    }
}
