import SwiftUI

struct SeasonOverviewView: View {
    let tenant: DomainModel.Tenant
    let teamId: String?
    @EnvironmentObject var store: AppStore
    
    // Convenience initializer for backward compatibility
    init(tenant: DomainModel.Tenant) {
        self.tenant = tenant
        self.teamId = nil
    }
    
    // New initializer with specific team
    init(tenant: DomainModel.Tenant, teamId: String) {
        self.tenant = tenant
        self.teamId = teamId
    }
    @State private var showConfetti = false
    @State private var confettiTrigger = 0
    @State private var showResetConfirmation = false
    @State private var selectedTeam: DomainModel.Team?
    @State private var availableTeams: [DomainModel.Team] = []
    @State private var seasonSummary: SeasonSummaryResponse?
    @State private var isLoadingApiData = false
    @State private var isUsingLocalCache = false
    
    // Computed property for season stats - either from API or local fallback
    private var seasonStats: SeasonStats {
        if let summary = seasonSummary {
            return summary.seasonStats.toSeasonStats(for: tenant)
        } else {
            // Fallback to local calculation
            return SeasonStats.calculate(from: store.upcoming, for: tenant.slug, with: tenant)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with confetti overlay (consistent with app style)
                VStack(spacing: 8) {
                    Text("SEIZOEN AFGELOPEN")
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text(tenant.name)
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                    
                    // Show selected team info (always visible when team is selected)
                    if let team = selectedTeam {
                        VStack(spacing: 4) {
                            Text("Jouw team")
                                .font(KKFont.body(12))
                                .foregroundStyle(KKTheme.textSecondary)
                            HStack(spacing: 8) {
                                Text(team.name)
                                    .font(KKFont.title(18))
                                    .fontWeight(.medium)
                                    .foregroundStyle(KKTheme.accent)
                                if let code = team.code {
                                    Text("(\(code))")
                                        .font(KKFont.body(14))
                                        .foregroundStyle(KKTheme.textSecondary)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    // Team selection picker (only if multiple teams and no specific team provided)
                    if teamId == nil && availableTeams.count > 1 {
                        TeamSelectionPicker(
                            teams: availableTeams,
                            selectedTeam: $selectedTeam,
                            isLoading: isLoadingApiData
                        )
                        .padding(.top, 8)
                    }
                    
                    // Note: No data source indicator for season summaries - we always use API or show nothing
                }
                .multilineTextAlignment(.center)
                .overlay(ConfettiView(trigger: confettiTrigger).allowsHitTesting(false))
                
                // Main statistics card
                SeasonStatsCard(stats: seasonStats)
                
                // Achievements card
                if !seasonStats.achievements.isEmpty {
                    AchievementsCard(achievements: seasonStats.achievements)
                }
                
                // Thank you card
                ThankYouCard()
                
                // Reset button card
                ResetTenantCard(tenant: tenant) {
                    showResetConfirmation = true
                }
                
                Spacer(minLength: 100)
            }
        }
        .safeAreaInset(edge: .top) {
            // Fixed banner positioned under navigation
            TenantBannerView(tenantSlug: tenant.slug)
                .environmentObject(store)
                .padding(.bottom, 12)
                .background(KKTheme.surface)
        }
        .background(KKTheme.surface)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Trigger confetti celebration
            triggerConfetti()
            // Load teams and season summary
            loadTeamsAndSeasonSummary()
        }
        .onChange(of: selectedTeam) { _, newTeam in
            if let team = newTeam {
                loadSeasonSummary(for: team)
            }
        }
        .alert("Seizoen Data Verwijderen", isPresented: $showResetConfirmation) {
            Button("Annuleren", role: .cancel) { }
            Button("Verwijderen", role: .destructive) {
                resetTenant()
            }
        } message: {
            Text("Dit verwijdert alle gegevens van \(tenant.name) uit de app. Deze actie kan niet ongedaan worden gemaakt.")
        }
    }
    
    private func triggerConfetti() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { 
            showConfetti = true 
        }
        confettiTrigger += 1
        
        // Add iPhone vibration for extra celebration
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Second burst after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            confettiTrigger += 1
            let lightFeedback = UIImpactFeedbackGenerator(style: .light)
            lightFeedback.impactOccurred()
        }
    }
    
