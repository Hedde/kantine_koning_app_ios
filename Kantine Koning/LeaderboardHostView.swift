import SwiftUI

struct LeaderboardHostView: View {
    @EnvironmentObject var store: AppStore
    let initialTenant: String?
    let initialTeam: String?
    let showingInfo: Bool
    let onInfoToggle: (Bool) -> Void
    
    @State private var selectedTenant: String?
    @State private var selectedTeam: String?
    @State private var selectedPeriod: LeaderboardPeriod = .season
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingMenu = true  // Start with menu when no tenant selected
    
    enum LeaderboardPeriod: String, CaseIterable {
        case week = "week"
        case month = "month" 
        case season = "season"
        
        var displayName: String {
            switch self {
            case .week: return "Deze week"
            case .month: return "Deze maand"
            case .season: return "Dit seizoen"
            }
        }
        
        var headerText: String {
            let today = Date()
            let calendar = Calendar.current
            
            switch self {
            case .week:
                let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "nl_NL")
                formatter.dateFormat = "d MMM"
                let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? today
                return "Week \(calendar.component(.weekOfYear, from: today)) (\(formatter.string(from: weekStart)) - \(formatter.string(from: weekEnd)))"
            case .month:
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "nl_NL")
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: today)
            case .season:
                let currentMonth = calendar.component(.month, from: today)
                let currentYear = calendar.component(.year, from: today)
                let year = currentMonth >= 8 ? currentYear : currentYear - 1
                return "Seizoen \(year)-\(year + 1)"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showingInfo {
                LeaderboardInfoView()
            } else if showingMenu {
                LeaderboardMenuView(
                    tenants: Array(store.model.tenants.values.sorted(by: { $0.name < $1.name })),
                    onNationalSelected: {
                        showingMenu = false
                        selectedTenant = "global"  // Special marker for global
                        loadGlobalLeaderboard()
                    },
                    onTenantSelected: { tenantSlug in
                        showingMenu = false
                        selectedTenant = tenantSlug
                        loadLeaderboard(for: tenantSlug)
                    }
                )
            } else if selectedTenant == "global" {
                // Global leaderboard view
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 24)
                        
                        // Header for global
                        VStack(spacing: 8) {
                            Text("KANTINE KONING")
                                .font(KKFont.heading(24))
                                .fontWeight(.regular)
                                .kerning(-1.0)
                                .foregroundStyle(KKTheme.textPrimary)
                            Text("Nationaal Leaderboard")
                                .font(KKFont.title(16))
                                .foregroundStyle(KKTheme.textSecondary)
                        }
                        .multilineTextAlignment(.center)
                        
                        // Period header
                        Text(selectedPeriod.headerText)
                            .font(KKFont.title(16))
                            .foregroundStyle(KKTheme.textSecondary)
                            .multilineTextAlignment(.center)
                        
