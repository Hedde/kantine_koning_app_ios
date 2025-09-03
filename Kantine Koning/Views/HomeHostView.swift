import SwiftUI

struct HomeHostView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSettings = false
    @State private var showLeaderboard = false
    @State private var leaderboardShowingInfo = false
    @State private var selectedTenant: String? = nil
    @State private var selectedTeam: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main Content
                if showSettings {
                    SettingsViewInternal().environmentObject(store)
                } else if showLeaderboard {
                    LeaderboardHostView(
                        initialTenant: selectedTenant,
                        initialTeam: selectedTeam,
                        showingInfo: leaderboardShowingInfo,
                        onInfoToggle: { showingInfo in
                            leaderboardShowingInfo = showingInfo
                        }
                    ).environmentObject(store)
                } else if let tenantSlug = selectedTenant, let teamId = selectedTeam, let tenant = store.model.tenants[tenantSlug] {
                    // Team is selected - show appropriate view based on season status
                    if tenant.seasonEnded {
                        SeasonOverviewView(tenant: tenant, teamId: teamId)
                            .environmentObject(store)
                    } else {
                        TeamDienstenView(tenant: tenant, teamId: teamId).environmentObject(store)
                    }
                } else if let tenantSlug = selectedTenant, let tenant = store.model.tenants[tenantSlug] {
                    // Tenant selected but no team - always show team selection
                    if tenant.seasonEnded {
                        SeasonEndedTeamsView(tenant: tenant,
                                           onTeamSelected: { teamId in selectedTeam = teamId },
                                           onBack: { selectedTenant = nil })
                        .environmentObject(store)
                    } else {
                        // Normal accessible tenant -> show teams
                        TeamsView(tenant: tenant,
                                  onTeamSelected: { teamId in selectedTeam = teamId },
                                  onBack: { selectedTenant = nil })
                        .environmentObject(store)
                    }
                } else {
                    // Smart tenant selection logic
                    let allTenants = Array(store.model.tenants.values)
                    let accessibleTenants = allTenants.filter { $0.isAccessible }
                    
                    // If only ONE tenant total and it's season ended -> still show team selection
                    if allTenants.count == 1, let singleTenant = allTenants.first, singleTenant.seasonEnded {
                        SeasonEndedTeamsView(tenant: singleTenant,
                                           onTeamSelected: { teamId in 
                                               selectedTenant = singleTenant.slug
                                               selectedTeam = teamId 
                                           },
                                           onBack: { /* No back for single tenant */ })
                        .environmentObject(store)
                    } 
                    // If multiple tenants OR single accessible tenant -> show selection
                    else if allTenants.count > 1 || !accessibleTenants.isEmpty {
                        ClubsViewInternal(
                            onTenantSelected: { slug in
                                selectedTenant = slug
                                // Auto-select team when only one exists (for accessible tenants)
                                if let tenant = store.model.tenants[slug], tenant.isAccessible, tenant.teams.count == 1, let onlyTeam = tenant.teams.first {
                                    selectedTeam = onlyTeam.id
                                }
                                // Note: Season ended tenants will be handled by selectedTenant logic above
                            }
                        )
                        .environmentObject(store)
                    } 
                    // No tenants at all -> should not happen here
                    else {
                        EmptyView()
                    }
                }

                // Back navigation is handled by home button in navigation bar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KKTheme.surface.ignoresSafeArea())
            .onAppear {
                Logger.viewLifecycle("HomeHostView", event: "onAppear", details: "tenants: \(store.model.tenants.count)")
            }
            .onDisappear {
                Logger.viewLifecycle("HomeHostView", event: "onDisappear")
            }
            .onChange(of: store.model.tenants) { _, tenants in
                // Check if currently selected tenant became season ended
                if let selectedTenantSlug = selectedTenant,
                   let tenant = tenants[selectedTenantSlug],
                   tenant.seasonEnded {
                    Logger.auth("🔄 Selected tenant \(selectedTenantSlug) became season ended - clearing team selection")
                    selectedTeam = nil // This will trigger navigation to SeasonOverviewView
                }
            }
                            .safeAreaInset(edge: .top) {
                TopNavigationBar(
                    onHomeAction: {
                        Logger.userInteraction("Tap", target: "Home Button")
                        selectedTenant = nil
                        selectedTeam = nil
                        showSettings = false
                        showLeaderboard = false
                    },
                    onSettingsAction: { 
                        Logger.userInteraction("Tap", target: "Settings Button", context: ["current_state": showSettings ? "open" : "closed"])
                        showSettings.toggle()
                        showLeaderboard = false
                    },
                    onLeaderboardAction: {
                        Logger.userInteraction("Tap", target: "Leaderboard Button", context: ["current_state": showLeaderboard ? "open" : "closed"])
                        if !showLeaderboard {
                            showLeaderboard = true
                            showSettings = false
                            leaderboardShowingInfo = false
                            
                            // If current tenant is season ended, clear selection to force menu
                            if let tenantSlug = selectedTenant,
                               let tenant = store.model.tenants[tenantSlug],
                               tenant.seasonEnded {
                                Logger.debug("Clearing season ended tenant selection for leaderboard access")
                                // Note: Don't clear selectedTenant here, just let LeaderboardHostView handle it
                            }
                        } else {
                            // Toggle info when already in leaderboard
                            leaderboardShowingInfo.toggle()
                        }
                    },
                    isSettingsActive: showSettings,
                    showLeaderboard: showLeaderboard
                )
                .background(KKTheme.surface)
            }
        }
    }
}