    private func resetTenant() {
        Logger.userInteraction("Reset Tenant", target: "SeasonOverview", context: ["tenant": tenant.slug])
        store.removeSeasonEndedTenant(tenant.slug)
    }
    
    // MARK: - Season Summary Loading
    
    private func loadTeamsAndSeasonSummary() {
        // If specific teamId is provided, use that team directly
        if let teamId = teamId,
           let specificTeam = tenant.teams.first(where: { $0.id == teamId }) {
            availableTeams = [specificTeam]
            selectedTeam = specificTeam
            loadSeasonSummary(for: specificTeam)
            return
        }
        
        // Otherwise, find all teams user was enrolled for in this tenant (legacy behavior)
        let enrolledTeams = store.model.enrollments.values
            .filter { $0.tenantSlug == tenant.slug }
            .flatMap { enrollment -> [DomainModel.Team] in
                return tenant.teams.filter { team in
                    enrollment.teams.contains(team.id)
                }
            }
        
        // Remove duplicates by filtering unique team IDs
        var uniqueTeams: [DomainModel.Team] = []
        var seenTeamIds: Set<String> = []
        
        for team in enrolledTeams {
            if !seenTeamIds.contains(team.id) {
                uniqueTeams.append(team)
                seenTeamIds.insert(team.id)
            }
        }
        
        availableTeams = uniqueTeams
        selectedTeam = availableTeams.first
        
        if let firstTeam = selectedTeam {
            loadSeasonSummary(for: firstTeam)
        }
    }
    
    private func loadSeasonSummary(for team: DomainModel.Team) {
        guard !isLoadingApiData else { return }
        
        isLoadingApiData = true
        let teamIdentifier = team.code ?? team.id
        let backend = BackendClient()
        
        Logger.debug("Loading season summary for team: \(team.name) (\(teamIdentifier))")
        
        backend.fetchSeasonSummary(
            tenantSlug: tenant.slug,
            teamCode: teamIdentifier
        ) { result in
            DispatchQueue.main.async {
                self.isLoadingApiData = false
                
                switch result {
                case .success(let summary):
                    Logger.success("Season summary loaded from API")
                    self.seasonSummary = summary
                    self.isUsingLocalCache = false
                    
                case .failure(let error):
                    Logger.error("Season summary API failed: \(error)")
                    
                    // Use local fallback
                    self.useLocalSeasonSummary(for: team)
                }
            }
        }
    }
    
    private func useLocalSeasonSummary(for team: DomainModel.Team) {
        Logger.info("Using local season summary fallback for team: \(team.name)")
        
        // Clear API summary to force use of local calculation
        seasonSummary = nil
        isUsingLocalCache = true
    }
}

// MARK: - Season Stats Card
struct SeasonStatsCard: View {
    let stats: SeasonStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Jouw Prestaties")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    icon: "clock.fill",
                    title: "Totaal Uren",
                    value: String(format: "%.1f", stats.totalHours),
                    subtitle: "uur gewerkt"
                )
                
                StatCard(
                    icon: "calendar.badge.checkmark",
                    title: "Diensten",
                    value: "\(stats.totalShifts)",
                    subtitle: "voltooid"
                )
                
                if let location = stats.favoriteLocation {
                    StatCard(
                        icon: "location.fill",
                        title: "Favoriete Locatie",
                        value: location,
                        subtitle: "meest gebruikt"
                    )
                }
                
                if let month = stats.mostActiveMonth {
                    StatCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Drukste Maand",
                        value: month,
                        subtitle: "meeste diensten"
                    )
                }
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(KKTheme.accent)
            
            Text(value)
                .font(KKFont.title(16))
                .foregroundStyle(KKTheme.textPrimary)
                .multilineTextAlignment(.center)
            
            Text(title)
                .font(KKFont.body(10))
                .foregroundStyle(KKTheme.textSecondary)
                .multilineTextAlignment(.center)
            
            Text(subtitle)
                .font(KKFont.body(9))
                .foregroundStyle(KKTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(KKTheme.surfaceAlt)
        .cornerRadius(8)
    }
}

