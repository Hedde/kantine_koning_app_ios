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
                    TeamDienstenView(tenant: tenant, teamId: teamId).environmentObject(store)
                } else if let tenantSlug = selectedTenant, let tenant = store.model.tenants[tenantSlug] {
                    TeamsView(tenant: tenant,
                              onTeamSelected: { teamId in selectedTeam = teamId },
                              onBack: { selectedTenant = nil })
                    .environmentObject(store)
                } else {
                    ClubsViewInternal(
                        onTenantSelected: { slug in
                            selectedTenant = slug
                            // Auto-select team when only one exists
                            if let tenant = store.model.tenants[slug], tenant.teams.count == 1, let onlyTeam = tenant.teams.first {
                                selectedTeam = onlyTeam.id
                            }
                        }
                    )
                    .environmentObject(store)
                }

                // Subtle back control
                if (selectedTenant != nil) && (selectedTeam == nil) {
                    Button {
                        if selectedTeam != nil { selectedTeam = nil }
                        else if selectedTenant != nil { selectedTenant = nil }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.body)
                            Text("Terug").font(KKFont.body(12))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KKTheme.textSecondary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KKTheme.surface.ignoresSafeArea())
            .onAppear {
                Logger.viewLifecycle("HomeHostView", event: "onAppear", details: "tenants: \(store.model.tenants.count)")
            }
            .onDisappear {
                Logger.viewLifecycle("HomeHostView", event: "onDisappear")
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
                    ForEach(tenant.teams.sorted(by: { $0.name < $1.name }), id: \.id) { team in
                        SwipeableRow(onTap: { onTeamSelected(team.id) }, onDelete: { store.removeTeam(team.id, from: tenant.slug) }) {
                            HStack(spacing: 16) {
                                // Club logo (same for all teams in this tenant)
                                CachedAsyncImage(url: store.tenantInfo[tenant.slug]?.clubLogoUrl.flatMap(URL.init)) { image in
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
        let count = store.upcoming.filter { $0.teamId == teamId && $0.tenantId == tenant.slug }.count
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
                    Text(findTeamName(teamId: teamId, in: tenant).uppercased())
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
                    DienstCardView(d: d, isManager: (tenant.teams.first{ $0.id == teamId }?.role == .manager))
                        .opacity(d.startTime < Date() ? 0.5 : 1.0)
                }
                    }
                    .padding(.horizontal, 16)
                }
                Spacer(minLength: 24)
            }
        }
        .refreshable { store.refreshDiensten() }
        .background(KKTheme.surface.ignoresSafeArea())
    }
    
    private var diensten: [Dienst] {
        let filtered = store.upcoming.filter { $0.teamId == teamId && $0.tenantId == tenant.slug }
        let now = Date()
        let future = filtered.filter { $0.startTime >= now }.sorted { $0.startTime < $1.startTime }
        let past = filtered.filter { $0.startTime < now }.sorted { $0.startTime > $1.startTime }
        return future + past
    }
    
    private func findTeamName(teamId: String, in tenant: DomainModel.Tenant) -> String {
        Logger.debug("🔍 Looking for team with teamId: '\(teamId)' in tenant '\(tenant.name)'")
        
        // First try to find by ID
        if let team = tenant.teams.first(where: { $0.id == teamId }) {
            Logger.debug("🎯 Found team by ID: '\(team.name)' (id='\(team.id)' code='\(team.code ?? "nil")')")
            return team.name
        }
        
        // Fallback: try to find by code
        if let team = tenant.teams.first(where: { $0.code == teamId }) {
            Logger.debug("🎯 Found team by CODE: '\(team.name)' (id='\(team.id)' code='\(team.code ?? "nil")')")
            return team.name
        }
        
        // Last resort: partial match on ID or code containing the teamId
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
    let d: Dienst
    let isManager: Bool
    @State private var volunteers: [String] = []
    @State private var showAddVolunteer = false
    @State private var newVolunteerName = ""
    @State private var showCelebration = false
    @State private var confettiTrigger = 0
    @EnvironmentObject var store: AppStore
    
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
                                    .disabled(d.startTime < Date())
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
                            .disabled(d.startTime < Date())
                    }
                    .onSubmit { 
                        if d.startTime >= Date() {
                            addVolunteer() 
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Button("Annuleren") { showAddVolunteer = false; newVolunteerName = "" }.buttonStyle(KKSecondaryButton())
                        Button("Toevoegen") { addVolunteer() }.disabled(newVolunteerName.trimmingCharacters(in: .whitespaces).isEmpty || d.startTime < Date()).buttonStyle(KKPrimaryButton())
                    }
                    .padding(.top, 8)
                }
            } else {
                if isManager {
                    Button(action: { showAddVolunteer = true }) {
                        HStack { Image(systemName: "plus.circle"); Text("Vrijwilliger toevoegen") }
                    }
                    .buttonStyle(KKSecondaryButton())
                    .disabled(d.startTime < Date())
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
        .onAppear { volunteers = d.volunteers ?? [] }
    }
    
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: d.startTime)
    }
    private var locationText: String { d.locationName?.isEmpty == false ? d.locationName! : "Kantine" }
    private var timeRangeText: String {
        let start = d.startTime.formatted(date: .omitted, time: .shortened)
        let end = d.endTime.formatted(date: .omitted, time: .shortened)
        let duration = durationText
        return "\(start) - \(end) (\(duration))"
    }
    private var statusColor: Color {
        if volunteers.count == 0 { return Color.red }
        if volunteers.count < minimumBemanning { return Color.orange }
        return Color.green
    }
    private var isFullyStaffed: Bool { volunteers.count >= minimumBemanning }
    private var minimumBemanning: Int { d.minimumBemanning }
    private var durationText: String {
        let minutes = Int(d.endTime.timeIntervalSince(d.startTime) / 60)
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h\(m > 0 ? " \(m)m" : "")" : "\(m)m"
    }
    
    private func addVolunteer() {
        let name = newVolunteerName.trimmingCharacters(in: .whitespaces)
        Logger.userInteraction("Add Volunteer", target: "DienstCard", context: ["name": name, "dienst_id": d.id])
        
        guard isManager, !name.isEmpty, name.count <= 15, !volunteers.contains(name) else { 
            Logger.volunteer("Add validation failed: manager=\(isManager) name='\(name)' exists=\(volunteers.contains(name))")
            return 
        }
        guard d.startTime >= Date() else { 
            Logger.volunteer("Cannot add to past dienst")
            return 
        }
        
        Logger.volunteer("Adding volunteer '\(name)' to dienst \(d.id)")
        newVolunteerName = ""
        showAddVolunteer = false
        
        // Call backend API instead of local update
        store.addVolunteer(tenant: d.tenantId, dienstId: d.id, name: name) { result in
            switch result {
            case .success:
                Logger.volunteer("Successfully added volunteer via API")
                volunteers.append(name)
                if isFullyStaffed { triggerCelebration() }
            case .failure(let err):
                Logger.volunteer("Failed to add volunteer: \(err)")
                // Revert UI state on failure
                showAddVolunteer = true
                newVolunteerName = name
            }
        }
    }
    private func removeVolunteer(_ name: String) {
        Logger.userInteraction("Remove Volunteer", target: "DienstCard", context: ["name": name, "dienst_id": d.id])
        
        guard isManager else { 
            Logger.volunteer("Remove denied: not manager")
            return 
        }
        guard d.startTime >= Date() else { 
            Logger.volunteer("Cannot remove from past dienst")
            return 
        }
        
        Logger.volunteer("Removing volunteer '\(name)' from dienst \(d.id)")
        
        // Call backend API instead of local update
        store.removeVolunteer(tenant: d.tenantId, dienstId: d.id, name: name) { result in
            switch result {
            case .success:
                Logger.volunteer("Successfully removed volunteer via API")
                volunteers.removeAll { $0 == name }
            case .failure(let err):
                Logger.volunteer("Failed to remove volunteer: \(err)")
            }
        }
    }
    private func triggerCelebration() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { showCelebration = true }
        confettiTrigger += 1
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
                    ForEach(Array(store.model.tenants.values), id: \.slug) { tenant in
                        SwipeableRow(onTap: { onTenantSelected(tenant.slug) }, onDelete: { store.removeTenant(tenant.slug) }) {
                            HStack(spacing: 16) {
                                // Club logo (from tenant info)
                                CachedAsyncImage(url: store.tenantInfo[tenant.slug]?.clubLogoUrl.flatMap(URL.init)) { image in
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
                    // Group teams by tenant - only show tenants with manager teams
                    ForEach(Array(store.model.tenants.values.filter({ tenant in
                        tenant.teams.contains { $0.role == .manager }
                    }).sorted(by: { $0.name < $1.name })), id: \.slug) { tenant in
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
                                    Text(team.name)
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
            
            // Use tenant-specific auth token for this enrollment
            guard let authToken = tenant.signedDeviceToken else {
                Logger.email("No auth token for tenant \(tenant.name)")
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
        
        // Use tenant-specific auth token for this enrollment
        guard let authToken = tenant.signedDeviceToken else {
            Logger.email("No auth token for tenant \(tenant.name)")
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
}