// MARK: - Top Navigation Bar
private struct TopNavigationBar: View {
    let onHomeAction: () -> Void
    let onSettingsAction: () -> Void
    let onLeaderboardAction: () -> Void
    let isSettingsActive: Bool
    let showLeaderboard: Bool
    var body: some View {
        ZStack {
            // Background
            KKTheme.surface
            
            // Centered logo (always perfectly centered)
            BrandAssets.logoImage()
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
            
            // Left and right buttons overlay
            HStack {
                // Left side
                Button(action: onHomeAction) {
                    Image(systemName: "house.fill")
                        .font(.title2)
                        .foregroundColor(KKTheme.textSecondary)
                }
                
                Spacer()
                
                // Right side
                HStack(spacing: 12) {
                    if showLeaderboard {
                        // Question mark/X icon when in leaderboard
                        Button(action: onLeaderboardAction) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(KKTheme.textSecondary)
                        }
                    } else {
                        // Trophy icon when not in leaderboard
                        Button(action: onLeaderboardAction) {
                            Image(systemName: "trophy.fill")
                                .font(.title2)
                                .foregroundColor(KKTheme.textSecondary)
                        }
                    }
                    Button(action: onSettingsAction) {
                        Image(systemName: isSettingsActive ? "xmark.circle.fill" : "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(KKTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 56)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(KKTheme.surfaceAlt),
            alignment: .bottom
        )
    }
}

private struct NotificationPermissionCard: View {
    @EnvironmentObject var store: AppStore
    @State private var status: AppStore.NotificationStatus = .notDetermined
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schakel notificaties in")
                .font(.headline)
            Text("Ontvang updates over diensten en inschrijvingen.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("Sta toe") { request() }.buttonStyle(KKPrimaryButton())
                    .disabled(status == .authorized)
            }
        }
        .kkCard()
        .onAppear { store.getNotificationStatus { self.status = $0 } }
        .opacity(status == .authorized ? 0 : 1)
    }
    private func request() {
        store.configurePushNotifications()
        store.getNotificationStatus { self.status = $0 }
    }
}

private struct TeamsView: View {
    let tenant: DomainModel.Tenant
    let onTeamSelected: (String) -> Void
    let onBack: () -> Void
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                VStack(spacing: 8) {
                    Text("SELECTEER TEAM")
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text("Bij \(tenant.name)")
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                VStack(spacing: 8) {
                    ForEach(tenant.teams.sorted(by: { 
                        // Sort manager teams first, then by name
                        if $0.role != $1.role {
                            return $0.role == .manager && $1.role == .member
                        }
                        return $0.name < $1.name 
                    }), id: \.id) { team in
                        SwipeableRow(onTap: { onTeamSelected(team.id) }, onDelete: { store.removeTeam(team.id, from: tenant.slug) }) {
                            HStack(spacing: 16) {
                                // Club logo (same for all teams in this tenant)
                                CachedAsyncImage(url: (store.tenantInfo[tenant.slug]?.clubLogoUrl ?? tenant.clubLogoUrl).flatMap(URL.init)) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "building.2.fill")
                                        .foregroundStyle(KKTheme.accent)
                                }
                                .frame(width: 40, height: 40)
                                .cornerRadius(6)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                Text(team.name)
                                            .font(KKFont.title(18))
                                            .foregroundStyle(KKTheme.textPrimary)
                                        if team.role == .manager {
                                            Text("Manager")
                                                .font(KKFont.body(10))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(KKTheme.accent.opacity(0.12))
                                                .foregroundStyle(KKTheme.accent)
                                                .cornerRadius(6)
                                        }
                                    }
                                    Text(dienstCountText(for: team.id))
                                        .font(KKFont.body(14))
                                        .foregroundStyle(KKTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(KKTheme.textSecondary)
                                    .font(.title2)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(KKTheme.surfaceAlt)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 24)
            }
        }
    }
    private func dienstCountText(for teamId: String) -> String {
        // Find the team first to get both ID and code
        guard let team = tenant.teams.first(where: { $0.id == teamId }) else {
            return "Geen diensten"
        }
        
        // Match diensten using both team ID and team code (diensten use team codes as teamId)
        let count = store.upcoming.filter { dienst in
            guard dienst.tenantId == tenant.slug else { return false }
            // Match either by the team's ID or the team's code
            return dienst.teamId == team.id || dienst.teamId == team.code
        }.count
        
        return count == 0 ? "Geen diensten" : count == 1 ? "1 dienst" : "\(count) diensten"
    }
}

private struct DienstRow: View {
    let d: Dienst
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(d.tenantId).font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
                Text(d.status.capitalized).font(KKFont.title(16)).foregroundStyle(KKTheme.textPrimary)
                Text(d.startTime.formatted(date: .abbreviated, time: .shortened)).font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(KKTheme.textSecondary)
        }
        .padding(16)
        .background(KKTheme.surfaceAlt)
        .cornerRadius(12)
    }
}

