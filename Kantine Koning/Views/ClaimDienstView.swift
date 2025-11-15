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
    
    // Check if user has manager access to this tenant
    private var hasManagerAccess: Bool {
        !managerTeamsForTenant.isEmpty
    }
    
    // Check if we need team selection
    private var needsTeamSelection: Bool {
        managerTeamsForTenant.count > 1
    }
    
    // Get the single team if there's only one
    private var singleTeam: DomainModel.Team? {
        managerTeamsForTenant.count == 1 ? managerTeamsForTenant.first : nil
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)
                
                if !tenantExists {
                    // Tenant not found
                    errorView(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Color.orange,
                        title: "Vereniging niet gevonden",
                        message: "Deze dienst hoort bij een vereniging waar je geen toegang toe hebt."
                    )
                } else if !hasManagerAccess {
                    // No manager access for this tenant
                    errorView(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Color.orange,
                        title: "Geen toegang",
                        message: "Je bent geen teammanager voor deze vereniging. Alleen teammanagers kunnen diensten oppakken."
                    )
                } else if isLoadingDienst {
                    // Loading dienst details
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
                } else if let errorMessage = errorMessage, dienst == nil {
                    // Error loading dienst
                    errorView(
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Color.red,
                        title: "Fout bij ophalen",
                        message: errorMessage
                    )
                } else if let successMessage = successMessage {
                    // Success state
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(Color.green)
                        
                        Text("Dienst opgepakt!")
                            .font(KKFont.heading(24))
                            .fontWeight(.semibold)
                            .foregroundStyle(KKTheme.textPrimary)
                        
                        Text(successMessage)
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
                    .padding(.horizontal, 24)
                } else if let dienst = dienst {
                    // Claiming state with dienst details
                    VStack(spacing: 24) {
                        // Header icon
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 50))
                            .foregroundStyle(KKTheme.accent)
                        
                        Text("Dienst oppakken")
                            .font(KKFont.heading(24))
                            .fontWeight(.semibold)
                            .foregroundStyle(KKTheme.textPrimary)
                        
                        // Dienst details card
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 20))
                                    .foregroundStyle(KKTheme.accent)
                                    .frame(width: 24)
                                Text(formatDate(dienst.start_tijd))
                                    .font(KKFont.body(16))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(KKTheme.textPrimary)
                            }
                            
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.system(size: 20))
                                    .foregroundStyle(KKTheme.accent)
                                    .frame(width: 24)
                                Text("\(formatTime(dienst.start_tijd)) - \(formatTime(dienst.eind_tijd))")
                                    .font(KKFont.body(14))
                                    .foregroundStyle(KKTheme.textSecondary)
                            }
                            
                            if let locatie = dienst.locatie_naam {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(KKTheme.accent)
                                        .frame(width: 24)
                                    Text(locatie)
                                        .font(KKFont.body(14))
                                        .foregroundStyle(KKTheme.textSecondary)
                                }
                            }
                            
                            if let type = dienst.dienst_type?.naam {
                                HStack(spacing: 12) {
                                    Image(systemName: "tag")
                                        .font(.system(size: 20))
                                        .foregroundStyle(KKTheme.accent)
                                        .frame(width: 24)
                                    Text(type)
                                        .font(KKFont.body(14))
                                        .foregroundStyle(KKTheme.textSecondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(KKTheme.surfaceAlt)
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                        
                        Text("Wil je deze dienst oppakken met jouw team?")
                            .font(KKFont.body(14))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(KKTheme.textSecondary)
                            .padding(.horizontal, 24)
                        
                        if needsTeamSelection {
                            // Multiple manager teams: show team selector
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Kies een team:")
                                    .font(KKFont.body(14))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(KKTheme.textPrimary)
                                    .padding(.horizontal, 24)
                                
                                ForEach(managerTeamsForTenant) { team in
                                    TeamSelectionRow(
                                        team: team,
                                        tenantName: tenant?.name ?? "",
                                        isSelected: selectedTeamId == team.id,
                                        action: {
                                            selectedTeamId = team.id
                                        }
                                    )
                                    .padding(.horizontal, 24)
                                }
                            }
                        }
                        
                        if let errorMessage = errorMessage {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.red)
                                Text(errorMessage)
                                    .font(KKFont.body(12))
                                    .foregroundStyle(Color.red)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal, 24)
                        }
                        
                        // Action buttons
                        VStack(spacing: 12) {
                            Button(action: claimDienst) {
                                HStack(spacing: 8) {
                                    if isClaiming {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                    }
                                    Text(isClaiming ? "Bezig met oppakken..." : "Dienst oppakken")
                                        .font(KKFont.body(16))
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isClaiming || (needsTeamSelection && selectedTeamId == nil) ? Color.gray : KKTheme.accent)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                            }
                            .disabled(isClaiming || (needsTeamSelection && selectedTeamId == nil))
                            .padding(.horizontal, 24)
                        }
                        .padding(.top, 8)
                    }
                }
                
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KKTheme.surface)
        .onAppear {
            // Pre-select suggested team if it's a valid manager team for this tenant
            if let suggestedTeamId = suggestedTeamId,
               managerTeamsForTenant.contains(where: { $0.id == suggestedTeamId }) {
                selectedTeamId = suggestedTeamId
            }
            
            if tenantExists && hasManagerAccess {
                fetchDienstDetails()
            }
        }
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
                .padding(.horizontal, 24)
            
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
                    
                    // Auto-dismiss after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.onDismiss()
                    }
                    
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
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tenantName)
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                    
                    Text(team.name)
                        .font(KKFont.body(16))
                        .fontWeight(.medium)
                        .foregroundStyle(KKTheme.textPrimary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(KKTheme.accent)
                }
            }
            .padding(16)
            .background(isSelected ? KKTheme.accent.opacity(0.08) : KKTheme.surfaceAlt)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? KKTheme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