                        // Period selector
                        HStack(spacing: 8) {
                            ForEach(LeaderboardPeriod.allCases, id: \.self) { period in
                                Button(action: { 
                                    selectedPeriod = period
                                    loadGlobalLeaderboard()
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
                        .padding(.horizontal, 24)
                        
                        // Content
                        if isLoading {
                            ProgressView()
                                .padding(.vertical, 32)
                        } else if let error = errorMessage {
                            ErrorView(message: error, onRetry: loadGlobalLeaderboard)
                        } else if let globalData = store.globalLeaderboard {
                            GlobalLeaderboardView(
                                leaderboard: globalData, 
                                highlightedTeamCodes: Set(store.model.tenants.values.flatMap { $0.teams.map { $0.id } })
                            )
                        }
                        
                        Spacer(minLength: 24)
                    }
                }
                .refreshable {
                    loadGlobalLeaderboard()
                }
                .onAppear {
                    loadGlobalLeaderboard()
                }
            } else if let tenantSlug = selectedTenant, let tenant = store.model.tenants[tenantSlug] {
                ScrollView {
                    VStack(spacing: 24) {
                        Spacer(minLength: 24)
                        
                        // Header with club info
                        VStack(spacing: 16) {
                            // Club logo
                            AsyncImage(url: store.tenantInfo[tenant.slug]?.clubLogoUrl.flatMap(URL.init)) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(KKTheme.accent)
                            }
                            .frame(width: 48, height: 48)
                            .cornerRadius(8)
                            
                            // Title and subtitle
                            VStack(spacing: 8) {
                                Text(tenant.name.uppercased())
                                    .font(KKFont.heading(24))
                                    .fontWeight(.regular)
                                    .kerning(-1.0)
                                    .foregroundStyle(KKTheme.textPrimary)
                                Text("Leaderboard")
                                    .font(KKFont.title(16))
                                    .foregroundStyle(KKTheme.textSecondary)
                            }
                            .multilineTextAlignment(.center)
                        }
                        
                        // Period header
                        Text(selectedPeriod.headerText)
                            .font(KKFont.title(16))
                            .foregroundStyle(KKTheme.textSecondary)
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
                            LocalLeaderboardView(
                                leaderboard: leaderboardData, 
                                highlightedTeamCodes: Set(tenant.teams.map { $0.id })  // These are codes, not IDs
                            )
                            .onAppear {
                                let enrolledTeamCodes = Set(tenant.teams.map { $0.id })  // These are actually codes
                                let leaderboardTeamIds = leaderboardData.teams.map { $0.id }
                                
                                print("[LeaderboardView] 🎯 Enrolled team codes: \(enrolledTeamCodes)")
                                print("[LeaderboardView] 📊 Leaderboard team IDs: \(leaderboardTeamIds)")
                                
                                // Debug: show team mapping from leaderboard response
                                for team in leaderboardData.teams {
                                    if enrolledTeamCodes.contains(team.code ?? "") {
                                        print("[LeaderboardView] 🔗 HIGHLIGHTED: \(team.name) (code: \(team.code ?? "nil")) rank \(team.rank)")
                                    }
                                }
                            }
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
                // Show club selection for leaderboard
                LeaderboardWelcomeView(
                    onTenantSelected: { tenantSlug in
                        selectedTenant = tenantSlug
                        showingMenu = false
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
            
            // Show menu if no tenant initially selected and not showing info
            showingMenu = (initialTenant == nil && !showingInfo)
        }
    }
    
    private func loadLeaderboard(for tenantSlug: String) {
        isLoading = true
        errorMessage = nil
        
        // Use AppStore for consistent data management
        store.refreshLeaderboard(for: tenantSlug, period: selectedPeriod.rawValue, teamId: selectedTeam)
        
        // Check if data loaded successfully after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("[LeaderboardView] 🔍 Checking if data loaded for tenant: \(tenantSlug)")
            print("[LeaderboardView] 🔍 Available leaderboards: \(Array(store.leaderboards.keys))")
            
            if let leaderboard = store.leaderboards[tenantSlug] {
                print("[LeaderboardView] ✅ Found leaderboard data with \(leaderboard.teams.count) teams")
                isLoading = false
                errorMessage = nil
            } else {
                print("[LeaderboardView] ❌ No leaderboard data found")
                isLoading = false
                errorMessage = "Kon leaderboard niet laden"
            }
        }
    }
    
    private func loadGlobalLeaderboard() {
        isLoading = true
        errorMessage = nil
        
        // Use first tenant for authentication
        guard let firstTenant = store.model.tenants.values.first else {
            errorMessage = "Geen verenigingen beschikbaar"
            isLoading = false
            return
        }
        
        let client = BackendClient()
        // Use any available tenant token for global leaderboard (read-only operation)
        client.authToken = store.model.tenants.values.first?.signedDeviceToken
        
        client.fetchGlobalLeaderboard(
            tenant: firstTenant.slug,
            period: selectedPeriod.rawValue,
            teamId: selectedTeam
        ) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let leaderboard):
                    store.globalLeaderboard = GlobalLeaderboardData(
                        period: leaderboard.period,
                        teams: leaderboard.teams.map { teamEntry in
                            GlobalLeaderboardTeam(
                                id: teamEntry.team.id,
                                name: teamEntry.team.name,
                                code: teamEntry.team.code,
                                rank: teamEntry.rank,
                                points: teamEntry.points,
                                totalHours: teamEntry.totalHours,
                                recentChange: teamEntry.recentChange,
                                positionChange: teamEntry.positionChange,
                                highlighted: teamEntry.highlighted,
                                clubName: teamEntry.club.name,
                                clubSlug: teamEntry.club.slug,
                                clubLogoUrl: nil  // Logo URLs now come from /tenants API
                            )
                        },
                        lastUpdated: Date()
                    )
                    print("[Leaderboard] ✅ Loaded global leaderboard: \(leaderboard.teams.count) teams")
                case .failure(let error):
                    if (error as NSError).code == 403 {
                        errorMessage = "Deze vereniging heeft zich afgemeld voor de globale leaderboard."
                    } else {
                        errorMessage = self.formatErrorMessage(error, context: "globale leaderboard")
                    }
                    print("[Leaderboard] ❌ Failed to load global leaderboard: \(error)")
                }
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

// MARK: - Menu View
private struct LeaderboardMenuView: View {
    let tenants: [DomainModel.Tenant]
    let onNationalSelected: () -> Void
    let onTenantSelected: (String) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 24)
                
                // Header
                VStack(spacing: 8) {
                    Text("LEADERBOARD")
                        .font(KKFont.heading(28))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text("Kies wat je wilt bekijken")
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                
                // Menu options
                VStack(spacing: 16) {
                    // National leaderboard option
                    Button(action: onNationalSelected) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Image(systemName: "trophy.fill")
                                        .foregroundColor(KKTheme.accent)
                                    Text("Nationaal Leaderboard")
                                        .font(KKFont.title(18))
                                        .foregroundStyle(KKTheme.textPrimary)
                                }
                                Text("Ranglijst van alle verenigingen")
                                    .font(KKFont.body(14))
                                    .foregroundStyle(KKTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(KKTheme.textSecondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(KKTheme.surfaceAlt)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    // Individual tenant options
                    ForEach(tenants, id: \.slug) { tenant in
                        Button(action: { onTenantSelected(tenant.slug) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "trophy.fill")
                                            .foregroundColor(KKTheme.accent)
                                        Text(tenant.name)
                                            .font(KKFont.title(18))
                                            .foregroundStyle(KKTheme.textPrimary)
                                    }
                                    Text("\(tenant.teams.count) team\(tenant.teams.count == 1 ? "" : "s")")
                                        .font(KKFont.body(14))
                                        .foregroundStyle(KKTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(KKTheme.textSecondary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(KKTheme.surfaceAlt)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                
                Spacer(minLength: 24)
            }
        }
    }
}

// MARK: - Info View
private struct LeaderboardInfoView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 24)
                
                // Header
                VStack(spacing: 8) {
                    Text("OVER DE LEADERBOARD")
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text("Hoe werkt het puntensysteem?")
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                
                // Info sections
                VStack(spacing: 24) {
                    InfoSectionView(
                        icon: "clock.fill",
                        title: "Punten per uur",
                        description: "Teams krijgen 1 punt voor elk uur dat ze dienst draaien. Hoe meer diensten, hoe meer punten!"
                    )
                    
                    InfoSectionView(
                        icon: "calendar",
                        title: "Verschillende periodes",
                        description: "Bekijk rankings per week, maand of seizoen. Zo zie je zowel recente prestaties als langere trends."
                    )
                    
                    InfoSectionView(
                        icon: "arrow.up.arrow.down",
                        title: "Positionering",
                        description: "Groene pijltjes betekenen dat een team is gestegen, rode pijltjes betekenen gedaald in de ranglijst."
                    )
                    
                    InfoSectionView(
                        icon: "trophy.fill",
                        title: "Ranglijsten",
                        description: "Er zijn zowel nationale ranglijsten (alle clubs) als club-specifieke ranglijsten (alleen teams van jouw club)."
                    )
                }
                .padding(.horizontal, 24)
                
                Spacer(minLength: 24)
            }
        }
    }
}