private struct TeamDienstenView: View {
    let tenant: DomainModel.Tenant
    let teamId: String
    @EnvironmentObject var store: AppStore
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                VStack(spacing: 8) {
                    Text(teamDisplayName(teamId: teamId, in: tenant).uppercased())
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text("Aankomende diensten")
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                
                if diensten.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundStyle(KKTheme.textSecondary)
                        VStack(spacing: 8) {
                            Text("Geen diensten gevonden")
                                .font(KKFont.title(18))
                                .foregroundStyle(KKTheme.textPrimary)
                            Text("Er zijn momenteel geen aankomende diensten voor dit team.")
                                .font(KKFont.body(14))
                                .foregroundStyle(KKTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 32)
                } else {
                    VStack(spacing: 12) {
                                        ForEach(diensten) { d in
                    DienstCardView(dienstId: d.id, isManager: (tenant.teams.first{ $0.id == teamId }?.role == .manager))
                        .opacity(d.startTime < Date() ? 0.5 : 1.0)
                }
                    }
                    .padding(.horizontal, 16)
                }
                Spacer(minLength: 24)
            }
        }
        .refreshable { 
            store.refreshDiensten()
        }
        .background(KKTheme.surface.ignoresSafeArea())
    }
    
    private var diensten: [Dienst] {
        // Find the team first to get both ID and code
        guard let team = tenant.teams.first(where: { $0.id == teamId }) else {
            Logger.warning("❌ Team with ID '\(teamId)' not found in tenant '\(tenant.name)'")
            return []
        }
        
        // Match diensten using both team ID and team code (diensten use team codes as teamId)
        let filtered = store.upcoming.filter { dienst in
            guard dienst.tenantId == tenant.slug else { return false }
            // Match either by the team's ID or the team's code
            let matches = dienst.teamId == team.id || dienst.teamId == team.code
            if matches {
                Logger.debug("🎯 Found matching dienst: dienstTeamId='\(dienst.teamId ?? "nil")' matches team id='\(team.id)' or code='\(team.code ?? "nil")'")
            }
            return matches
        }
        
        let now = Date()
        let future = filtered.filter { $0.startTime >= now }.sorted { $0.startTime < $1.startTime }
        let past = filtered.filter { $0.startTime < now }.sorted { $0.startTime > $1.startTime }
        
        Logger.debug("📊 Filtered diensten for team '\(team.name)': \(filtered.count) total (\(future.count) future, \(past.count) past)")
        return future + past
    }
    
    private func teamDisplayName(teamId: String, in tenant: DomainModel.Tenant) -> String {
        Logger.debug("🔍 Looking for team display name with teamId: '\(teamId)' in tenant '\(tenant.name)'")
        
        // NEW: First check if any dienst has this teamId and already has the teamName
        if let dienst = store.upcoming.first(where: { $0.teamId == teamId && $0.teamName != nil }),
           let teamName = dienst.teamName {
            Logger.debug("🎯 Found team name from dienst: '\(teamName)' for teamId='\(teamId)'")
            return teamName
        }
        
        // Fallback to original lookup logic for backwards compatibility
        if let team = tenant.teams.first(where: { $0.id == teamId }) {
            Logger.debug("🎯 Found team by ID: '\(team.name)' (id='\(team.id)' code='\(team.code ?? "nil")')")
            return team.name
        }
        
        if let team = tenant.teams.first(where: { $0.code == teamId }) {
            Logger.debug("🎯 Found team by CODE: '\(team.name)' (id='\(team.id)' code='\(team.code ?? "nil")')")
            return team.name
        }
        
        if let team = tenant.teams.first(where: { 
            $0.id.contains(teamId) || ($0.code?.contains(teamId) ?? false)
        }) {
            Logger.debug("🎯 Found team by PARTIAL match: '\(team.name)' (id='\(team.id)' code='\(team.code ?? "nil")')")
            return team.name
        }
        
        Logger.warning("❌ Team NOT FOUND: teamId='\(teamId)' in tenant '\(tenant.name)'")
        Logger.debug("📋 Available teams in '\(tenant.name)':")
        for team in tenant.teams {
            Logger.debug("  - id='\(team.id)' code='\(team.code ?? "nil")' name='\(team.name)'")
        }
        return "TEAM (\(teamId))"
    }
}

private struct DienstDetail: View {
    @EnvironmentObject var store: AppStore
    let dienst: Dienst
    @State private var name: String = ""
    @State private var working = false
    @State private var errorText: String?
    var body: some View {
        List {
            Section("Details") {
                Text("Tenant: \(dienst.tenantId)")
                Text("Status: \(dienst.status)")
                Text("Start: \(dienst.startTime.formatted())")
                Text("Einde: \(dienst.endTime.formatted())")
                if let loc = dienst.locationName { Text("Locatie: \(loc)") }
            }
            Section("Vrijwilligers") {
                ForEach(dienst.volunteers ?? [], id: \.self) { v in
                    HStack {
                        Text(v)
                        Spacer()
                        Button(role: .destructive) { remove(v) } label: { Image(systemName: "trash") }
                            .disabled(dienst.startTime < Date())
                    }
                }
                HStack {
                    TextField("Naam", text: $name)
                    Button("Voeg toe") { add() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || working || dienst.startTime < Date())
                }
                if let e = errorText { Text(e).foregroundColor(.red).font(.footnote) }
            }
        }
        .navigationTitle("Dienst")
    }

    private func add() {
        guard dienst.startTime >= Date() else {
            errorText = "Kan geen vrijwilligers toevoegen aan diensten in het verleden"
            return
        }
        working = true
        store.addVolunteer(tenant: dienst.tenantId, dienstId: dienst.id, name: name) { result in
            working = false
            if case .failure(let err) = result { errorText = ErrorTranslations.translate(err) }
        }
    }

    private func remove(_ v: String) {
        guard dienst.startTime >= Date() else {
            errorText = "Kan geen vrijwilligers verwijderen van diensten in het verleden"
            return
        }
        working = true
        store.removeVolunteer(tenant: dienst.tenantId, dienstId: dienst.id, name: v) { result in
            working = false
            if case .failure(let err) = result { errorText = ErrorTranslations.translate(err) }
        }
    }
}

// MARK: - Dienst Card View (exact old design colors/fonts)
private struct DienstCardView: View {
    let dienstId: String
    let isManager: Bool
    @EnvironmentObject var store: AppStore
    
    // Dynamic lookup to always get fresh data from store
    private var d: Dienst? {
        store.upcoming.first { $0.id == dienstId }
    }
    
    // Computed property to always reflect current dienst data
    private var volunteers: [String] { d?.volunteers ?? [] }
    @State private var showAddVolunteer = false
    @State private var newVolunteerName = ""
    @State private var showCelebration = false
    @State private var confettiTrigger = 0
    
    var body: some View {
        Group {
            if let dienst = d {
                DienstCardContent(dienst: dienst, isManager: isManager, dienstId: dienstId)
            } else {
                EmptyView() // Dienst not found in store
            }
        }
    }
}

// MARK: - Dienst Card Content (separated for easier state management)
private struct DienstCardContent: View {
    let dienst: Dienst
    let isManager: Bool
    let dienstId: String
    @State private var showAddVolunteer = false
    @State private var newVolunteerName = ""
    @State private var showCelebration = false
    @State private var confettiTrigger = 0
    @EnvironmentObject var store: AppStore
    
