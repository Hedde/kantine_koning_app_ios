import SwiftUI
import AVFoundation

struct HomeHostView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSettings = false
    @State private var showLeaderboard = false
    @State private var leaderboardShowingInfo = false
    @State private var selectedTenant: String? = nil
    @State private var selectedTeam: String? = nil
    @State private var showQRScanner = false
    @State private var scanningActive = false
    @State private var showBeschikbareDiensten = false
    @State private var offerTransferForDienst: Dienst? = nil
    
    // Check if user is viewing a manager team page
    private var isViewingManagerTeam: Bool {
        guard let tenantSlug = selectedTenant,
              let teamId = selectedTeam,
              let tenant = store.model.tenants[tenantSlug],
              let team = tenant.teams.first(where: { $0.id == teamId }) else {
            return false
        }
        return team.role == .manager && !tenant.seasonEnded
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation (always visible)
            TopNavigationBar(
                onHomeAction: {
                    // Clear all selections to go back to home
                    selectedTenant = nil
                    selectedTeam = nil
                    showQRScanner = false
                    showBeschikbareDiensten = false
                    showSettings = false
                    showLeaderboard = false
                    scanningActive = false
                    offerTransferForDienst = nil
                    store.pendingClaimDienst = nil
                },
                onSettingsAction: {
                    showSettings.toggle()
            if showSettings {
                        showLeaderboard = false
                        showQRScanner = false
                        scanningActive = false
                        showBeschikbareDiensten = false
                        offerTransferForDienst = nil
                        store.pendingClaimDienst = nil
                    }
                },
                onLeaderboardAction: {
                    if showLeaderboard {
                        // Already in leaderboard - toggle info view
                        leaderboardShowingInfo.toggle()
                    } else {
                        // Opening leaderboard - start with data view
                        showLeaderboard = true
                        leaderboardShowingInfo = false
                        showSettings = false
                        showQRScanner = false
                        scanningActive = false
                        showBeschikbareDiensten = false
                        offerTransferForDienst = nil
                        store.pendingClaimDienst = nil
                    }
                },
                onQRScanAction: {
                    Logger.userInteraction("Tap", target: "QR Scan Button")
                    
                    // If already on QR scanner, refresh by restarting scanning
                    if showQRScanner {
                        scanningActive = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scanningActive = true
                        }
                        return
                    }
                    
                    showQRScanner = true
                    showSettings = false
                    showLeaderboard = false
                    showBeschikbareDiensten = false
                    offerTransferForDienst = nil
                    
                    // Request camera permission and start scanning
                    switch AVCaptureDevice.authorizationStatus(for: .video) {
                    case .authorized:
                        scanningActive = true
                    case .notDetermined:
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            DispatchQueue.main.async {
                                if granted {
                                    scanningActive = true
                                }
                            }
                        }
                    default:
                        Logger.qr("❌ Camera permission denied")
                    }
                },
                onBeschikbareDienstenAction: {
                    Logger.userInteraction("Tap", target: "Beschikbare Diensten Button")
                    
                    // If already on beschikbare diensten, refresh by toggling state
                    if showBeschikbareDiensten {
                        showBeschikbareDiensten = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            showBeschikbareDiensten = true
                        }
                        return
                    }
                    
                    showBeschikbareDiensten = true
                    showSettings = false
                    showLeaderboard = false
                    showQRScanner = false
                    scanningActive = false
                    offerTransferForDienst = nil
                },
                isSettingsActive: showSettings,
                showLeaderboard: showLeaderboard,
                leaderboardShowingInfo: leaderboardShowingInfo,
                showQRButton: isViewingManagerTeam && store.pendingClaimDienst == nil,
                showBeschikbareDienstenButton: isViewingManagerTeam && store.pendingClaimDienst == nil
            )
            .background(KKTheme.surface)
            
            // Offline Banner - shows when no internet connection
            if !store.isOnline {
                OfflineBanner(onRetry: {
                    store.refreshDiensten()
                })
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Main Content
            if let claimParams = store.pendingClaimDienst {
                // Claim dienst view
                ClaimDienstView(
                    tenantSlug: claimParams.tenantSlug,
                    dienstId: claimParams.dienstId,
                    notificationToken: claimParams.notificationToken,
                    suggestedTeamId: claimParams.suggestedTeamId,
                    onDismiss: {
                        store.pendingClaimDienst = nil
                    }
                )
                .environmentObject(store)
            } else if showQRScanner, let tenantSlug = selectedTenant {
                // QR Scanner for claiming diensten
                ScrollView {
                    VStack(spacing: 20) {
                        // Header with subtitle
                        VStack(spacing: 8) {
                            Text("SCAN QR-CODE")
                                .font(KKFont.heading(24))
                                .fontWeight(.regular)
                                .kerning(-1.0)
                                .foregroundStyle(KKTheme.textPrimary)
                            Text("Pak een dienst op met je team")
                                .font(KKFont.title(16))
                                .foregroundStyle(KKTheme.textSecondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                        
                        Text("Richt je camera op een QR-code in de publieke planning")
                            .font(KKFont.body(14))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(KKTheme.textSecondary)
                            .padding(.horizontal, 24)
                        
                        ZStack {
                            QRScannerView(isActive: scanningActive) { code in
                                handleQRScanned(code)
                            }
                            CrosshairOverlay()
                        }
                        .aspectRatio(1.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 24)
                        
                        Button(action: {
                            showQRScanner = false
                            scanningActive = false
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left").font(.body)
                                Text("Terug").font(KKFont.body(12))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(KKTheme.textSecondary)
                        .padding(.top, 24)
                        
                        Spacer(minLength: 24)
                    }
                }
                .safeAreaInset(edge: .top) {
                    // Fixed banner positioned under navigation
                    TenantBannerView(tenantSlug: tenantSlug)
                        .environmentObject(store)
                        .padding(.bottom, 12)
                        .background(KKTheme.surface)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KKTheme.surface.ignoresSafeArea())
            } else if showBeschikbareDiensten, let tenantSlug = selectedTenant {
                // Beschikbare diensten view (manager only)
                BeschikbareDienstenView(
                    tenantSlug: tenantSlug,
                    onDismiss: { showBeschikbareDiensten = false }
                )
                .environmentObject(store)
            } else if let dienst = offerTransferForDienst {
                // Transfer offer view (full page, not sheet)
                OfferDienstForTransferView(
                    dienst: dienst,
                    isPresented: Binding(
                        get: { offerTransferForDienst != nil },
                        set: { if !$0 { offerTransferForDienst = nil } }
                    )
                )
                .environmentObject(store)
            } else if showSettings {
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
                    TeamDienstenView(
                        tenant: tenant, 
                        teamId: teamId,
                        onOfferTransfer: { dienst in
                            offerTransferForDienst = dienst
                        }
                    )
                    .environmentObject(store)
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
            .onChange(of: store.model.tenants) { oldTenants, newTenants in
                // Only react to season ended changes for the currently selected tenant
                guard let selectedTenantSlug = selectedTenant,
                      let oldTenant = oldTenants[selectedTenantSlug],
                      let newTenant = newTenants[selectedTenantSlug],
                      oldTenant.seasonEnded != newTenant.seasonEnded else {
                    return
                }
                
                if newTenant.seasonEnded {
                    Logger.auth("🔄 Selected tenant \(selectedTenantSlug) became season ended - clearing team selection")
                    selectedTeam = nil // This will trigger navigation to SeasonOverviewView
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pushNavigationRequested)) { notification in
                // Handle push notification navigation with defensive programming
                guard let userInfo = notification.userInfo,
                      let tenantSlug = userInfo["tenant"] as? String,
                      let teamCode = userInfo["team"] as? String,
                      let source = userInfo["source"] as? String,
                      source == "push_notification" else {
                Logger.push("🚫 HomeHostView: Invalid push notification data received")
                    return
                }
                
                // Enhanced safety: Don't override user's recent manual navigation
                let userHasNavigated = (selectedTenant != nil || selectedTeam != nil)
                if userHasNavigated {
                    Logger.push("🚫 HomeHostView: User already navigated manually - skipping push navigation")
                    Logger.push("   Current state: tenant=\(selectedTenant ?? "nil") team=\(selectedTeam ?? "nil")")
                    return
                }
                
                // Additional safety: Verify user has correct role access for this team
                if let tenant = store.model.tenants[tenantSlug] {
                    let correctTeamAccess = tenant.teams.contains { team in
                        (team.id == teamCode || team.code == teamCode)
                    }
                    
                    if !correctTeamAccess {
                        Logger.push("🚫 HomeHostView: Team access verification failed for '\(teamCode)' in tenant '\(tenantSlug)'")
                        return
                    }
                }
                
                // Double-check tenant access (redundant safety check)
                guard store.model.tenants[tenantSlug] != nil else {
                    Logger.push("🚫 HomeHostView: Push navigation denied - tenant '\(tenantSlug)' not accessible")
                    return
                }
                
                Logger.push("✅ HomeHostView: Applying push navigation - tenant='\(tenantSlug)' team='\(teamCode)'")
                
                // Apply navigation state
                selectedTenant = tenantSlug
                selectedTeam = teamCode
            }
        .onChange(of: selectedTeam) { _, newTeam in
            // Update AppStore with currently viewing team for QR scan context
            store.currentlyViewingTeamId = newTeam
        }
    }
    
    // MARK: - QR Scanner Handler
    private func handleQRScanned(_ code: String) {
        Logger.qr("📦 Scanned code in HomeHostView: \(code)")
        
        // Stop scanning and close scanner
        scanningActive = false
        showQRScanner = false
                            
        // Try to parse as URL
        guard let url = URL(string: code) else {
            Logger.qr("❌ Invalid URL format")
            return
        }
        
        // Check if it's a claim deep link
        if DeepLink.isClaim(url) {
            Logger.qr("✅ Detected claim deep link, processing...")
            store.handleIncomingURL(url)
                        } else {
            Logger.qr("⚠️ Not a claim deep link, ignoring")
            }
    }
}

// MARK: - Top Navigation Bar
private struct TopNavigationBar: View {
    let onHomeAction: () -> Void
    let onSettingsAction: () -> Void
    let onLeaderboardAction: () -> Void
    let onQRScanAction: () -> Void
    let onBeschikbareDienstenAction: () -> Void
    let isSettingsActive: Bool
    let showLeaderboard: Bool
    let leaderboardShowingInfo: Bool
    let showQRButton: Bool
    let showBeschikbareDienstenButton: Bool
    @EnvironmentObject var store: AppStore
    
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
                HStack(spacing: 12) {
                    Button(action: onHomeAction) {
                        Image(systemName: "house.fill")
                            .font(.title2)
                            .foregroundColor(KKTheme.textSecondary)
                    }
                    
                    if showQRButton {
                        Button(action: onQRScanAction) {
                            Image(systemName: "qrcode")
                                .font(.title2)
                                .foregroundColor(KKTheme.textSecondary)
                        }
                    }
                    
                    if showBeschikbareDienstenButton {
                        Button(action: onBeschikbareDienstenAction) {
                            Image(systemName: "tray.full")
                                .font(.title2)
                                .foregroundColor(KKTheme.textSecondary)
                        }
                    }
                    
                    #if DEBUG
                    // 🚨 TEMP DEBUG: Season end toggle
                    Button(action: {
                        store.toggleSeasonEndedForFirstTenant()
                    }) {
                        let isSeasonEnded = store.model.tenants.values.first?.seasonEnded ?? false
                        Image(systemName: isSeasonEnded ? "flag.checkered.circle.fill" : "flag.circle")
                            .font(.title3)
                            .foregroundColor(isSeasonEnded ? .red : .orange)
                    }
                    #endif
                }
                
                Spacer()
                
                // Right side
                HStack(spacing: 12) {
                        Button(action: onLeaderboardAction) {
                        if showLeaderboard {
                            // In leaderboard - show trophy or question mark
                            Image(systemName: leaderboardShowingInfo ? "trophy.fill" : "questionmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(KKTheme.textSecondary)
                    } else {
                            // Not in leaderboard - show trophy
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
                        let isInvalid = isTeamInvalid(team.id)
                        SwipeableRow(
                            onTap: isInvalid ? nil : { onTeamSelected(team.id) },  // Block tap if invalid
                            onDelete: { store.removeTeam(team.id, from: tenant.slug) }
                        ) {
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
                                .opacity(isInvalid ? 0.5 : 1.0)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(team.name)
                                            .font(KKFont.title(18))
                                            .foregroundStyle(isInvalid ? KKTheme.textSecondary : KKTheme.textPrimary)
                                        if team.role == .manager && !isInvalid {
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
                                        .foregroundStyle(isInvalid ? KKTheme.error : KKTheme.textSecondary)
                                }
                                Spacer()
                                if !isInvalid {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(KKTheme.textSecondary)
                                        .font(.title2)
                                }
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
        .safeAreaInset(edge: .top) {
            // Fixed banner positioned under navigation
            TenantBannerView(tenantSlug: tenant.slug)
                .environmentObject(store)
                .padding(.bottom, 12)
                .background(KKTheme.surface)
        }
    }
    private func dienstCountText(for teamId: String) -> String {
        // Check if enrollment is invalid (device_not_found, invalid_token)
        if store.isTeamEnrollmentInvalid(teamId, in: tenant.slug) {
            return "Uitgelogd"
        }
        
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
    
    /// Check if team enrollment is invalid (for blocking navigation)
    private func isTeamInvalid(_ teamId: String) -> Bool {
        store.isTeamEnrollmentInvalid(teamId, in: tenant.slug)
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
    let onOfferTransfer: (Dienst) -> Void
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    
    private var isTeamInvalid: Bool {
        store.isTeamEnrollmentInvalid(teamId, in: tenant.slug)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(teamDisplayName(teamId: teamId, in: tenant).uppercased())
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(isTeamInvalid ? KKTheme.textSecondary : KKTheme.textPrimary)
                    Text(isTeamInvalid ? "Uitgelogd" : "Aankomende diensten")
                        .font(KKFont.title(16))
                        .foregroundStyle(isTeamInvalid ? KKTheme.error : KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                
                if isTeamInvalid {
                    // Show logged out message for invalid enrollments
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(KKTheme.error.opacity(0.7))
                        
                        VStack(spacing: 8) {
                            Text("Sessie verlopen")
                                .font(KKFont.title(18))
                                .foregroundStyle(KKTheme.textPrimary)
                                .fontWeight(.medium)
                            
                            Text("Je bent uitgelogd voor dit team. Verwijder het team en voeg opnieuw toe om door te gaan.")
                                .font(KKFont.body(14))
                                .foregroundStyle(KKTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("Terug naar overzicht")
                                .font(KKFont.body(16))
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(KKTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 48)
                    .padding(.horizontal, 16)
                } else if let error = store.dienstenError, store.isOnline {
                    // API error state - show error with retry button (only when online)
                    DienstenErrorView(message: error, onRetry: { store.refreshDiensten() })
                } else if diensten.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: store.isOnline ? "calendar.badge.exclamationmark" : "wifi.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(store.isOnline ? KKTheme.textSecondary.opacity(0.5) : KKTheme.accent.opacity(0.7))
                        
                        VStack(spacing: 8) {
                            Text(store.isOnline ? "Geen diensten gevonden" : "Geen internetverbinding")
                                .font(KKFont.title(18))
                                .foregroundStyle(KKTheme.textPrimary)
                                .fontWeight(.medium)
                            
                            Text(store.isOnline 
                                ? "Er zijn momenteel geen aankomende diensten voor dit team."
                                : "Controleer je internetverbinding en probeer opnieuw.")
                                .font(KKFont.body(14))
                                .foregroundStyle(KKTheme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 48)
                    .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 12) {
                                        ForEach(diensten) { d in
                            DienstCardView(
                                dienstId: d.id, 
                                isManager: (tenant.teams.first{ $0.id == teamId }?.role == .manager),
                                onOfferTransfer: onOfferTransfer
                            )
                        .opacity(d.startTime < Date() ? 0.5 : 1.0)
                }
                    }
                    .padding(.horizontal, 16)
                }
                Spacer(minLength: 24)
            }
        }
        .safeAreaInset(edge: .top) {
            // Fixed banner positioned under navigation
            TenantBannerView(tenantSlug: tenant.slug)
                .environmentObject(store)
                .padding(.bottom, 12)
                .background(KKTheme.surface)
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
        
        // Only show last 3 past diensten to keep the list manageable
        let recentPast = Array(past.prefix(3))
        
        Logger.debug("📊 Filtered diensten for team '\(team.name)': \(filtered.count) total (\(future.count) future, \(past.count) past, showing \(recentPast.count) recent)")
        return future + recentPast
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
    let onOfferTransfer: (Dienst) -> Void
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
                DienstCardContent(
                    dienst: dienst, 
                    isManager: isManager, 
                    dienstId: dienstId,
                    onOfferTransfer: onOfferTransfer
                )
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
    let onOfferTransfer: (Dienst) -> Void
    @State private var showAddVolunteer = false
    @State private var newVolunteerName = ""
    @State private var showCelebration = false
    @State private var confettiTrigger = 0
    @State private var working = false
    @State private var errorText: String?
    @State private var removingVolunteers: Set<String> = []
    @State private var calendarService = CalendarService()
    // Calendar success is now tracked persistently in AppStore
    private var isInCalendar: Bool { store.isDienstInCalendar(dienst.id) }
    @State private var calendarError: String?
    @EnvironmentObject var store: AppStore
    
    // Computed property to always reflect current dienst data
    private var volunteers: [String] { dienst.volunteers ?? [] }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with date and time
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Dienst type icon naast datum (grijs vierkantje)
                    if let dienstType = dienst.dienstType {
                        Image(systemName: dienstType.sfSymbolName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.gray.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dateText)
                            .font(KKFont.title(18))
                            .foregroundStyle(KKTheme.textPrimary)
                        Text(dayText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(KKTheme.textSecondary)
                            .tracking(1)
                    }
                    Spacer()
                    
                    // Calendar button (only for future diensten)
                    if dienst.startTime >= Date() && calendarService.isCalendarAvailable {
                        Button(action: { addToCalendar() }) {
                            Image(systemName: isInCalendar ? "calendar.badge.checkmark" : "calendar.badge.plus")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(isInCalendar ? Color.green : KKTheme.accent)
                        }
                        .accessibilityLabel("Toevoegen aan agenda")
                        .disabled(isInCalendar)
                    }
                    
                    // Transfer offer toggle (only for future diensten and managers)
                    if dienst.startTime >= Date() && isManager {
                        Button(action: { onOfferTransfer(dienst) }) {
                            Image(systemName: (dienst.offeredForTransfer ?? false) ? "arrow.left.arrow.right.circle.fill" : "arrow.left.arrow.right.circle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(KKTheme.accent)
                        }
                        .accessibilityLabel("Dienst ter overname aanbieden")
                    }
                    
                    // Location badge
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").font(.system(size: 12))
                        Text(locationText).font(KKFont.body(12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(Color.blue)
                    .cornerRadius(8)
                }
                HStack(spacing: 8) {
                    Image(systemName: "clock").font(.caption).foregroundStyle(KKTheme.textSecondary)
                    Text(timeRangeText).font(KKFont.body(14)).foregroundStyle(KKTheme.textSecondary)
                    
                    // Dienst type - subtiel naast de tijd
                    if let dienstType = dienst.dienstType {
                        Text("•")
                            .foregroundStyle(KKTheme.textSecondary)
                            .font(KKFont.body(12))
                        Text(dienstType.naam)
                            .font(KKFont.body(14))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                }
            }
            
            // Volunteer status and progress
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Bezetting").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
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
                                        if removingVolunteers.contains(volunteer) {
                                            ProgressView().scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "minus.circle.fill").foregroundStyle(Color.red).font(.title3)
                                        }
                                    }
                                    .disabled(dienst.startTime < Date() || removingVolunteers.contains(volunteer))
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
                        Button {
                            showAddVolunteer = false
                            newVolunteerName = ""
                            errorText = nil
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Terug")
                            }
                        }.buttonStyle(KKSecondaryButton())
                        Button(working ? "Bezig..." : "Toevoegen") { addVolunteer() }
                            .disabled(newVolunteerName.trimmingCharacters(in: .whitespaces).isEmpty || dienst.startTime < Date() || working)
                            .buttonStyle(KKPrimaryButton())
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
        // Calendar success alert removed - state is now persistent via isInCalendar computed property
        .alert("Agenda Fout", isPresented: Binding<Bool>(
            get: { calendarError != nil },
            set: { _ in calendarError = nil }
        )) {
            Button("OK") { calendarError = nil }
        } message: {
            Text(calendarError ?? "")
        }

    }
    
    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: dienst.startTime)
    }
    
    private var dayText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: dienst.startTime).uppercased()
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
    
    private func addToCalendar() {
        Logger.userInteraction("Add to Calendar", target: "DienstCard", context: ["dienst_id": dienst.id])
        
        calendarService.addDienstToCalendar(dienst) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Mark as added in persistent storage
                    store.markDienstAddedToCalendar(dienst.id)
                    calendarError = nil
                    
                    // Haptic feedback for success
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.success)
                    
                    Logger.success("Calendar event created successfully")
                    
                case .failure(let error):
                    calendarError = error.localizedDescription
                    
                    // Haptic feedback for error
                    let feedback = UINotificationFeedbackGenerator()
                    feedback.notificationOccurred(.error)
                    
                    Logger.error("Calendar add failed: \(error)")
                }
            }
        }
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
        working = true
        errorText = nil
        newVolunteerName = ""
        showAddVolunteer = false
        
        // OPTIMISTIC UPDATE: Update UI immediately for snappy UX
        store.optimisticallyAddVolunteer(dienstId: dienst.id, name: name)
        
        // Call backend API for persistence
        store.addVolunteer(tenant: dienst.tenantId, dienstId: dienst.id, name: name) { result in
            working = false
            switch result {
            case .success:
                Logger.volunteer("✅ Volunteer added successfully - optimistic update confirmed")
                // Check if dienst is now fully staffed for celebration
                let currentVolunteers = store.upcoming.first { $0.id == dienst.id }?.volunteers ?? []
                if currentVolunteers.count >= minimumBemanning { 
                    triggerCelebration()
                    // Request review at peak happiness moment (after successful completion)
                    AppStore.requestReviewIfAppropriate()
                }
            case .failure(let err):
                Logger.volunteer("❌ Failed to add volunteer - reverting optimistic update")
                // REVERT: Remove optimistic update and show error
                store.revertOptimisticVolunteerAdd(dienstId: dienst.id, name: name)
                errorText = ErrorTranslations.translate(err)
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
        removingVolunteers.insert(name)
        errorText = nil
        
        // OPTIMISTIC UPDATE: Remove from UI immediately for snappy UX
        store.optimisticallyRemoveVolunteer(dienstId: dienst.id, name: name)
        
        // Call backend API for persistence
        store.removeVolunteer(tenant: dienst.tenantId, dienstId: dienst.id, name: name) { result in
            removingVolunteers.remove(name)
            switch result {
            case .success:
                Logger.volunteer("✅ Volunteer removed successfully - optimistic update confirmed")
            case .failure(let err):
                Logger.volunteer("❌ Failed to remove volunteer - reverting optimistic update")
                // REVERT: Add volunteer back and show error
                store.revertOptimisticVolunteerRemove(dienstId: dienst.id, name: name)
                errorText = ErrorTranslations.translate(err)
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
                // No top spacer - handled by safeAreaInset padding
                
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
                    
                    // Add new club/team button
                    Button {
                        store.startNewEnrollment()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(KKTheme.accent)
                                .frame(width: 40, height: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Team toevoegen")
                                    .font(KKFont.title(18))
                                    .foregroundStyle(KKTheme.textPrimary)
                                Text("Scannen of zoeken")
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
                .padding(.horizontal, 12)
                Spacer(minLength: 24)
            }
        }
        .safeAreaInset(edge: .top) {
            // Fixed banner positioned under navigation - EXACT pattern as TenantBannerView
            GlobalBannerView()
                .environmentObject(store)
                .padding(.bottom, 12)
                .background(KKTheme.surface)
        }
        .onAppear {
            // Ensure global banners are loaded when this view appears
            store.refreshGlobalBanners()
        }
    }
    private func teamCountText(for tenant: DomainModel.Tenant) -> String {
        let count = tenant.teams.count
        return count == 1 ? "1 team" : "\(count) teams"
    }
}

// MARK: - Swipeable Row (ported)
private struct SwipeableRow<Content: View>: View {
    let onTap: (() -> Void)?  // Optional - nil disables tap navigation
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
                .onTapGesture { 
                    if offset == 0 { 
                        onTap?()  // Only call if not nil
                    } else { 
                        withAnimation(.spring()) { offset = 0 } 
                    } 
                }
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
        } message: { Text("Weet je zeker dat je dit team wilt verwijderen?") }
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
                // No top spacer - handled by safeAreaInset padding
                
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
                        .font(KKFont.body(13))
                        .foregroundStyle(KKTheme.textPrimary)
                        .fontWeight(.medium)
                    Text("Voeg een nieuwe vereniging of team toe door te scannen of te zoeken")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .font(KKFont.body(13))
                        .foregroundStyle(KKTheme.textPrimary)
                        .fontWeight(.medium)
                    Text("Push meldingen worden automatisch geconfigureerd bij eerste gebruik. Heb je geweigerd? Ga dan naar Instellingen > Apps > Kantine Koning om meldingen alsnog toe te staan.")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .kkCard()
                .padding(.horizontal, 24)
                
                // Email notification preferences per team - only show if user has manager teams
                let hasManagerTeams = store.model.tenants.values.contains { tenant in
                    tenant.teams.contains { $0.role == .manager }
                }
                
                if hasManagerTeams {
                    EmailNotificationPreferencesView()
                        .environmentObject(store)
                }
                
                // Destructive reset card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Geavanceerd")
                        .font(KKFont.body(13))
                        .foregroundStyle(KKTheme.textPrimary)
                        .fontWeight(.medium)
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
        .safeAreaInset(edge: .top) {
            // Fixed banner positioned under navigation - EXACT pattern as TenantBannerView
            GlobalBannerView()
                .environmentObject(store)
                .padding(.bottom, 12)
                .background(KKTheme.surface)
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
            Text("Dit verwijdert alle teams en gegevens van dit apparaat.")
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
                .font(KKFont.body(13))
                .foregroundStyle(KKTheme.textPrimary)
                .fontWeight(.medium)
            
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
                                .font(KKFont.body(13))
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
                // Tenant banners - positioned right under navigation with minimal spacing
                TenantBannerView(tenantSlug: tenant.slug)
                    .environmentObject(store)
                
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
                        SwipeableRow(onTap: { onTeamSelected(team.id) }, onDelete: { store.removeTeam(team.id, from: tenant.slug) }) {
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

// MARK: - Crosshair Overlay for QR Scanner
private struct CrosshairOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let minDim = min(geo.size.width, geo.size.height)
            let inset: CGFloat = minDim * 0.15
            let rect = CGRect(
                x: (geo.size.width - minDim) / 2 + inset,
                y: (geo.size.height - minDim) / 2 + inset,
                width: minDim - 2 * inset,
                height: minDim - 2 * inset
            )

            let lineW: CGFloat = 2.0
            let radius: CGFloat = 16
            let seg: CGFloat = 32
            let plus: CGFloat = 16

            let stroke = StrokeStyle(lineWidth: lineW, lineCap: .round, lineJoin: .round)

            ZStack {
                // TL (Top Left corner)
                Path { p in
                    p.move(to: .init(x: rect.minX + radius, y: rect.minY))
                    p.addLine(to: .init(x: rect.minX + radius + seg, y: rect.minY))
                    p.move(to: .init(x: rect.minX, y: rect.minY + radius))
                    p.addLine(to: .init(x: rect.minX, y: rect.minY + radius + seg))
                    p.addArc(center: .init(x: rect.minX + radius, y: rect.minY + radius),
                             radius: radius,
                             startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                }
                .stroke(Color.black.opacity(0.8), style: stroke)

                // TR (Top Right corner)
                Path { p in
                    p.move(to: .init(x: rect.maxX - radius, y: rect.minY))
                    p.addLine(to: .init(x: rect.maxX - radius - seg, y: rect.minY))
                    p.move(to: .init(x: rect.maxX, y: rect.minY + radius))
                    p.addLine(to: .init(x: rect.maxX, y: rect.minY + radius + seg))
                    p.addArc(center: .init(x: rect.maxX - radius, y: rect.minY + radius),
                             radius: radius,
                             startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)
                }
                .stroke(Color.black.opacity(0.8), style: stroke)

                // BL (Bottom Left corner)
                Path { p in
                    p.move(to: .init(x: rect.minX + radius, y: rect.maxY))
                    p.addLine(to: .init(x: rect.minX + radius + seg, y: rect.maxY))
                    p.move(to: .init(x: rect.minX, y: rect.maxY - radius))
                    p.addLine(to: .init(x: rect.minX, y: rect.maxY - radius - seg))
                    p.addArc(center: .init(x: rect.minX + radius, y: rect.maxY - radius),
                             radius: radius,
                             startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
                }
                .stroke(Color.black.opacity(0.8), style: stroke)

                // BR (Bottom Right corner)
                Path { p in
                    p.move(to: .init(x: rect.maxX - radius, y: rect.maxY))
                    p.addLine(to: .init(x: rect.maxX - radius - seg, y: rect.maxY))
                    p.move(to: .init(x: rect.maxX, y: rect.maxY - radius))
                    p.addLine(to: .init(x: rect.maxX, y: rect.maxY - radius - seg))
                    p.addArc(center: .init(x: rect.maxX - radius, y: rect.maxY - radius),
                             radius: radius,
                             startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                }
                .stroke(Color.black.opacity(0.8), style: stroke)

                // Center crosshair
                Path { p in
                    let c = CGPoint(x: rect.midX, y: rect.midY)
                    p.move(to: .init(x: c.x - plus, y: c.y))
                    p.addLine(to: .init(x: c.x + plus, y: c.y))
                    p.move(to: .init(x: c.x, y: c.y - plus))
                    p.addLine(to: .init(x: c.x, y: c.y + plus))
                }
                .stroke(Color.black.opacity(0.8), style: stroke)
            }
        }
    }
}

// MARK: - Offer Dienst For Transfer Confirmation View
private struct OfferDienstForTransferView: View {
    let dienst: Dienst
    @Binding var isPresented: Bool
    @EnvironmentObject var store: AppStore
    
    @State private var isOffering: Bool = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "d MMMM"
        return formatter
    }
    
    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.dateFormat = "EEEE"
        return formatter
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }
    
    private var isCurrentlyOffered: Bool {
        dienst.offeredForTransfer ?? false
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let successMessage = successMessage {
                    // Success state - consistent header style
                    VStack(spacing: 24) {
                        // Header with subtitle (like other pages)
                        VStack(spacing: 8) {
                            Text(isCurrentlyOffered ? "VERZOEK INGETROKKEN" : "DIENST AANGEBODEN")
                                .font(KKFont.heading(24))
                                .fontWeight(.regular)
                                .kerning(-1.0)
                                .foregroundStyle(KKTheme.textPrimary)
                            Text(dienst.teamName ?? "")
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
                            
                            Text(successMessage)
                                .font(KKFont.body(16))
                                .foregroundStyle(KKTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.bottom, 8)
                        
                        // What happens now section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Wat gebeurt er nu?")
                                .font(KKFont.title(18))
                                .fontWeight(.semibold)
                                .foregroundStyle(KKTheme.textPrimary)
                            
                            if isCurrentlyOffered {
                                // Was offered, now retracted
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(KKTheme.accent)
                                            .font(.system(size: 18))
                                            .frame(width: 20, alignment: .center)
                                        Text("De dienst is niet meer zichtbaar voor andere teams")
                                            .font(KKFont.body(14))
                                            .foregroundStyle(KKTheme.textSecondary)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "person.2.fill")
                                            .foregroundStyle(KKTheme.accent)
                                            .font(.system(size: 18))
                                            .frame(width: 20, alignment: .center)
                                        Text("Je blijft verantwoordelijk voor de bemanning van deze dienst")
                                            .font(KKFont.body(14))
                                            .foregroundStyle(KKTheme.textSecondary)
                                    }
                                }
                            } else {
                                // Was not offered, now offered
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "eye.fill")
                                            .foregroundStyle(KKTheme.accent)
                                            .font(.system(size: 18))
                                            .frame(width: 20, alignment: .center)
                                        Text("De dienst is nu zichtbaar in de publieke planning en in de app bij andere teams")
                                            .font(KKFont.body(14))
                                            .foregroundStyle(KKTheme.textSecondary)
                                    }
                                    
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(KKTheme.accent)
                                            .font(.system(size: 18))
                                            .frame(width: 20, alignment: .center)
                                        Text("Je blijft verantwoordelijk totdat een ander team de dienst oppakt - er zijn geen garanties dat dit gebeurt")
                                            .font(KKFont.body(14))
                                            .foregroundStyle(KKTheme.textSecondary)
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .background(KKTheme.surfaceAlt)
                        .cornerRadius(12)
                        
                        // Tip buiten het grijze vlak (met eigen VStack voor minder spacing)
                        if !isCurrentlyOffered {
                            VStack(spacing: 16) {
                                VStack(spacing: 8) {
                                    Text("💡 Tip: Communiceer ook direct met andere teams")
                                        .font(KKFont.body(14))
                                        .foregroundStyle(KKTheme.textSecondary)
                                    
                                    Text("Dit vergroot de kans dat de dienst wordt opgepakt")
                                        .font(KKFont.body(14))
                                        .foregroundStyle(KKTheme.textSecondary)
                                }
                                
                                // Navigation button
                                Button(action: {
                                    isPresented = false
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
                        } else {
                            // Navigation button (voor intrekken zonder tip)
                            Button(action: {
                                isPresented = false
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
                    .padding(.horizontal, 20)
                } else {
                    // Header with subtitle (like ClubsViewInternal)
                    VStack(spacing: 8) {
                        Text((isCurrentlyOffered ? "OVERNAME VERZOEK INTREKKEN" : "OVERNAME VERZOEK INDIENEN"))
                            .font(KKFont.heading(24))
                            .fontWeight(.regular)
                            .kerning(-1.0)
                            .foregroundStyle(KKTheme.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        Text(dienst.teamName ?? "")
                            .font(KKFont.title(16))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    
                    // Dienst details card (style like normal dienst cards)
                    VStack(alignment: .leading, spacing: 16) {
                        // Date and location header
                        HStack {
                            // Dienst type icon naast datum (grijs vierkantje)
                            if let dienstType = dienst.dienstType {
                                Image(systemName: dienstType.sfSymbolName)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color.gray.opacity(0.85))
                                    .frame(width: 36, height: 36)
                                    .background(Color.gray.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dateFormatter.string(from: dienst.startTime))
                                    .font(KKFont.title(18))
                                    .foregroundStyle(KKTheme.textPrimary)
                                Text(dayFormatter.string(from: dienst.startTime).uppercased())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(KKTheme.textSecondary)
                                    .tracking(1)
                            }
                            Spacer()
                            
                            // Location badge
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill").font(.system(size: 12))
                                Text(dienst.locationName ?? "Kantine").font(KKFont.body(12))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(Color.blue)
                            .cornerRadius(8)
                        }
                        
                        // Time and type
                        HStack(spacing: 8) {
                            Image(systemName: "clock").font(.caption).foregroundStyle(KKTheme.textSecondary)
                            Text("\(timeFormatter.string(from: dienst.startTime)) - \(timeFormatter.string(from: dienst.endTime))")
                                .font(KKFont.body(14))
                                .foregroundStyle(KKTheme.textSecondary)
                            
                            if let dienstType = dienst.dienstType {
                                Text("•")
                                    .foregroundStyle(KKTheme.textSecondary)
                                    .font(KKFont.body(12))
                                Text(dienstType.naam)
                                    .font(KKFont.body(14))
                                    .foregroundStyle(KKTheme.textSecondary)
                            }
                        }
                    }
                    .padding(16)
                    .background(KKTheme.surfaceAlt)
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    
                    // Explanation text
                    VStack(alignment: .leading, spacing: 12) {
                        if isCurrentlyOffered {
                            Text("💪 Top dat jullie het toch gaan doen!")
                                .font(KKFont.body(14))
                                .foregroundStyle(KKTheme.accent)
                                .fontWeight(.medium)
                            
                            Text("Super dat jullie deze dienst alsnog zelf uitvoeren. Samen maken we onze vereniging sterker!")
                                .font(KKFont.body(14))
                                .foregroundStyle(KKTheme.textSecondary)
                        } else {
                            Text("💡 Tip: Probeer eerst binnen je eigen team te ruilen")
                                .font(KKFont.body(14))
                                .foregroundStyle(KKTheme.textSecondary)
                            
                            Text("Lukt het niet om iemand te vinden? Stel de dienst beschikbaar voor andere teams. Let op: je blijft verantwoordelijk totdat een ander team de dienst oppakt.")
                                .font(KKFont.body(14))
                                .foregroundStyle(KKTheme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.red)
                            Text(errorMessage)
                                .font(KKFont.body(13))
                                .foregroundStyle(Color.red)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal, 20)
                    }
                    
                    // Action button
                    Button(action: toggleTransferOffer) {
                        if isOffering {
                            HStack {
                                ProgressView()
                                    .tint(.white)
                                Text("Even geduld...")
                            }
                        } else {
                            HStack {
                                Image(systemName: isCurrentlyOffered ? "arrow.uturn.backward.circle.fill" : "hand.thumbsup.fill")
                                Text(isCurrentlyOffered ? "Aanbod intrekken" : "Dienst aanbieden")
                            }
                        }
                    }
                    .buttonStyle(KKPrimaryButton())
                    .disabled(isOffering)
                    .opacity(isOffering ? 0.5 : 1.0)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    
                    // Back button (like QR scanner)
                    Button(action: { isPresented = false }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.body)
                            Text("Terug").font(KKFont.body(12))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KKTheme.textSecondary)
                    .padding(.top, 16)
                }
                
                Spacer(minLength: 24)
            }
        }
        .safeAreaInset(edge: .top) {
            // Fixed banner positioned under navigation
            TenantBannerView(tenantSlug: dienst.tenantId)
                .environmentObject(store)
                .padding(.bottom, 12)
                .background(KKTheme.surface)
        }
        .background(KKTheme.surface.ignoresSafeArea())
    }
    
    private func toggleTransferOffer() {
        isOffering = true
        errorMessage = nil
        
        let backend = BackendClient()
        
        // CRITICAL: Find the manager enrollment that contains the team for this dienst
        // This ensures the JWT token has the correct team permissions for multi-enrollment scenarios
        var managerEnrollment: DomainModel.Enrollment?
        if let teamId = dienst.teamId {
            Logger.debug("Looking for enrollment containing team: \(teamId) for dienst transfer toggle")
            managerEnrollment = store.model.enrollments.values.first { enrollment in
                enrollment.tenantSlug == dienst.tenantId && 
                enrollment.role == .manager && 
                enrollment.teams.contains(teamId)
            }
            
            if managerEnrollment != nil {
                Logger.success("Found enrollment for dienst team \(teamId)")
            }
        }
        
        // Fallback to any manager enrollment for this tenant if team not found
        if managerEnrollment == nil {
            Logger.debug("No team-specific enrollment found, using any manager enrollment for tenant")
            managerEnrollment = store.model.enrollments.values.first { enrollment in
                enrollment.tenantSlug == dienst.tenantId && enrollment.role == .manager
            }
        }
        
        guard let token = managerEnrollment?.signedDeviceToken else {
            errorMessage = "Geen manager authenticatie beschikbaar"
            isOffering = false
            return
        }
        
        Logger.auth("Using manager enrollment token for transfer toggle: \(token.prefix(20))...")
        backend.authToken = token
        
        backend.toggleTransferOffer(dienstId: dienst.id, offered: !isCurrentlyOffered) { result in
            DispatchQueue.main.async {
                isOffering = false
                
                switch result {
                case .success:
                    successMessage = isCurrentlyOffered ? "Aanbod ingetrokken" : "Dienst aangeboden voor overname"
                    
                    // Refresh diensten to get updated state
                    store.refreshDiensten()
                    
                    // Don't auto-close - let user read info and click button
                    
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Diensten Error View

/// Error view shown when diensten fetch fails (API errors, server errors, timeouts)
/// Displays user-friendly error message with retry button and loading feedback
private struct DienstenErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    @State private var isRetrying = false
    @State private var retryCount = 0
    
    private var errorType: ErrorType {
        if message.contains("internetverbinding") || message.contains("verbinding") {
            return .network
        } else if message.contains("storing") || message.contains("server") {
            return .server
        } else if message.contains("duurt te lang") || message.contains("timeout") {
            return .timeout
        } else {
            return .generic
        }
    }
    
    private enum ErrorType {
        case network, server, timeout, generic
        
        var icon: String {
            switch self {
            case .network: return "wifi.exclamationmark"
            case .server: return "server.rack"
            case .timeout: return "clock.badge.exclamationmark"
            case .generic: return "exclamationmark.triangle"
            }
        }
        
        var title: String {
            switch self {
            case .network: return "Verbindingsprobleem"
            case .server: return "Tijdelijke storing"
            case .timeout: return "Trage verbinding"
            case .generic: return "Kon niet laden"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: errorType.icon)
                .font(.system(size: 48))
                .foregroundStyle(KKTheme.accent)
            
            // Title and message
            VStack(spacing: 8) {
                Text(errorType.title)
                    .font(KKFont.title(18))
                    .foregroundStyle(KKTheme.textPrimary)
                    .fontWeight(.medium)
                
                Text(message)
                    .font(KKFont.body(14))
                    .foregroundStyle(KKTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Retry button with loading state
            Button {
                performRetry()
            } label: {
                HStack(spacing: 8) {
                    if isRetrying {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: KKTheme.accent))
                            .scaleEffect(0.8)
                    }
                    Text(isRetrying ? "Laden..." : "Opnieuw proberen")
                }
            }
            .buttonStyle(KKSecondaryButton())
            .disabled(isRetrying)
            .padding(.horizontal, 48)
            .padding(.top, 8)
            
            // Tip after multiple retries
            if retryCount >= 2 {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 12))
                    Text("Tip: wacht een paar minuten en probeer het dan opnieuw")
                        .font(KKFont.body(12))
                }
                .foregroundStyle(KKTheme.textSecondary.opacity(0.7))
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
    }
    
    private func performRetry() {
        isRetrying = true
        retryCount += 1
        
        // Call retry and simulate minimum loading time for feedback
        onRetry()
        
        // Reset loading state after a brief delay
        // The actual refresh will update the UI when data arrives
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isRetrying = false
        }
    }
}

// MARK: - Offline Banner

/// Banner shown when the device has no internet connection
/// Helps users understand why they might see "Geen diensten" or other empty states
private struct OfflineBanner: View {
    let onRetry: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            
            Text("Geen internetverbinding")
                .font(KKFont.body(14))
                .fontWeight(.medium)
                .foregroundStyle(.white)
            
            Spacer()
            
            Button {
                onRetry()
            } label: {
                Text("Opnieuw")
                    .font(KKFont.body(12))
                    .fontWeight(.semibold)
                    .foregroundStyle(KKTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(KKTheme.accent)
        .padding(.bottom, 8)  // Extra margin to content below
    }
}