private struct InfoSectionView: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(KKTheme.accent)
                    .frame(width: 32)
                
                Text(title)
                    .font(KKFont.title(18))
                    .foregroundStyle(KKTheme.textPrimary)
                
                Spacer()
            }
            
            Text(description)
                .font(KKFont.body(14))
                .foregroundStyle(KKTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .kkCard()
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
                        
                        Text("Ga terug naar het hoofdmenu en klik op het trophy icoon om een leaderboard te bekijken.")
                            .font(KKFont.body(14))
                            .foregroundStyle(KKTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .kkCard()
                    .padding(.horizontal, 24)
                }
                
                Spacer(minLength: 24)
            }
        }
    }
}

// MARK: - Local Leaderboard View
private struct LocalLeaderboardView: View {
    let leaderboard: LeaderboardData
    let highlightedTeamCodes: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Teams list
            LazyVStack(spacing: 8) {
                ForEach(Array(leaderboard.teams.enumerated()), id: \.element.id) { index, team in
                    TeamRowView(
                        team: team,
                        isHighlighted: highlightedTeamCodes.contains(team.code ?? ""),
                        isLocal: true
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Global Leaderboard View
private struct GlobalLeaderboardView: View {
    let leaderboard: GlobalLeaderboardData
    let highlightedTeamCodes: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Teams list with club logos
            LazyVStack(spacing: 8) {
                ForEach(Array(leaderboard.teams.enumerated()), id: \.element.id) { index, team in
                    GlobalTeamRowView(
                        team: team,
                        isHighlighted: highlightedTeamCodes.contains(team.code ?? "")
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Global Team Row
private struct GlobalTeamRowView: View {
    let team: GlobalLeaderboardTeam
    let isHighlighted: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank
            ZStack {
                Circle()
                    .fill(isHighlighted ? KKTheme.accent : rankColor)
                    .frame(width: 32, height: 32)
                if isHighlighted {
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                        .frame(width: 32, height: 32)
                }
                Text("\(team.rank)")
                    .font(KKFont.body(14))
                    .fontWeight(isHighlighted ? .bold : .medium)
                    .foregroundColor(.white)
            }
            
            // Club logo
            AsyncImage(url: store.tenantInfo[team.clubSlug]?.clubLogoUrl.flatMap(URL.init)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "building.2")
                    .foregroundStyle(KKTheme.textSecondary)
            }
            .frame(width: 32, height: 32)
            .cornerRadius(6)
            
            // Team and club info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(team.name)
                        .font(KKFont.title(16))
                        .fontWeight(isHighlighted ? .bold : .regular)
                        .foregroundStyle(isHighlighted ? KKTheme.accent : KKTheme.textPrimary)
                    if let code = team.code {
                        Text("(\(code))")
                            .font(KKFont.body(12))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    if isHighlighted {
                        Text("JIJ")
                            .font(KKFont.body(10))
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(KKTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 16) {
                    Text(team.clubName)
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                    
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
        .background(highlightedBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? Color.orange : Color.clear, lineWidth: 1)  // Dunne border
        )
        .shadow(color: isHighlighted ? Color.orange.opacity(0.4) : Color.clear, radius: 6, x: 0, y: 2)
        .scaleEffect(isHighlighted ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }
    
    private var highlightedBackground: Color {
        if isHighlighted {
            return Color.orange.opacity(0.25)  // Test kleur
        } else {
            return KKTheme.surfaceAlt
        }
    }
    
    private var rankColor: Color {
        if isHighlighted {
            return KKTheme.accent
        }
        switch team.rank {
        case 1: return Color.yellow
        case 2: return Color.gray
        case 3: return Color.orange
        default: return KKTheme.accent
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
                    .fill(isHighlighted ? KKTheme.accent : rankColor)
                    .frame(width: 32, height: 32)
                if isHighlighted {
                    Circle()
                        .stroke(Color.white, lineWidth: 1)
                        .frame(width: 32, height: 32)
                }
                Text("\(team.rank)")
                    .font(KKFont.body(14))
                    .fontWeight(isHighlighted ? .bold : .medium)
                    .foregroundColor(.white)
            }
            
            // Team info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(team.name)
                        .font(KKFont.title(16))
                        .fontWeight(isHighlighted ? .bold : .regular)
                        .foregroundStyle(isHighlighted ? KKTheme.accent : KKTheme.textPrimary)
                    if let code = team.code {
                        Text("(\(code))")
                            .font(KKFont.body(12))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    if isHighlighted {
                        Text("JIJ")
                            .font(KKFont.body(10))
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(KKTheme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(4)
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
        .background(isHighlighted ? Color.orange.opacity(0.25) : KKTheme.surfaceAlt)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? Color.orange : Color.clear, lineWidth: 1)  // Dunne border
        )
        .shadow(color: isHighlighted ? Color.orange.opacity(0.4) : Color.clear, radius: 6, x: 0, y: 2)
        .scaleEffect(isHighlighted ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }
    
    private var rankColor: Color {
        if isHighlighted {
            return KKTheme.accent
        }
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