    // Computed property to always reflect current dienst data
    private var volunteers: [String] { dienst.volunteers ?? [] }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with date and time
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(dateText)
                        .font(KKFont.title(18))
                        .foregroundStyle(KKTheme.textPrimary)
                    Spacer()
                    // Location badge
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").font(.caption)
                        Text(locationText).font(KKFont.body(12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(Color.blue)
                    .cornerRadius(8)
                }
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption).foregroundStyle(KKTheme.textSecondary)
                    Text(timeRangeText).font(KKFont.body(14)).foregroundStyle(KKTheme.textSecondary)
                }
            }
            
            // Volunteer status and progress
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Bemanning").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(volunteers.count)/\(minimumBemanning)")
                            .font(KKFont.body(12))
                            .fontWeight(.medium)
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                    }
                    .foregroundStyle(statusColor)
                }
                ProgressView(value: min(Double(volunteers.count), Double(minimumBemanning)), total: Double(minimumBemanning))
                    .tint(statusColor)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            
            // Volunteers list
            if !volunteers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Aangemeld:").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
                    LazyVStack(spacing: 6) {
                        ForEach(volunteers, id: \.self) { volunteer in
                            HStack {
                                HStack(spacing: 8) {
                                    Image(systemName: "person.fill").font(.caption).foregroundStyle(Color.green)
                                    Text(volunteer).font(KKFont.body(14)).foregroundStyle(KKTheme.textPrimary)
                                }
                                Spacer()
                                if isManager {
                                    Button(action: { removeVolunteer(volunteer) }) {
                                        Image(systemName: "minus.circle.fill").foregroundStyle(Color.red).font(.title3)
                                    }
                                    .disabled(dienst.startTime < Date())
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.green.opacity(0.1)).cornerRadius(8)
                        }
                    }
                }
            }
            
            // Add volunteer section or celebration
            if isFullyStaffed {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                            .font(.title2)
                            .scaleEffect(showCelebration ? 1.2 : 1.0)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showCelebration)
                        Text("Volledig bemand!")
                            .font(KKFont.title(16))
                            .foregroundStyle(Color.green)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    Text("Deze dienst heeft genoeg vrijwilligers. Bedankt voor je hulp! 🎉")
                        .font(KKFont.body(14))
                        .foregroundStyle(KKTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(16)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.3), lineWidth: 1))
            } else if showAddVolunteer && isManager {
                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        if newVolunteerName.isEmpty {
                            Text("Naam vrijwilliger...").foregroundColor(.gray).padding(.leading, 12).font(KKFont.body(16))
                        }
                        TextField("", text: $newVolunteerName)
                            .padding(12).background(Color.white).cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            .font(KKFont.body(16)).foregroundColor(KKTheme.textPrimary)
                            .disabled(dienst.startTime < Date())
                    }
                    .onSubmit { 
                        if dienst.startTime >= Date() {
                            addVolunteer() 
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Button("Annuleren") { showAddVolunteer = false; newVolunteerName = "" }.buttonStyle(KKSecondaryButton())
                        Button("Toevoegen") { addVolunteer() }.disabled(newVolunteerName.trimmingCharacters(in: .whitespaces).isEmpty || dienst.startTime < Date()).buttonStyle(KKPrimaryButton())
                    }
                    .padding(.top, 8)
                }
            } else {
                if isManager {
                    Button(action: { showAddVolunteer = true }) {
                        HStack { Image(systemName: "plus.circle"); Text("Vrijwilliger toevoegen") }
                    }
                    .buttonStyle(KKSecondaryButton())
                    .disabled(dienst.startTime < Date())
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(KKTheme.textSecondary)
                        Text("Alleen lezen (verenigingslid)").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .background(KKTheme.surfaceAlt)
        .cornerRadius(12)
        .overlay(ConfettiView(trigger: confettiTrigger).allowsHitTesting(false))

    }
    
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: dienst.startTime)
    }
    private var locationText: String { dienst.locationName?.isEmpty == false ? dienst.locationName! : "Kantine" }
    private var timeRangeText: String {
        let start = dienst.startTime.formatted(date: .omitted, time: .shortened)
        let end = dienst.endTime.formatted(date: .omitted, time: .shortened)
        let duration = durationText
        return "\(start) - \(end) (\(duration))"
    }
    private var statusColor: Color {
        if volunteers.count == 0 { return Color.red }
        if volunteers.count < minimumBemanning { return Color.orange }
        return Color.green
    }
    private var isFullyStaffed: Bool { volunteers.count >= minimumBemanning }
    private var minimumBemanning: Int { dienst.minimumBemanning }
    private var durationText: String {
        let minutes = Int(dienst.endTime.timeIntervalSince(dienst.startTime) / 60)
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h\(m > 0 ? " \(m)m" : "")" : "\(m)m"
    }
    
    private func addVolunteer() {
        let name = newVolunteerName.trimmingCharacters(in: .whitespaces)
        Logger.userInteraction("Add Volunteer", target: "DienstCard", context: ["name": name, "dienst_id": dienst.id])
        
        guard isManager, !name.isEmpty, name.count <= 15, !volunteers.contains(name) else { 
            Logger.volunteer("Add validation failed: manager=\(isManager) name='\(name)' exists=\(volunteers.contains(name))")
            return 
        }
        guard dienst.startTime >= Date() else { 
            Logger.volunteer("Cannot add to past dienst")
            return 
        }
        
        Logger.volunteer("Adding volunteer '\(name)' to dienst \(dienst.id)")
        newVolunteerName = ""
        showAddVolunteer = false
        
        // Call backend API instead of local update
        store.addVolunteer(tenant: dienst.tenantId, dienstId: dienst.id, name: name) { result in
            switch result {
            case .success:
                Logger.volunteer("Successfully added volunteer via API")
                // Note: volunteers will be updated when diensten refresh after cache invalidation
                // Check if dienst will be fully staffed after adding this volunteer
                let newVolunteerCount = volunteers.count + 1
                if newVolunteerCount >= minimumBemanning { triggerCelebration() }
            case .failure(let err):
                Logger.volunteer("Failed to add volunteer: \(err)")
                // Revert UI state on failure
                showAddVolunteer = true
                newVolunteerName = name
            }
        }
    }
    private func removeVolunteer(_ name: String) {
        Logger.userInteraction("Remove Volunteer", target: "DienstCard", context: ["name": name, "dienst_id": dienst.id])
        
        guard isManager else { 
            Logger.volunteer("Remove denied: not manager")
            return 
        }
        guard dienst.startTime >= Date() else { 
            Logger.volunteer("Cannot remove from past dienst")
            return 
        }
        
        Logger.volunteer("Removing volunteer '\(name)' from dienst \(dienst.id)")
        
        // Call backend API instead of local update
        store.removeVolunteer(tenant: dienst.tenantId, dienstId: dienst.id, name: name) { result in
            switch result {
            case .success:
                Logger.volunteer("Successfully removed volunteer via API")
                // Note: volunteers will be updated when diensten refresh after cache invalidation
            case .failure(let err):
                Logger.volunteer("Failed to remove volunteer: \(err)")
            }
        }
    }
    private func triggerCelebration() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showCelebration = true }
        confettiTrigger += 1
        
        // Add haptic feedback for extra celebration feel
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Second lighter haptic after delay for double celebration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let lightFeedback = UIImpactFeedbackGenerator(style: .light)
            lightFeedback.impactOccurred()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) { showCelebration = false }
        }
    }
}

