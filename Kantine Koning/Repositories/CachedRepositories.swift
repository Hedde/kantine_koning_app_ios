import Foundation

/// Enhanced repositories with intelligent caching for offline-first experience
/// These repositories provide cached data immediately while fetching fresh data in background

// MARK: - Cached Dienst Repository

final class CachedDienstRepository: DienstRepository {
    private let backend = BackendClient()
    
    func fetchUpcoming(for model: DomainModel, completion: @escaping (Result<[Dienst], Error>) -> Void) {
        guard !model.tenants.isEmpty else { 
            completion(.success([])); return 
        }
        
        let group = DispatchGroup()
        var freshCollected: [Dienst] = []
        var cachedCollected: [Dienst] = []
        var firstError: Error?
        var hasCachedData = false
        var completionCalled = false
        
        Logger.debug("Fetching diensten for \(model.tenants.count) tenants with caching support")
        
        // First pass: collect cached data and return immediately if available
        for tenant in model.tenants.values {
            let cacheKey = CacheManager.CacheKey.diensten(tenantSlug: tenant.slug)
            let cachedResult = CacheManager.shared.getCached([DienstDTO].self, forKey: cacheKey)
            
            if let cachedItems = cachedResult.data {
                Logger.debug("Using cached diensten for tenant \(tenant.slug): \(cachedItems.count) items")
                let mapped = cachedItems.map(mapDTOToDienst)
                cachedCollected.append(contentsOf: mapped)
                hasCachedData = true
            }
        }
        
        // Return cached data immediately if available
        if hasCachedData {
            let deduped = deduplicateAndSort(cachedCollected)
            Logger.success("Returning \(deduped.count) cached diensten while fetching fresh data")
            completion(.success(deduped))
            completionCalled = true
        }
        
        // Second pass: fetch fresh data (always attempt, even if we have cached data)
        for tenant in model.tenants.values {
            group.enter()
            
            // Use tenant-specific auth token
            let tenantBackend = BackendClient()
            tenantBackend.authToken = tenant.signedDeviceToken
            
            Logger.network("Fetching fresh diensten for tenant \(tenant.slug)")
            
            tenantBackend.fetchDiensten(tenant: tenant.slug) { result in
                defer { group.leave() }
                
                switch result {
                case .success(let items):
                    Logger.success("Fetched \(items.count) fresh diensten for tenant \(tenant.slug)")
                    
                    // Cache the fresh data
                    let cacheKey = CacheManager.CacheKey.diensten(tenantSlug: tenant.slug)
                    CacheManager.shared.cache(items, forKey: cacheKey)
                    
                    let mapped = items.map(self.mapDTOToDienst)
                    freshCollected.append(contentsOf: mapped)
                    
                case .failure(let err):
                    Logger.error("Failed to fetch diensten for tenant \(tenant.slug): \(err)")
                    if firstError == nil { firstError = err }
                }
            }
        }
        
        // Handle fresh data completion
        group.notify(queue: .global()) {
            // If we already returned cached data and fresh fetch failed, don't override with error
            if completionCalled && firstError != nil && freshCollected.isEmpty {
                Logger.warning("Fresh fetch failed but cached data already returned")
                return
            }
            
            // If we have fresh data or no cached data was available
            if !freshCollected.isEmpty {
                let deduped = self.deduplicateAndSort(freshCollected)
                Logger.success("Returning \(deduped.count) fresh diensten")
                DispatchQueue.main.async {
                    completion(.success(deduped))
                }
            } else if !completionCalled {
                // No cached data and fresh fetch failed
                DispatchQueue.main.async {
                    completion(.failure(firstError ?? NetworkError.noData))
                }
            }
        }
    }
    
