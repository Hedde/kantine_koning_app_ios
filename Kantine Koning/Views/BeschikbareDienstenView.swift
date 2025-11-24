import SwiftUI

struct BeschikbareDienstenView: View {
    @EnvironmentObject var store: AppStore
    let tenantSlug: String
    let onDismiss: () -> Void
    
    @State private var diensten: [DienstDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var showConflictAlert = false
    @State private var conflictMessage = ""
    
    @Environment(\.scenePhase) var scenePhase
    
    // Get tenant and validate manager access
    private var tenant: DomainModel.Tenant? {
        store.model.tenants[tenantSlug]
    }
    
    private var hasManagerAccess: Bool {
        guard let tenant = tenant else { return false }
        return tenant.teams.contains { $0.role == .manager }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with subtitle
                VStack(spacing: 8) {
                    Text("DIENST OPPAKKEN")
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text("Help je vereniging en verdien extra punten")
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
                    
                    // Content
                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(KKTheme.accent)
                            .padding(.top, 40)
                    } else if !hasManagerAccess {
                        EmptyState(
                            icon: "exclamationmark.triangle",
                            title: "Geen toegang",
                            message: "Alleen teammanagers kunnen beschikbare diensten bekijken"
                        )
                    } else if let error = errorMessage {
                        EmptyState(
                            icon: "exclamationmark.triangle",
                            title: "Fout bij ophalen",
                            message: error
                        )
                    } else if diensten.isEmpty {
                        EmptyState(
                            icon: "checkmark.circle",
                            title: "Top! Alles bezet 🎉",
                            message: "Alle diensten zijn momenteel ingevuld. Kom later nog eens terug!"
                        )
                    } else {
                        VStack(spacing: 12) {
                            Text("Voor deze diensten zoeken wij nog hulp")
                                .font(KKFont.body(14))
                                .foregroundStyle(KKTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 8)
                            
                            ForEach(diensten, id: \.id) { dienst in
                                BeschikbareDienstCard(
                                    dienst: dienst,
                                    onClaim: { claimDienst(dienst) }
                                )
                            }
                        }
                    }
                    
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
                    
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .top) {
            // Fixed banner positioned under navigation
            TenantBannerView(tenantSlug: tenantSlug)
                .environmentObject(store)
                .padding(.bottom, 12)
                .background(KKTheme.surface)
        }
        .background(KKTheme.surface.ignoresSafeArea())
        .navigationTitle("Beschikbare diensten")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fetchDiensten() }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Foreground refresh (race condition mitigation)
            if oldPhase == .background && newPhase == .active {
                fetchDiensten()
            }
        }
        .alert("Dienst niet meer beschikbaar", isPresented: $showConflictAlert) {
            Button("OK") {
                // Auto-refresh after conflict
                fetchDiensten()
            }
        } message: {
            Text(conflictMessage)
        }
    }
    
    private func fetchDiensten() {
        guard let backend = createAuthenticatedBackend() else {
            errorMessage = "Authenticatie vereist"
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Get current team code to filter out only this team's diensten
        let currentTeamCode = getCurrentTeamCode()
        
        backend.fetchBeschikbareDiensten(currentTeamCode: currentTeamCode) { result in
            DispatchQueue.main.async {
                isLoading = false
                
                switch result {
                case .success(let fetchedDiensten):
                    diensten = fetchedDiensten
                    Logger.success("Fetched \(fetchedDiensten.count) beschikbare diensten (filtered for team: \(currentTeamCode ?? "all"))")
                    
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    Logger.error("Failed to fetch beschikbare diensten: \(error)")
                }
            }
        }
    }
    
    private func getCurrentTeamCode() -> String? {
        // Get team code of currently viewing team (if any)
        guard let teamId = store.currentlyViewingTeamId,
              let tenant = store.model.tenants[tenantSlug],
              let team = tenant.teams.first(where: { $0.id == teamId }) else {
            return nil
        }
        return team.code
    }
    
    private func claimDienst(_ dienst: DienstDTO) {
        // Reuse existing ClaimDienstView flow
        guard let notificationToken = dienst.notification_token else {
            conflictMessage = "Deze dienst kan niet worden geclaimd (geen token)"
            showConflictAlert = true
            return
        }
        
        store.pendingClaimDienst = AppStore.ClaimDienstParams(
            tenantSlug: tenantSlug,
            dienstId: dienst.id,
            notificationToken: notificationToken,
            suggestedTeamId: store.currentlyViewingTeamId
        )
    }
    
    private func createAuthenticatedBackend() -> BackendClient? {
        // Find MANAGER enrollment token for this tenant
        // CRITICAL: Use enrollment that contains the currently viewing team
        // This ensures the JWT token has the correct team permissions
        guard let tenant = tenant else {
            Logger.error("Tenant not found: \(tenantSlug)")
            return nil
        }
        
        // Try to find enrollment for the currently viewing team first
        var managerEnrollment: DomainModel.Enrollment?
        if let currentTeamId = store.currentlyViewingTeamId {
            Logger.debug("Looking for enrollment containing team: \(currentTeamId)")
            managerEnrollment = tenant.enrollments.compactMap { enrollmentId in
                store.model.enrollments[enrollmentId]
            }.first { enrollment in
                enrollment.role == .manager && enrollment.teams.contains(currentTeamId)
            }
            
            if managerEnrollment != nil {
                Logger.success("Found enrollment for current team \(currentTeamId)")
            }
        }

        // Fallback to any manager enrollment if no team is selected
        if managerEnrollment == nil {
            Logger.debug("No team-specific enrollment found, using any manager enrollment")
            managerEnrollment = tenant.enrollments.compactMap { enrollmentId in
                store.model.enrollments[enrollmentId]
            }.first { enrollment in
                enrollment.role == .manager
            }
        }
        
        guard let signedToken = managerEnrollment?.signedDeviceToken else {
            Logger.error("No manager enrollment token available for tenant \(tenantSlug)")
            return nil
        }
        
        Logger.auth("Using enrollment token for beschikbare diensten: \(signedToken.prefix(20))...")
        
        let backend = BackendClient()
        backend.authToken = signedToken
        return backend
    }
}

