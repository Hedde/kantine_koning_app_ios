import SwiftUI

struct ClaimDienstView: View {
    @EnvironmentObject var store: AppStore
    
    let tenantSlug: String
    let dienstId: String
    let notificationToken: String
    let suggestedTeamId: String? // Team user was viewing when scanning
    let onDismiss: () -> Void
    
    @State private var selectedTeamId: String? = nil
    @State private var isClaiming = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var isLoadingDienst = true
    @State private var dienst: DienstDTO? = nil
    
    // Get the tenant for this claim
    private var tenant: DomainModel.Tenant? {
        store.model.tenants[tenantSlug]
    }
    
    // Validate tenant exists
    private var tenantExists: Bool {
        tenant != nil
    }
    
    // Get all manager teams for this tenant
    private var managerTeamsForTenant: [DomainModel.Team] {
        guard let tenant = tenant else { return [] }
        return tenant.teams.filter { $0.role == .manager }
    }
    
    // Get teams available for claiming (excludes the team that already owns the dienst)
    private var availableTeamsForClaiming: [DomainModel.Team] {
        // If dienst already has a team, exclude it from selection
        guard let dienstTeamId = dienst?.team?.id else {
            // Open dienst - all manager teams are available
            return managerTeamsForTenant
        }
        
        // Filter out the team that currently owns the dienst
        return managerTeamsForTenant.filter { $0.id != dienstTeamId }
    }
    
    // Check if user has manager access to this tenant
    private var hasManagerAccess: Bool {
        !managerTeamsForTenant.isEmpty
    }
    
    // Check if we need team selection
    private var needsTeamSelection: Bool {
        availableTeamsForClaiming.count > 1
    }
    