    func addVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void) {
        backend.addVolunteer(tenant: tenant, dienstId: dienstId, name: name) { [weak self] result in
            // Invalidate cache on successful volunteer update
            if case .success = result {
                let cacheKey = CacheManager.CacheKey.diensten(tenantSlug: tenant)
                CacheManager.shared.invalidateCache(forKey: cacheKey)
                Logger.debug("🗑️ Cache invalidated for tenant \(tenant) after volunteer add")
            }
            
            guard let self = self else {
                Logger.error("CachedDienstRepository deallocated during volunteer add")
                completion(.failure(NSError(domain: "CachedRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Repository deallocated"])))
                return
            }
            
            completion(result.map(self.mapDTOToDienst))
        }
    }
    
    func removeVolunteer(tenant: TenantID, dienstId: String, name: String, completion: @escaping (Result<Dienst, Error>) -> Void) {
        backend.removeVolunteer(tenant: tenant, dienstId: dienstId, name: name) { [weak self] result in
            // Invalidate cache on successful volunteer update
            if case .success = result {
                let cacheKey = CacheManager.CacheKey.diensten(tenantSlug: tenant)
                CacheManager.shared.invalidateCache(forKey: cacheKey)
                Logger.debug("🗑️ Cache invalidated for tenant \(tenant) after volunteer remove")
            }
            
            guard let self = self else {
                Logger.error("CachedDienstRepository deallocated during volunteer remove")
                completion(.failure(NSError(domain: "CachedRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Repository deallocated"])))
                return
            }
            
            completion(result.map(self.mapDTOToDienst))
        }
    }
    
    func submitVolunteers(actionToken: String, names: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        backend.submitVolunteers(actionToken: actionToken, names: names, completion: completion)
    }
    
    // MARK: - Helper Methods
    
    private func deduplicateAndSort(_ diensten: [Dienst]) -> [Dienst] {
        var byId: [String: Dienst] = [:]
        for d in diensten { 
            if let existing = byId[d.id] {
                let choose: Bool
                if let existingUpdated = existing.updatedAt, let dUpdated = d.updatedAt {
                    choose = dUpdated > existingUpdated
                } else {
                    choose = d.startTime > existing.startTime
                }
                if choose { byId[d.id] = d }
            } else {
                byId[d.id] = d
            }
        }
        
        let deduped = Array(byId.values)
        let future = deduped.filter { $0.startTime >= Date() }.sorted { $0.startTime < $1.startTime }
        let past = deduped.filter { $0.startTime < Date() }.sorted { $0.startTime > $1.startTime }
        return future + past
    }
    
    private func mapDTOToDienst(_ dto: DienstDTO) -> Dienst {
        return Dienst(
            id: dto.id,
            tenantId: dto.tenant_id,
            teamId: dto.team?.code ?? dto.team?.id,
            startTime: dto.start_tijd,
            endTime: dto.eind_tijd,
            status: dto.status,
            locationName: dto.locatie_naam,
            volunteers: dto.aanmeldingen,
            updatedAt: dto.updated_at,
            minimumBemanning: dto.minimum_bemanning
        )
    }
}

// MARK: - Cached Leaderboard Repository

final class CachedLeaderboardRepository: LeaderboardRepository {
    private let backend = BackendClient()
    
    func fetchLeaderboard(tenant: TenantID, period: String, teamId: String?, auth: String, completion: @escaping (Result<LeaderboardResponse, Error>) -> Void) {
        let cacheKey = CacheManager.CacheKey.leaderboard(tenantSlug: tenant, period: period, teamId: teamId)
        let cachedResult = CacheManager.shared.getCached(LeaderboardResponse.self, forKey: cacheKey)
        
        // Return cached data immediately if available
        if let cachedData = cachedResult.data {
            Logger.debug("Using cached leaderboard for tenant \(tenant)")
            completion(.success(cachedData))
        }
        
        // Fetch fresh data (always, even if cached data exists)
        backend.authToken = auth
        backend.fetchLeaderboard(tenant: tenant, period: period, teamId: teamId) { result in
            switch result {
            case .success(let response):
                Logger.success("Fetched fresh leaderboard for tenant \(tenant)")
                
                // Cache with longer TTL for leaderboards
                CacheManager.shared.cache(response, forKey: cacheKey, ttl: 600) // 10 minutes
                
                // Only call completion if we didn't already return cached data
                if cachedResult.data == nil {
                    completion(.success(response))
                }
                
            case .failure(let error):
                Logger.error("Failed to fetch leaderboard for tenant \(tenant): \(error)")
                
                // Only call completion with error if we don't have cached data
                if cachedResult.data == nil {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func fetchGlobalLeaderboard(tenant: TenantID, period: String, teamId: String?, auth: String, completion: @escaping (Result<GlobalLeaderboardResponse, Error>) -> Void) {
        let cacheKey = CacheManager.CacheKey.globalLeaderboard(tenantSlug: tenant, period: period, teamId: teamId)
        let cachedResult = CacheManager.shared.getCached(GlobalLeaderboardResponse.self, forKey: cacheKey)
        
        // Return cached data immediately if available
        if let cachedData = cachedResult.data {
            Logger.debug("Using cached global leaderboard for tenant \(tenant)")
            completion(.success(cachedData))
        }
        
        // Fetch fresh data
        backend.authToken = auth
        backend.fetchGlobalLeaderboard(tenant: tenant, period: period, teamId: teamId) { result in
            switch result {
            case .success(let response):
                Logger.success("Fetched fresh global leaderboard for tenant \(tenant)")
                
                // Cache with longer TTL
                CacheManager.shared.cache(response, forKey: cacheKey, ttl: 600) // 10 minutes
                
                if cachedResult.data == nil {
                    completion(.success(response))
                }
                
            case .failure(let error):
                Logger.error("Failed to fetch global leaderboard for tenant \(tenant): \(error)")
                
                if cachedResult.data == nil {
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - Network Error

enum NetworkError: LocalizedError {
    case noData
    
    var errorDescription: String? {
        switch self {
        case .noData:
            return "No data available"
        }
    }
}