// MARK: - Beschikbare Dienst Card
struct BeschikbareDienstCard: View {
    let dienst: DienstDTO
    let onClaim: () -> Void
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "EEEE d MMM"
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
    
    private var isOpen: Bool {
        dienst.team == nil
    }
    
    private var isOfferedForTransfer: Bool {
        dienst.offered_for_transfer == true
    }
    
    private var statusColor: Color {
        let aanmeldingenCount = dienst.aanmeldingen_count ?? 0
        if aanmeldingenCount == 0 { return Color.red }
        if aanmeldingenCount < dienst.minimum_bemanning { return Color.orange }
        return Color.green
    }
    
    var body: some View {
        Button(action: onClaim) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    // Compact header - date and location
                    HStack {
                        Text(dateFormatter.string(from: dienst.start_tijd))
                            .font(KKFont.title(16))
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
                    
                    // Time and status indicator
                    HStack(spacing: 8) {
                        Image(systemName: "clock").font(.caption).foregroundStyle(KKTheme.textSecondary)
                        Text("\(timeFormatter.string(from: dienst.start_tijd)) - \(timeFormatter.string(from: dienst.eind_tijd))")
                            .font(KKFont.body(14))
                            .foregroundStyle(KKTheme.textSecondary)
                        
                        Spacer()
                        
                        // Compact status indicator - just the dot
                        HStack(spacing: 4) {
                            Text("\(dienst.aanmeldingen_count ?? 0)/\(dienst.minimum_bemanning)")
                                .font(KKFont.body(12))
                                .fontWeight(.medium)
                            Circle().fill(statusColor).frame(width: 8, height: 8)
                        }
                        .foregroundStyle(statusColor)
                    }
                }
                
                // Chevron to indicate tappability
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KKTheme.textSecondary.opacity(0.5))
            }
            .padding(16)
            .background(KKTheme.surfaceAlt)
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(KKTheme.textSecondary)
            
            Text(title)
                .font(KKFont.title(18))
                .foregroundStyle(KKTheme.textPrimary)
            
            Text(message)
                .font(KKFont.body(14))
                .foregroundStyle(KKTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 60)
    }
}