    // Get the single team if there's only one
    private var singleTeam: DomainModel.Team? {
        availableTeamsForClaiming.count == 1 ? availableTeamsForClaiming.first : nil
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                mainContent
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
        }
        .safeAreaInset(edge: .top) {
            // Fixed banner positioned under navigation
            TenantBannerView(tenantSlug: tenantSlug)
                .environmentObject(store)
                .padding(.bottom, 12)
                .background(KKTheme.surface)
        }
        .background(KKTheme.surface.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .onAppear { fetchDienstDetails() }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if !tenantExists {
            errorView(
                icon: "exclamationmark.triangle.fill",
                iconColor: Color.orange,
                title: "Vereniging niet gevonden",
                message: "Deze dienst hoort bij een vereniging waar je geen toegang toe hebt."
            )
        } else if !hasManagerAccess {
            errorView(
                icon: "exclamationmark.triangle.fill",
                iconColor: Color.orange,
                title: "Geen toegang",
                message: "Je bent geen teammanager voor deze vereniging. Alleen teammanagers kunnen diensten oppakken."
            )
        } else if dienst != nil && availableTeamsForClaiming.isEmpty {
            errorView(
                icon: "checkmark.circle.fill",
                iconColor: KKTheme.accent,
                title: "Dienst hangt al aan jouw team",
                message: "Deze dienst is al gekoppeld aan het enige team waar je manager van bent."
            )
        } else if isLoadingDienst {
            loadingView
        } else if let errorMessage = errorMessage, dienst == nil {
            errorView(
                icon: "exclamationmark.triangle.fill",
                iconColor: Color.red,
                title: "Fout bij ophalen",
                message: errorMessage
            )
        } else if let successMessage = successMessage {
            successView(message: successMessage)
        } else if let dienst = dienst {
            claimingView(dienst: dienst)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(KKTheme.accent)
            
            Text("Dienst ophalen...")
                .font(KKFont.body(14))
                .foregroundStyle(KKTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
    
    private func successView(message: String) -> some View {
        VStack(spacing: 24) {
            // Header with subtitle (like other pages)
            VStack(spacing: 8) {
                Text("DIENST OPGEPAKT")
                    .font(KKFont.heading(24))
                    .fontWeight(.regular)
                    .kerning(-1.0)
                    .foregroundStyle(KKTheme.textPrimary)
                Text(dienst?.team?.naam ?? "")
                    .font(KKFont.title(16))
                    .foregroundStyle(KKTheme.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 8)
            
            // Success icon and message
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(KKTheme.accent)
                
                Text(message)
                    .font(KKFont.body(16))
                    .foregroundStyle(KKTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 8)
            
            // What happens now section
            VStack(alignment: .leading, spacing: 16) {
                Text("Wat moet je nu doen?")
                    .font(KKFont.title(18))
                    .fontWeight(.semibold)
                    .foregroundStyle(KKTheme.textPrimary)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(KKTheme.accent)
                            .font(.system(size: 18))
                            .frame(width: 20, alignment: .center)
                        Text("Zorg dat je team weet dat jullie deze dienst hebben opgepakt")
                            .font(KKFont.body(14))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundStyle(KKTheme.accent)
                            .font(.system(size: 18))
                            .frame(width: 20, alignment: .center)
                        Text("Geef direct door wie er gaan komen, zodat je team zich kan inschrijven")
                            .font(KKFont.body(14))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                }
            }
            .padding(20)
            .background(KKTheme.surfaceAlt)
            .cornerRadius(12)
            
            // Tip + knop in eigen VStack voor minder spacing
            VStack(spacing: 16) {
                Text("💡 Tip: Super dat jullie helpen! Dit levert natuurlijk ook punten op voor je team 🎉")
                    .font(KKFont.body(14))
                    .foregroundStyle(KKTheme.textSecondary)
                
                // Navigation button
                Button(action: {
                    store.pendingClaimDienst = nil
                }) {
                    Text("Naar het overzicht")
                        .font(KKFont.body(16))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(KKTheme.accent)
                        .cornerRadius(12)
                }
            }
            
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }
    
    private func claimingView(dienst: DienstDTO) -> some View {
        VStack(spacing: 20) {
            // Header with subtitle
            VStack(spacing: 8) {
                Text("DIENST OPPAKKEN")
                    .font(KKFont.heading(24))
                    .fontWeight(.regular)
                    .kerning(-1.0)
                    .foregroundStyle(KKTheme.textPrimary)
                Text("Bevestig je keuze")
                    .font(KKFont.title(16))
                    .foregroundStyle(KKTheme.textSecondary)
            }
            .multilineTextAlignment(.center)
            
            // Dienst details card
            dienstDetailsCard(dienst: dienst)
            
            Text("Wil je deze dienst oppakken met jouw team?")
                .font(KKFont.body(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(KKTheme.textSecondary)
            
            if needsTeamSelection {
                teamSelectionView
            }
            
            if let errorMessage = errorMessage {
                errorBanner(message: errorMessage)
            }
            
            // Action buttons
            actionButtons
            
            // Back button (like QR scanner)
            Button(action: onDismiss) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.body)
                    Text("Terug").font(KKFont.body(12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(KKTheme.textSecondary)
            .padding(.top, 16)
        }
        .onAppear {
            // Pre-select suggested team if it's available for claiming (not the current owner)
            if let suggestedTeamId = suggestedTeamId,
               availableTeamsForClaiming.contains(where: { $0.id == suggestedTeamId }) {
                selectedTeamId = suggestedTeamId
            }
        }
    }
    
    private func dienstDetailsCard(dienst: DienstDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status indicator
            statusIndicator(dienst: dienst)
            
            // Date and location header
            dateAndLocation(dienst: dienst)
            
            // Time and type
            timeAndType(dienst: dienst)
            
            // Bezetting info
            bezettingInfo(dienst: dienst)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(KKTheme.surfaceAlt)
        .cornerRadius(12)
    }
    
    private func statusIndicator(dienst: DienstDTO) -> some View {
        HStack {
            Image(systemName: (dienst.team == nil) ? "circle.dashed" : "arrow.left.arrow.right")
                .font(.system(size: 14))
            if let team = dienst.team {
                Text("Ter overname van \(team.naam)")
                    .font(KKFont.body(14))
                    .fontWeight(.medium)
            } else {
                Text("Open dienst")
                    .font(KKFont.body(14))
                    .fontWeight(.medium)
            }
            Spacer()
        }
        .foregroundStyle((dienst.team == nil) ? Color.blue : KKTheme.accent)
    }
    
    private func dateAndLocation(dienst: DienstDTO) -> some View {
        HStack {
            Text(formatDate(dienst.start_tijd))
                .font(KKFont.title(18))
                .foregroundStyle(KKTheme.textPrimary)
            Spacer()
            
            // Location badge
            HStack(spacing: 4) {
                Image(systemName: "location.fill").font(.system(size: 12))
                Text(dienst.locatie_naam ?? "Kantine").font(KKFont.body(12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundStyle(Color.blue)
            .cornerRadius(8)
        }
    }
    
    private func timeAndType(dienst: DienstDTO) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock").font(.caption).foregroundStyle(KKTheme.textSecondary)
            Text("\(formatTime(dienst.start_tijd)) - \(formatTime(dienst.eind_tijd))")
                .font(KKFont.body(14))
                .foregroundStyle(KKTheme.textSecondary)
            
            if let dienstType = dienst.dienst_type {
                Text("•")
                    .foregroundStyle(KKTheme.textSecondary)
                    .font(KKFont.body(12))
                Text(dienstType.naam)
                    .font(KKFont.body(14))
                    .foregroundStyle(KKTheme.textSecondary)
            }
        }
    }
    
    private func bezettingInfo(dienst: DienstDTO) -> some View {
        let count = dienst.aanmeldingen?.count ?? 0
        let minBemanning = dienst.minimum_bemanning
        let statusColor: Color = count == 0 ? .red : (count < minBemanning ? .orange : .green)
        let countDouble = Double(count)
        let minDouble = Double(minBemanning)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bezetting").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(count)/\(minBemanning)")
                        .font(KKFont.body(12))
                        .fontWeight(.medium)
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                }
            }
            ProgressView(value: Swift.min(countDouble, minDouble), total: minDouble)
                .tint(statusColor)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
        }
    }
    
    private var teamSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kies een team:")
                .font(KKFont.body(14))
                .fontWeight(.semibold)
                .foregroundStyle(KKTheme.textPrimary)
            
            ForEach(availableTeamsForClaiming) { team in
                TeamSelectionRow(
                    team: team,
                    tenantName: tenant?.name ?? "",
                    isSelected: selectedTeamId == team.id,
                    action: {
                        selectedTeamId = team.id
                    }
                )
            }
        }
    }
    
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.red)
            Text(message)
                .font(KKFont.body(12))
                .foregroundStyle(Color.red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var actionButtons: some View {
        Button(action: claimDienst) {
            if isClaiming {
                HStack {
                    ProgressView()
                        .tint(.white)
                    Text("Bezig met oppakken...")
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Dienst oppakken")
                }
            }
        }
        .buttonStyle(KKPrimaryButton())
        .disabled(isClaiming || (needsTeamSelection && selectedTeamId == nil))
        .opacity((isClaiming || (needsTeamSelection && selectedTeamId == nil)) ? 0.5 : 1.0)
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private func errorView(icon: String, iconColor: Color, title: String, message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(iconColor)
            
            Text(title)
                .font(KKFont.heading(24))
                .fontWeight(.semibold)
                .foregroundStyle(KKTheme.textPrimary)
            
            Text(message)
                .font(KKFont.body(14))
                .multilineTextAlignment(.center)
                .foregroundStyle(KKTheme.textSecondary)
            
            Spacer()
            
            // Back button (subtle style like onboarding)
            Button(action: onDismiss) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.body)
                    Text("Terug").font(KKFont.body(12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(KKTheme.textSecondary)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func fetchDienstDetails() {
        isLoadingDienst = true
        errorMessage = nil
        
        // Get authenticated backend client for this tenant
        guard let backend = createAuthenticatedBackend() else {
            errorMessage = "Authenticatie vereist. Log opnieuw in."
            isLoadingDienst = false
            return
        }
        
        backend.fetchDienstDetails(dienstId: dienstId, tenantSlug: tenantSlug, notificationToken: notificationToken) { result in
            DispatchQueue.main.async {
                self.isLoadingDienst = false
                
                switch result {
                case .success(let dienstDTO):
                    // Store dienst DTO
                    self.dienst = dienstDTO
                    Logger.success("Dienst details loaded successfully")
                    
                case .failure(let error):
                    Logger.error("Failed to fetch dienst details: \(error)")
                    if let nsError = error as NSError? {
                        self.errorMessage = nsError.localizedDescription
                    } else {
                        self.errorMessage = "Kan dienst niet ophalen. Probeer het opnieuw."
                    }
                }
            }
        }
    }
    
    private func claimDienst() {
        // Determine which team to claim for
        let teamId: String?
        if needsTeamSelection {
            // Multiple teams: use selected
            teamId = selectedTeamId
        } else {
            // Single team: use that one
            teamId = singleTeam?.id
        }
        
        guard let teamId = teamId else {
            errorMessage = "Selecteer eerst een team"
            return
        }
        
        isClaiming = true
        errorMessage = nil
        
        // Get authenticated backend client for this tenant
        guard let backend = createAuthenticatedBackend() else {
            errorMessage = "Authenticatie vereist. Log opnieuw in."
            isClaiming = false
            return
        }
        
        backend.claimDienst(dienstId: dienstId, teamId: teamId, notificationToken: notificationToken) { result in
            DispatchQueue.main.async {
                self.isClaiming = false
                
                switch result {
                case .success:
                    self.successMessage = "De dienst is succesvol toegewezen aan jouw team."
                    Logger.success("Dienst successfully claimed")
                    
                    // Refresh diensten to show the newly claimed dienst
                    self.store.refreshDiensten()
                    
                    // Don't auto-dismiss - let user read info and click button
                    
                case .failure(let error):
                    Logger.error("Failed to claim dienst: \(error)")
                    
                    // Parse user-friendly error messages
                    if let nsError = error as NSError? {
                        self.errorMessage = nsError.localizedDescription
                    } else {
                        self.errorMessage = "Er ging iets mis bij het oppakken van de dienst. Probeer het opnieuw."
                    }
                }
            }
        }
    }
    
    // Helper to create authenticated BackendClient for this tenant
    private func createAuthenticatedBackend() -> BackendClient? {
        guard let tenant = tenant else {
            Logger.error("Tenant not found: \(tenantSlug)")
            return nil
        }
        
        // Find a MANAGER enrollment token for this tenant
        // (claiming diensten requires manager role)
        let managerEnrollment = tenant.enrollments.compactMap { enrollmentId in
            store.model.enrollments[enrollmentId]
        }.first { enrollment in
            enrollment.role == .manager
        }
        
        guard let signedToken = managerEnrollment?.signedDeviceToken else {
            Logger.error("No manager enrollment token available for tenant \(tenantSlug)")
            return nil
        }
        
        Logger.auth("Using manager enrollment token for claiming dienst")
        let backend = BackendClient()
        backend.authToken = signedToken
        return backend
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter.string(from: date).capitalized
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Team Selection Row
private struct TeamSelectionRow: View {
    let team: DomainModel.Team
    let tenantName: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.name)
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textPrimary)
                    
                    Text(tenantName)
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? KKTheme.accent : KKTheme.textSecondary)
            }
            .padding(16)
            .background(isSelected ? KKTheme.accent.opacity(0.1) : KKTheme.surfaceAlt)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? KKTheme.accent.opacity(0.6) : Color.clear, lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
