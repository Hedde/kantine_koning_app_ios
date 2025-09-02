import Foundation

// Tenant information including club logos
struct TenantInfo {
    let slug: String
    let name: String
    let clubLogoUrl: String?
    let seasonEnded: Bool
    let teams: [TeamInfo]
    
    struct TeamInfo {
        let id: String
        let code: String
        let name: String
        let role: String
    }
}