// MARK: - Clubs list (exact old design)
private struct ClubsViewInternal: View {
    @EnvironmentObject var store: AppStore
    let onTenantSelected: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                VStack(spacing: 8) {
                    Text("SELECTEER VERENIGING")
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text("Kies een vereniging om je team(s) te bekijken")
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                VStack(spacing: 8) {
                    // Show all tenants, but mark season ended ones differently
                    ForEach(Array(store.model.tenants.values.sorted { $0.name < $1.name }), id: \.slug) { tenant in
                        SwipeableRow(onTap: { onTenantSelected(tenant.slug) }, onDelete: { store.removeTenant(tenant.slug) }) {
                            HStack(spacing: 16) {
                                // Club logo (from tenant info)
                                CachedAsyncImage(url: (store.tenantInfo[tenant.slug]?.clubLogoUrl ?? tenant.clubLogoUrl).flatMap(URL.init)) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "building.2.fill")
                                        .foregroundStyle(KKTheme.accent)
                                }
                                .frame(width: 40, height: 40)
                                .cornerRadius(6)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tenant.name)
                                        .font(KKFont.title(18))
                                        .foregroundStyle(KKTheme.textPrimary)
                                    Text(teamCountText(for: tenant))
                                        .font(KKFont.body(14))
                                        .foregroundStyle(KKTheme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(KKTheme.textSecondary)
                                    .font(.title2)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(KKTheme.surfaceAlt)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 12)
                Spacer(minLength: 24)
            }
        }
    }
    private func teamCountText(for tenant: DomainModel.Tenant) -> String {
        let count = tenant.teams.count
        return count == 1 ? "1 team" : "\(count) teams"
    }
}

// MARK: - Swipeable Row (ported)
private struct SwipeableRow<Content: View>: View {
    let onTap: () -> Void
    let onDelete: () -> Void
    let content: () -> Content
    @State private var offset: CGFloat = 0
    @State private var showingDeleteConfirmation = false
    private let deleteButtonWidth: CGFloat = 80
    var body: some View {
        ZStack {
            content()
                .frame(maxWidth: .infinity)
                .offset(x: offset)
                .onTapGesture { if offset == 0 { onTap() } else { withAnimation(.spring()) { offset = 0 } } }
                .gesture(
                    DragGesture()
                        .onChanged { value in let t = value.translation.width; if t < 0 { offset = max(t, -deleteButtonWidth) } else if offset < 0 { offset = min(0, offset + t) } }
                        .onEnded { value in withAnimation(.spring()) { if value.translation.width < -deleteButtonWidth/2 || value.velocity.width < -500 { offset = -deleteButtonWidth } else { offset = 0 } } }
                )
            HStack { Spacer(); Button(action: { showingDeleteConfirmation = true }) { VStack { Image(systemName: "trash").font(.title2); Text("Verwijder").font(.caption) } .foregroundColor(.white).frame(width: deleteButtonWidth).frame(maxHeight: .infinity).background(Color.red) } .offset(x: offset + deleteButtonWidth).opacity(offset < 0 ? 1 : 0) }
        }
        .clipped()
        .alert("Bevestig verwijdering", isPresented: $showingDeleteConfirmation) {
            Button("Annuleren", role: .cancel) { }
            Button("Verwijderen", role: .destructive) { withAnimation(.spring()) { offset = 0; onDelete() } }
        } message: { Text("Weet je zeker dat je deze enrollment wilt verwijderen?") }
    }
}

// Legacy leftover internal - removed; use the new ClubsViewInternal above

private struct SettingsViewInternal: View {
    @EnvironmentObject var store: AppStore
    @State private var showResetConfirm = false
    @State private var showCapAlert = false
    