// MARK: - Achievements Card
struct AchievementsCard: View {
    let achievements: [Achievement]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Behaalde Prestaties")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            ForEach(achievements.indices, id: \.self) { index in
                AchievementRow(achievement: achievements[index])
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

struct AchievementRow: View {
    let achievement: Achievement
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.icon)
                .font(.system(size: 20))
                .foregroundStyle(.yellow)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(KKFont.title(14))
                    .foregroundStyle(KKTheme.textPrimary)
                
                Text(achievement.description)
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Team Contributions Card
struct TeamContributionsCard: View {
    let contributions: [TeamContribution]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jouw Teams")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            ForEach(contributions.indices, id: \.self) { index in
                TeamContributionRow(contribution: contributions[index])
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

struct TeamContributionRow: View {
    let contribution: TeamContribution
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(contribution.teamName)
                .font(KKFont.title(14))
                .foregroundStyle(KKTheme.textPrimary)
            
            HStack {
                Text(String(format: "%.1f uur", contribution.hoursWorked))
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
                
                Text("•")
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
                
                Text("\(contribution.shiftsCompleted) diensten")
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Thank You Card
struct ThankYouCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bedankt!")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                
                Text("Bedankt voor je inzet dit seizoen!")
                    .font(KKFont.title(16))
                    .foregroundStyle(KKTheme.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text("Jouw vrijwilligerswerk heeft het verschil gemaakt. Tot volgend jaar!")
                    .font(KKFont.body(14))
                    .foregroundStyle(KKTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            .frame(maxWidth: .infinity)
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

// MARK: - Reset Tenant Card  
struct ResetTenantCard: View {
    let tenant: DomainModel.Tenant
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seizoen Data")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            Text("Verwijder alle gegevens van \(tenant.name) uit de app om ruimte te maken voor een nieuw seizoen.")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            Button(action: action) {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("Reset \(tenant.name)")
                        .font(KKFont.title(14))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(KKTheme.accent)
                .cornerRadius(8)
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

// MARK: - Team Selection Picker

struct TeamSelectionPicker: View {
    let teams: [DomainModel.Team]
    @Binding var selectedTeam: DomainModel.Team?
    let isLoading: Bool
    
    var body: some View {
        if teams.count > 1 {
            VStack(spacing: 4) {
                Text("Team")
                    .font(KKFont.body(10))
                    .foregroundStyle(KKTheme.textSecondary)
                
                Menu {
                    ForEach(teams, id: \.id) { team in
                        Button(action: {
                            selectedTeam = team
                        }) {
                            HStack {
                                Text(team.name)
                                if selectedTeam?.id == team.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .foregroundColor(KKTheme.accent)
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedTeam?.name ?? "Selecteer team")
                            .font(KKFont.title(14))
                            .foregroundStyle(KKTheme.textPrimary)
                        
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundStyle(KKTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(KKTheme.surfaceAlt)
                    .cornerRadius(8)
                }
                .disabled(isLoading)
            }
        }
    }
}

// MARK: - Data Source Indicator

struct DataSourceIndicator: View {
    let isLocal: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isLocal ? "wifi.slash" : "wifi")
                .font(.system(size: 10))
            Text(isLocal ? "Lokale data" : "Live data")
                .font(KKFont.body(10))
        }
        .foregroundStyle(isLocal ? .orange : .green)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isLocal ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
        .cornerRadius(4)
    }
}

#Preview {
    let sampleTenant = DomainModel.Tenant(
        slug: "demo",
        name: "Demo Sportclub",
        teams: [],
        signedDeviceToken: "sample_token",
        enrollments: [],
        seasonEnded: true
    )
    
    SeasonOverviewView(tenant: sampleTenant)
        .environmentObject(AppStore())
}
