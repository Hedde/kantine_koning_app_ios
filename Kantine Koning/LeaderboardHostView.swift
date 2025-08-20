import SwiftUI

struct LeaderboardHostView: View {
    @EnvironmentObject var store: AppStore
    let initialTenant: String?
    let initialTeam: String?
    
    @State private var selectedTenant: String?
    @State private var selectedTeam: String?
    @State private var selectedPeriod: LeaderboardPeriod = .season
    @State private var showGlobal = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    enum LeaderboardPeriod: String, CaseIterable {
        case week = "week"
        case month = "month" 
        case season = "season"
        
        var displayName: String {
            switch self {
            case .week: return "Week"
            case .month: return "Maand"
            case .season: return "Seizoen"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let tenantSlug = selectedTenant, let tenant = store.model.tenants[tenantSlug] {
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 24)
                        
                        // Header
                        VStack(spacing: 8) {
                            Text("LEADERBOARD")
                                .font(KKFont.heading(24))
                                .fontWeight(.regular)
                                .kerning(-1.0)
                                .foregroundStyle(KKTheme.textPrimary)
                            Text("Bekijk de ranglijst van teams")
                                .font(KKFont.title(16))
                                .foregroundStyle(KKTheme.textSecondary)
                        }
                        .multilineTextAlignment(.center)
                        
                        // Period selector
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                ForEach(LeaderboardPeriod.allCases, id: \.self) { period in
                                    Button(action: { 
                                        selectedPeriod = period
                                        loadLeaderboard(for: tenant.slug)
                                    }) {
                                        Text(period.displayName)
                                            .font(KKFont.body(14))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(selectedPeriod == period ? KKTheme.accent : KKTheme.surfaceAlt)
                                            .foregroundColor(selectedPeriod == period ? .white : KKTheme.textPrimary)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            

                        }
                        .padding(.horizontal, 24)
                        
                        // Content
                        if isLoading {
                            ProgressView()
                                .padding(.vertical, 32)
                        } else if let error = errorMessage {
                            ErrorView(message: error, onRetry: { 
                                loadLeaderboard(for: tenant.slug)
                            })
                        } else if let leaderboardData = store.leaderboards[tenant.slug] {
                            LocalLeaderboardView(leaderboard: leaderboardData, highlightedTeamId: selectedTeam)
                        }
                        
                        Spacer(minLength: 24)
                    }
                }
                .refreshable {
                    if let tenantSlug = selectedTenant {
                        store.refreshLeaderboard(for: tenantSlug, period: selectedPeriod.rawValue, teamId: selectedTeam)
                    }
                }
                .onAppear {
                    if selectedTenant == nil {
                        selectedTenant = tenant.slug
                    }
                    loadLeaderboard(for: tenant.slug)
                }
            } else {
                // Show leaderboard welcome page
                LeaderboardWelcomeView(
                    onTenantSelected: { tenantSlug in
                        selectedTenant = tenantSlug
                        showGlobal = false
                    }
                )
                .environmentObject(store)
            }
        }
        .onAppear {
            // Set initial values from parameters
            if selectedTenant == nil {
                selectedTenant = initialTenant
            }
            if selectedTeam == nil {
                selectedTeam = initialTeam
            }
        }
    }
    
    private func loadLeaderboard(for tenantSlug: String) {
        isLoading = true
        errorMessage = nil
        
        // Use AppStore for consistent data management
        store.refreshLeaderboard(for: tenantSlug, period: selectedPeriod.rawValue, teamId: selectedTeam)
        
        // Check if data loaded successfully after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if store.leaderboards[tenantSlug] != nil {
                isLoading = false
                errorMessage = nil
            } else {
                isLoading = false
                errorMessage = "Kon leaderboard niet laden"
            }
        }
    }
    
    // MARK: - Error Formatting
    private func formatErrorMessage(_ error: Error, context: String) -> String {
        let nsError = error as NSError
        
        // Check if it's a user-friendly error from BackendClient
        if nsError.domain == "Backend" && !nsError.localizedDescription.isEmpty {
            return nsError.localizedDescription
        }
        
        // Fallback for other errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "Geen internetverbinding beschikbaar"
            case NSURLErrorTimedOut:
                return "Verbinding met server is verlopen"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return "Kan geen verbinding maken met de server"
            case NSURLErrorNetworkConnectionLost:
                return "Netwerkverbinding is verbroken"
            default:
                return "Netwerkfout opgetreden"
            }
        }
        
        // Generic fallback
        return "Er is een fout opgetreden bij het laden van \(context)"
    }
}