    // App info from Info.plist
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }
    private var appBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                VStack(spacing: 8) {
                    Text("INSTELLINGEN")
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text("Beheer je aanmeldingen en voorkeuren")
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                
                // Enrollment actions card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Aanmeldingen")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                    Button {
                        let totalTeams = store.model.tenants.values.reduce(0) { $0 + $1.teams.count }
                        guard totalTeams < 5 else { showCapAlert = true; return }
                        store.startNewEnrollment()
                    } label: {
                        Label("Team toevoegen", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(KKSecondaryButton())
                }
                .kkCard()
                .padding(.horizontal, 24)

                // Notifications card (info only)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Push Meldingen")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                    Text("Push meldingen worden automatisch geconfigureerd bij eerste gebruik. Heb je geweigerd? Ga dan naar Instellingen > Apps > Kantine Koning om meldingen alsnog toe te staan.")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .kkCard()
                .padding(.horizontal, 24)
                
                // Email notification preferences per team (DUMMY)
                EmailNotificationPreferencesView()
                    .environmentObject(store)
                
                // Development/Testing features
                developmentFeaturesCard()
                
                // Destructive reset card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Geavanceerd")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                    Text("Reset alle gegevens zet de app terug naar de beginstatus.")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                    Button {
                        showResetConfirm = true
                    } label: {
                        Label("Alles resetten", systemImage: "trash.fill")
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(KKSecondaryButton())
                }
                .kkCard()
                .padding(.horizontal, 24)
                

                // About: small centered text
                VStack(spacing: 4) {
                    Text("Kantine Koning – versie \(appVersion) (\(appBuild))")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    Text(Logger.buildInfo)
                        .font(KKFont.body(10))
                        .foregroundStyle(KKTheme.textSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                
                Spacer(minLength: 24)
            }
        }
        .alert("Limiet bereikt", isPresented: $showCapAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Je kunt maximaal 5 teams volgen. Verwijder eerst een team om verder te gaan.")
        }
        .alert("Weet je het zeker?", isPresented: $showResetConfirm) {
            Button("Annuleren", role: .cancel) { }
            Button("Reset", role: .destructive) { store.resetAll() }
        } message: {
            Text("Dit verwijdert alle lokale enrollments en gegevens van dit apparaat.")
        }
    }
    
    // MARK: - Development Features
    @ViewBuilder
    private func developmentFeaturesCard() -> some View {
        #if DEBUG
        developmentCard()
        #elseif ENABLE_LOGGING
        // Release Testing scheme with logging enabled
        developmentCard()
        #endif
    }
    
    private func developmentCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🧪 Development Features")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            Text("Tijdelijke test functies voor ontwikkeling")
                .font(KKFont.body(10))
                .foregroundStyle(KKTheme.textSecondary)
                .italic()
            
            VStack(spacing: 8) {
                // Force Season End for any tenant
                ForEach(Array(store.model.tenants.values), id: \.slug) { tenant in
                    Button {
                        simulateSeasonEnd(for: tenant)
                    } label: {
                        if tenant.seasonEnded {
                            Label("Season Ended: \(tenant.name)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.gray)
                        } else {
                            Label("🏁 Force Season End: \(tenant.name)", systemImage: "stop.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(KKSecondaryButton())
                    .disabled(tenant.seasonEnded)
                }
                
                if store.model.tenants.isEmpty {
                    Text("Geen tenants beschikbaar voor season end test")
                        .font(KKFont.body(10))
                        .foregroundStyle(KKTheme.textSecondary)
                        .italic()
                }
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
    

    private func simulateSeasonEnd(for tenant: DomainModel.Tenant) {
        Logger.debug("🧪 [DEV] Simulating season end for tenant: \(tenant.name)")
        
        // Simulate the token revocation scenario
        store.handleTokenRevocation(for: tenant.slug, reason: "dev_simulation")
        
        Logger.debug("🧪 [DEV] Season end simulation completed - tenant marked as ended")
    }
}

// MARK: - Email Notification Preferences
private struct EmailNotificationPreferencesView: View {
    @EnvironmentObject var store: AppStore
    @State private var emailPreferences: [String: Bool] = [:]  // teamId -> enabled
    @State private var adminOverrides: [String: Bool] = [:]   // teamId -> admin disabled
    @State private var pushStatus: [String: Bool] = [:]       // teamId -> has push notifications
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("E-mail Meldingen")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            let hasManagerTeams = store.model.tenants.values.contains { tenant in
                tenant.teams.contains { $0.role == .manager }
            }
            
            if store.model.tenants.isEmpty {
                Text("Geen teams gevonden. Voeg eerst een team toe om e-mail voorkeuren in te stellen.")
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
                    .italic()
            } else if !hasManagerTeams {
                Text("Geen manager teams gevonden. E-mail voorkeuren zijn alleen beschikbaar voor teams waarbij je manager bent.")
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
                    .italic()
            } else {
                VStack(spacing: 8) {
                    // Group teams by tenant - only show active tenants with manager teams
                    let managerTenants = store.model.tenants.values
                        .filter({ tenant in 
                            !tenant.seasonEnded && tenant.teams.contains { $0.role == .manager }
                        })
                        .sorted(by: { $0.name < $1.name })
                    
                    ForEach(Array(managerTenants), id: \.slug) { tenant in
                        // Tenant header
                        HStack {
                            Text(tenant.name)
                                .font(KKFont.body(12))
                                .fontWeight(.medium)
                                .foregroundStyle(KKTheme.textPrimary)
                            Spacer()
                        }
                        .padding(.top, 8)
                        
                        // Teams for this tenant - only show email preferences for manager teams
                        ForEach(tenant.teams.filter({ $0.role == .manager }).sorted(by: { $0.name < $1.name }), id: \.id) { team in
                            let isAdminDisabled = adminOverrides[team.id, default: false]
                            let hasPushNotifications = pushStatus[team.id, default: false]
                            let canDisableEmail = hasPushNotifications  // Only managers shown, so only check push status
                            
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(teamDisplayNameForEmailSettings(team: team, in: tenant))
                                        .font(KKFont.body(14))
                                        .foregroundStyle(KKTheme.textPrimary)
                                    
                                    HStack(spacing: 6) {
                                        // Role badge
                                        Text(team.role == .manager ? "Manager" : "Lid")
                                            .font(KKFont.body(9))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(team.role == .manager ? KKTheme.accent.opacity(0.12) : KKTheme.surfaceAlt)
                                            .foregroundStyle(team.role == .manager ? KKTheme.accent : KKTheme.textSecondary)
                                            .cornerRadius(4)
                                        
                                        // Admin override indicator
                                        if isAdminDisabled {
                                            Text("Admin uitgeschakeld")
                                                .font(KKFont.body(8))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.red.opacity(0.12))
                                                .foregroundStyle(Color.red)
                                                .cornerRadius(3)
                                        }
                                        // Push status indicators
                                        else if !emailPreferences[team.id, default: true] {
                                            if hasPushNotifications {
                                                Text("Alleen push-meldingen")
                                                    .font(KKFont.body(8))
                                                    .foregroundStyle(KKTheme.textSecondary)
                                            } else {
                                                Text("⚠️ Geforceerd email")
                                                    .font(KKFont.body(8))
                                                    .foregroundStyle(Color.orange)
                                            }
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                // Toggle with conditional disable
                                Toggle("", isOn: Binding(
                                    get: { 
                                        if isAdminDisabled { return false }
                                        return emailPreferences[team.id, default: true] 
                                    },
                                    set: { newValue in
                                        // Prevent changes when offline
                                        if !store.isOnline {
                                            Logger.warning("Email preference change blocked - app is offline")
                                            return
                                        }
                                        
                                        // Prevent disabling email if no push notifications for managers
                                        if !newValue && !canDisableEmail {
                                            // Show warning - can't disable email without push notifications
                                            return
                                        }
                                        
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            emailPreferences[team.id] = newValue
                                        }
                                        // Call backend API to update preferences
                                        updateEmailPreference(for: team, in: tenant, enabled: newValue)
                                    }
                                ))
                                .toggleStyle(SwitchToggleStyle(tint: KKTheme.accent))
                                .disabled(isAdminDisabled || !store.isOnline)
                                .opacity((isAdminDisabled || !store.isOnline) ? 0.5 : 1.0)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                

                // Info text
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(KKTheme.accent)
                            .font(.caption)
                        Text("E-mail meldingen uitschakelen")
                            .font(KKFont.body(11))
                            .fontWeight(.medium)
                            .foregroundStyle(KKTheme.textPrimary)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Schakel e-mail meldingen uit als je liever alleen push-meldingen ontvangt in de app. Teammanagers kunnen email alleen uitschakelen als push-meldingen werken. Anders blijft email geforceerd aan voor je veiligheid.")
                            .font(KKFont.body(10))
                            .foregroundStyle(KKTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if !store.isOnline {
                            Text("🌐 Offline: E-mail voorkeuren kunnen niet worden gewijzigd zonder internetverbinding.")
                                .font(KKFont.body(9))
                                .foregroundStyle(Color.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(KKTheme.accent.opacity(0.05))
                .cornerRadius(6)
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
        .onAppear {
            loadEmailPreferencesFromBackend()
        }
    }
    
    private func loadEmailPreferencesFromBackend() {
        // Load email preferences for all manager teams from backend
        for tenant in store.model.tenants.values {
            let managerTeams = tenant.teams.filter({ $0.role == .manager })
            guard !managerTeams.isEmpty else { continue }
            
            // Use manager team-specific auth token to prevent token mixup
            let firstManagerTeam = managerTeams.first!
            guard let authToken = store.model.authTokenForTeam(firstManagerTeam.id, in: tenant.slug) else {
                Logger.email("No auth token for manager team \(firstManagerTeam.id) in tenant \(tenant.name)")
                // Fallback to defaults for this tenant
                setDefaultsForTenant(tenant, managerTeams: managerTeams)
                continue
            }
            
            let backend = BackendClient()
            backend.authToken = authToken
            
            backend.fetchEnrollmentStatus { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let enrollmentStatus):
                        Logger.email("Loaded enrollment status for \(tenant.name): teams=\(enrollmentStatus.teamEmailPreferences?.count ?? 0), push=\(enrollmentStatus.hasApnsToken ?? false)")
                        
                        // Update state based on backend response - now per-team!
                        for team in managerTeams {
                            // Use per-team preference if available, fallback to global
                            self.emailPreferences[team.id] = enrollmentStatus.getEmailPreference(for: team.code ?? team.id)
                            self.pushStatus[team.id] = (enrollmentStatus.pushEnabled ?? false) && (enrollmentStatus.hasApnsToken ?? false)
                            self.adminOverrides[team.id] = false // Admin overrides would come from different API
                        }
                        
                    case .failure(let error):
                        Logger.email("Failed to load enrollment status for \(tenant.name): \(error)")
                        // Fallback to defaults
                        self.setDefaultsForTenant(tenant, managerTeams: managerTeams)
                    }
                }
            }
        }
    }
    
    private func setDefaultsForTenant(_ tenant: DomainModel.Tenant, managerTeams: [DomainModel.Team]) {
        for team in managerTeams {
            if emailPreferences[team.id] == nil {
                emailPreferences[team.id] = true // Default: email enabled
            }
            if adminOverrides[team.id] == nil {
                adminOverrides[team.id] = false // Default: admin allows email
            }
            if pushStatus[team.id] == nil {
                pushStatus[team.id] = false // Default: assume no push until proven otherwise
            }
        }
    }
    
    private func updateEmailPreference(for team: DomainModel.Team, in tenant: DomainModel.Tenant, enabled: Bool) {
        Logger.email("Email notifications for \(team.name) (\(tenant.name)): \(enabled ? "enabled" : "disabled")")
        
        // Use team-specific auth token to prevent token mixup with multiple enrollments
        guard let authToken = store.model.authTokenForTeam(team.id, in: tenant.slug) else {
            Logger.email("No auth token for team \(team.id) in tenant \(tenant.name)")
            // Revert UI state
            withAnimation(.easeInOut(duration: 0.2)) {
                emailPreferences[team.id] = !enabled
            }
            return
        }
        
        let backend = BackendClient()
        backend.authToken = authToken
        
        backend.updateEmailNotificationPreferences(enabled: enabled, teamCode: team.code ?? team.id) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    Logger.email("Email preference updated successfully for \(team.name)")
                    // Reload the actual status from backend to ensure we're in sync
                    backend.fetchEnrollmentStatus { statusResult in
                        DispatchQueue.main.async {
                            switch statusResult {
                            case .success(let enrollmentStatus):
                                // Update with actual backend state (may be different due to forced email logic)
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    // Use per-team preference for this specific team
                                    self.emailPreferences[team.id] = enrollmentStatus.getEmailPreference(for: team.code ?? team.id)
                                    self.pushStatus[team.id] = (enrollmentStatus.pushEnabled ?? false) && (enrollmentStatus.hasApnsToken ?? false)
                                }
                                Logger.email("Synced email preference state from backend for \(team.code ?? team.id): email=\(enrollmentStatus.getEmailPreference(for: team.code ?? team.id))")
                            case .failure(let error):
                                Logger.email("Failed to sync status after update: \(error)")
                            }
                        }
                    }
                case .failure(let error):
                    Logger.email("Failed to update email preference for \(team.name): \(error)")
                    // Revert UI state on failure
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.emailPreferences[team.id] = !enabled
                    }
                }
            }
        }
    }
    
    private func teamDisplayNameForEmailSettings(team: DomainModel.Team, in tenant: DomainModel.Tenant) -> String {
        Logger.debug("🔍 Email settings: Looking for team display name for team id='\(team.id)' name='\(team.name)'")
        
        // NEW: Check if any dienst has team name data that matches this team
        if let dienst = store.upcoming.first(where: { 
            ($0.teamId == team.id || $0.teamId == team.code) && $0.teamName != nil 
        }),
           let teamName = dienst.teamName {
            Logger.debug("🎯 Email settings: Found team name from dienst: '\(teamName)' for team '\(team.id)'")
            return teamName
        }
        
        // Fallback to enrollment team name (may be team code if enrollment was done before backend fix)
        Logger.debug("📋 Email settings: Using enrollment team name: '\(team.name)'")
        return team.name
    }
}

// MARK: - Season Ended Teams View

private struct SeasonEndedTeamsView: View {
    let tenant: DomainModel.Tenant
    let onTeamSelected: (String) -> Void
    let onBack: () -> Void
    @EnvironmentObject var store: AppStore
    
        // Get teams for season ended tenant - show all teams since user was enrolled for this tenant
    private var enrolledTeams: [DomainModel.Team] {
        Logger.debug("🔍 SeasonEndedTeams: Looking for teams in tenant '\(tenant.slug)'")
        
        // For season ended tenants, enrollments may have been cleared
        // So we show ALL teams in the tenant since the user had access to this tenant
        if tenant.seasonEnded {
            Logger.debug("📋 SeasonEndedTeams: Season ended tenant - showing all \(tenant.teams.count) teams")
            let teams = tenant.teams.sorted(by: { $0.name < $1.name })
            
            for team in teams {
                Logger.debug("📋 SeasonEndedTeams: Available team id='\(team.id)' code='\(team.code ?? "nil")' name='\(team.name)' role=\(team.role)")
            }
            
            return teams
        }
        
        // For active tenants, use enrollment filtering (original logic)
        let enrollments = store.model.enrollments.values.filter { $0.tenantSlug == tenant.slug }
        Logger.debug("📋 SeasonEndedTeams: Found \(enrollments.count) enrollments for active tenant")
        
        let enrolledTeamIds = Set(enrollments.flatMap { enrollment in
            Logger.debug("📋 SeasonEndedTeams: Enrollment has teams: \(enrollment.teams)")
            return enrollment.teams
        })
        
        Logger.debug("📋 SeasonEndedTeams: Total enrolled team IDs: \(enrolledTeamIds)")
        
        let teams = tenant.teams.filter { team in
            let isEnrolled = enrolledTeamIds.contains(team.id)
            Logger.debug("📋 SeasonEndedTeams: Team '\(team.name)' (id='\(team.id)') enrolled=\(isEnrolled)")
            return isEnrolled
        }.sorted(by: { $0.name < $1.name })

        Logger.debug("📋 SeasonEndedTeams: Final enrolled teams count: \(teams.count)")
        return teams
    }
    
        var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                
                // Header - same style as TeamsView
                VStack(spacing: 8) {
                    Text("SELECTEER TEAM")
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text("Bij \(tenant.name)")
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                
                // Teams list - exact same layout as TeamsView
                VStack(spacing: 8) {
                    ForEach(enrolledTeams.sorted(by: { 
                        // Sort manager teams first, then by name (same as TeamsView)
                        if $0.role != $1.role {
                            return $0.role == .manager && $1.role == .member
                        }
                        return $0.name < $1.name 
                    }), id: \.id) { team in
                        Button(action: { onTeamSelected(team.id) }) {
                            HStack(spacing: 16) {
                                // Club logo (same as TeamsView)
                                CachedAsyncImage(url: (store.tenantInfo[tenant.slug]?.clubLogoUrl ?? tenant.clubLogoUrl).flatMap(URL.init)) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "building.2.fill")
                                        .foregroundStyle(KKTheme.accent)
                                }
                                .frame(width: 40, height: 40)
                                .cornerRadius(6)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(teamDisplayName(for: team.id, in: tenant))
                                            .font(KKFont.title(18))
                                            .foregroundStyle(KKTheme.textPrimary)
                                        if team.role == .manager {
                                            Text("Manager")
                                                .font(KKFont.body(10))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(KKTheme.accent.opacity(0.12))
                                                .foregroundStyle(KKTheme.accent)
                                                .cornerRadius(8)
                                        }
                                    }
                                    Text("Seizoen afgelopen")
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
                .padding(.horizontal, 24)

                if enrolledTeams.isEmpty {
                    VStack(spacing: 16) {
                        Text("Geen teams gevonden")
                            .font(KKFont.title(20))
                            .foregroundStyle(KKTheme.textPrimary)
                        Text("Er zijn geen teams beschikbaar voor deze vereniging.")
                            .font(KKFont.body(14))
                            .foregroundStyle(KKTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .kkCard()
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: 24)
            }
        }
        .background(KKTheme.surface)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
    
    // MARK: - Team Display Name Resolution
    
    private func teamDisplayName(for teamId: String, in tenant: DomainModel.Tenant) -> String {
        Logger.debug("🔍 SeasonEndedTeams: Looking for team display name with teamId: '\(teamId)' in tenant '\(tenant.name)'")
        
        // Check cached diensten for team name (both active and season ended can use this)
        if let dienst = store.upcoming.first(where: { $0.teamId == teamId && $0.teamName != nil }),
           let teamName = dienst.teamName {
            Logger.debug("🎯 SeasonEndedTeams: Found team name from cached dienst: '\(teamName)' for teamId='\(teamId)'")
            return teamName
        }
        
        // Fallback to DomainModel - but prefer code over raw name for season ended (since name might be stale ID)
        if let team = tenant.teams.first(where: { $0.id == teamId }) {
            // For season ended, if team.name looks like an ID/number, prefer code
            if tenant.seasonEnded && team.name.allSatisfy({ $0.isNumber }) && team.code != nil {
                Logger.debug("🎯 SeasonEndedTeams: Using team code '\(team.code!)' instead of numeric name '\(team.name)' for season ended team")
                return team.code!
            }
            Logger.debug("🎯 SeasonEndedTeams: Found team by ID: '\(team.name)' (id='\(team.id)' code='\(team.code ?? "nil")')")
            return team.name
        }
        
        if let team = tenant.teams.first(where: { $0.code == teamId }) {
            Logger.debug("🎯 SeasonEndedTeams: Found team by code: '\(team.name)' (id='\(team.id)' code='\(team.code ?? "nil")')")
            return team.name
        }
        
        Logger.warning("⚠️ SeasonEndedTeams: No team found for teamId '\(teamId)' in tenant '\(tenant.name)'")
        return teamId
    }
}

