import Foundation

// MARK: - BackendClient Season Summary Extension

extension BackendClient {
    
    /// Fetch season summary for a specific team (public endpoint, no auth required)
    func fetchSeasonSummary(
        tenantSlug: String,
        teamCode: String,
        completion: @escaping (Result<SeasonSummaryResponse, Error>) -> Void
    ) {
        let url = baseURL.appendingPathComponent("/api/mobile/v1/season-summary/\(tenantSlug)/\(teamCode)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Note: No Authorization header - this is a public endpoint
        
        Logger.network("Fetching season summary for \(tenantSlug)/\(teamCode)")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                Logger.error("Season summary network error: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let invalidResponseError = AppError.serverError(-1)
                completion(.failure(invalidResponseError))
                return
            }
            
            guard let data = data else {
                let noDataError = AppError.dataCorrupted
                completion(.failure(noDataError))
                return
            }
            
            // Handle different HTTP status codes
            switch httpResponse.statusCode {
            case 200:
                do {
                    let summary = try JSONDecoder().decode(SeasonSummaryResponse.self, from: data)
                    Logger.success("Season summary loaded: \(summary.seasonStats.totalShifts) shifts, \(String(format: "%.1f", summary.seasonStats.totalHours)) hours")
                    completion(.success(summary))
                } catch {
                    Logger.error("Season summary decode error: \(error)")
                    completion(.failure(error))
                }
                
            case 404:
                Logger.warning("Season summary not found (404)")
                completion(.failure(SeasonSummaryNetworkError.notFound))
                
            case 410:
                // Season data was deleted
                Logger.info("Season data was deleted (410)")
                completion(.failure(SeasonSummaryNetworkError.dataDeleted))
                
            default:
                do {
                    let errorResponse = try JSONDecoder().decode(ApiErrorResponse.self, from: data)
                    Logger.error("Season summary API error: \(errorResponse.error)")
                    completion(.failure(SeasonSummaryNetworkError.apiError(errorResponse.error)))
                } catch {
                    Logger.error("Unknown season summary error (status: \(httpResponse.statusCode))")
                    completion(.failure(SeasonSummaryNetworkError.unknownError(httpResponse.statusCode)))
                }
            }
        }.resume()
    }
}

// MARK: - API Response Models

struct ApiErrorResponse: Codable {
    let error: String
}

// MARK: - Season Summary Specific Errors

enum SeasonSummaryNetworkError: Error, LocalizedError {
    case notFound
    case dataDeleted
    case apiError(String)
    case unknownError(Int)
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Season summary not found"
        case .dataDeleted:
            return "Season data has been deleted"
        case .apiError(let message):
            return "API Error: \(message)"
        case .unknownError(let statusCode):
            return "Unknown error (status: \(statusCode))"
        }
    }
    
    var isDataDeleted: Bool {
        if case .dataDeleted = self {
            return true
        }
        return false
    }
    
    var isNotFound: Bool {
        if case .notFound = self {
            return true
        }
        return false
    }
}