// MARK: - Welcome View
private struct LeaderboardWelcomeView: View {
    @EnvironmentObject var store: AppStore
    let onTenantSelected: (String) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 24)
                
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(KKTheme.accent)
                    
                    VStack(spacing: 8) {
                        Text("LEADERBOARD")
                            .font(KKFont.heading(28))
                            .fontWeight(.regular)
                            .kerning(-1.0)
                            .foregroundStyle(KKTheme.textPrimary)
                        Text("Bekijk de ranglijst van teams")
                            .font(KKFont.title(16))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                }
                
                // Instructions based on user state
                if store.model.tenants.isEmpty {
                    // No tenants - guide to add one
                    VStack(spacing: 16) {
                        Text("Geen verenigingen")
                            .font(KKFont.title(20))
                            .foregroundStyle(KKTheme.textPrimary)
                        
                        Text("Om de leaderboard te bekijken moet je eerst een vereniging toevoegen.")
                            .font(KKFont.body(14))
                            .foregroundStyle(KKTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        Button("Team toevoegen") {
                            store.startNewEnrollment()
                        }
                        .buttonStyle(KKPrimaryButton())
                    }
                    .kkCard()
                    .padding(.horizontal, 24)
                } else {
                    // Has tenants - guide to select one
                    VStack(spacing: 16) {
                        Text("Selecteer een vereniging")
                            .font(KKFont.title(20))
                            .foregroundStyle(KKTheme.textPrimary)
                        
                        Text("Op zoek naar de leaderboard van je vereniging? Selecteer eerst een vereniging om de ranglijst te bekijken.")
                            .font(KKFont.body(14))
                            .foregroundStyle(KKTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        // Show available tenants as buttons
                        LazyVStack(spacing: 8) {
                            ForEach(Array(store.model.tenants.values.sorted(by: { $0.name < $1.name })), id: \.slug) { tenant in
                                Button(action: {
                                    onTenantSelected(tenant.slug)
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(tenant.name)
                                                .font(KKFont.title(16))
                                                .foregroundStyle(KKTheme.textPrimary)
                                            Text("\(tenant.teams.count) team\(tenant.teams.count == 1 ? "" : "s")")
                                                .font(KKFont.body(12))
                                                .foregroundStyle(KKTheme.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "trophy")
                                            .foregroundStyle(KKTheme.accent)
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(KKTheme.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(KKTheme.surfaceAlt)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .kkCard()
                    .padding(.horizontal, 24)
                }
                
                // Info section
                VStack(spacing: 16) {
                    Text("Over de leaderboard")
                        .font(KKFont.title(18))
                        .foregroundStyle(KKTheme.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(
                            icon: "clock.fill",
                            title: "Punten per uur",
                            description: "Teams krijgen punten voor elke dienst die ze draaien"
                        )
                        
                        InfoRow(
                            icon: "calendar",
                            title: "Verschillende periodes",
                            description: "Bekijk rankings per week, maand of seizoen"
                        )
                        
                        InfoRow(
                            icon: "arrow.up.arrow.down",
                            title: "Positionering",
                            description: "Zie hoe teams stijgen of dalen in de ranglijst"
                        )
                    }
                }
                .kkCard()
                .padding(.horizontal, 24)
                
                Spacer(minLength: 24)
            }
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(KKTheme.accent)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KKFont.body(14))
                    .fontWeight(.medium)
                    .foregroundStyle(KKTheme.textPrimary)
                Text(description)
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
            }
        }
    }
}

// MARK: - Local Leaderboard View
private struct LocalLeaderboardView: View {
    let leaderboard: LeaderboardData
    let highlightedTeamId: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Club info header
            if let clubName = leaderboard.clubName {
                HStack(spacing: 12) {
                    // Club logo placeholder or actual logo
                    AsyncImage(url: leaderboard.clubLogoUrl.flatMap(URL.init)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "building.2")
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    .frame(width: 32, height: 32)
                    .background(KKTheme.surfaceAlt)
                    .cornerRadius(6)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clubName)
                            .font(KKFont.title(16))
                            .foregroundStyle(KKTheme.textPrimary)
                        Text("\(leaderboard.period.capitalized) ranglijst")
                            .font(KKFont.body(12))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            
            // Teams list
            LazyVStack(spacing: 8) {
                ForEach(Array(leaderboard.teams.enumerated()), id: \.element.id) { index, team in
                    TeamRowView(
                        team: team,
                        isHighlighted: highlightedTeamId != nil && team.id == highlightedTeamId,
                        isLocal: true
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Team Row Views
private struct TeamRowView: View {
    let team: LeaderboardTeam
    let isHighlighted: Bool
    let isLocal: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank
            ZStack {
                Circle()
                    .fill(rankColor)
                    .frame(width: 32, height: 32)
                Text("\(team.rank)")
                    .font(KKFont.body(14))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }
            
            // Team info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(team.name)
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textPrimary)
                    if let code = team.code {
                        Text("(\(code))")
                            .font(KKFont.body(12))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                }
                
                HStack(spacing: 16) {
                    Text("\(team.points) punten")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                    
                    Text("\(String(format: "%.1f", team.totalHours)) uur")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                }
            }
            
            Spacer()
            
            // Position change indicator
            if team.positionChange != 0 {
                HStack(spacing: 4) {
                    Image(systemName: team.positionChange > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption)
                    Text("\(abs(team.positionChange))")
                        .font(KKFont.body(10))
                }
                .foregroundColor(team.positionChange > 0 ? .green : .red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHighlighted ? KKTheme.accent.opacity(0.1) : KKTheme.surfaceAlt)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? KKTheme.accent : Color.clear, lineWidth: 2)
        )
    }
    
    private var rankColor: Color {
        switch team.rank {
        case 1: return Color.yellow
        case 2: return Color.gray
        case 3: return Color.orange
        default: return KKTheme.accent
        }
    }
}

// MARK: - Error View
private struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    private var errorType: ErrorType {
        if message.contains("internetverbinding") || message.contains("Netwerkfout") {
            return .network
        } else if message.contains("server") || message.contains("Serverfout") {
            return .server
        } else if message.contains("afgemeld") || message.contains("toegang") {
            return .permission
        } else {
            return .generic
        }
    }
    
    private enum ErrorType {
        case network, server, permission, generic
        
        var icon: String {
            switch self {
            case .network: return "wifi.exclamationmark"
            case .server: return "server.rack"
            case .permission: return "lock.circle"
            case .generic: return "exclamationmark.triangle"
            }
        }
        
        var title: String {
            switch self {
            case .network: return "Verbindingsprobleem"
            case .server: return "Serverfout"
            case .permission: return "Geen toegang"
            case .generic: return "Fout opgetreden"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: errorType.icon)
                .font(.system(size: 48))
                .foregroundStyle(errorType == .permission ? Color.orange : KKTheme.textSecondary)
            
            VStack(spacing: 8) {
                Text(errorType.title)
                    .font(KKFont.title(18))
                    .foregroundStyle(KKTheme.textPrimary)
                Text(message)
                    .font(KKFont.body(14))
                    .foregroundStyle(KKTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            if errorType != .permission {
                Button("Opnieuw proberen", action: onRetry)
                    .buttonStyle(KKSecondaryButton())
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
}
