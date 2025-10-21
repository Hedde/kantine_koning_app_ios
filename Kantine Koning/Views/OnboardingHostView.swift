import SwiftUI
import AVFoundation

struct OnboardingHostView: View {
    @EnvironmentObject var store: AppStore
    var namespace: Namespace.ID?
    @State private var email: String = ""
    @State private var tenant: TenantID = "" // Only used as fallback, should not happen in normal flow
    @State private var submitting = false
    @State private var errorText: String?
    @State private var searchQuery: String = ""
    @State private var selectedMemberTeams: Set<TeamID> = []
    @State private var selectedManagerTeams: Set<TeamID> = []
    @State private var scanning = false
    @State private var step: EnrollStep? = nil
    @State private var selectedRole: EnrollStep? = nil
    @State private var keyboardHeight: CGFloat = 0
    @State private var showingQRScanner = false
    @State private var tenantSearchQuery: String = ""
    private var safeAreaBottom: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom ?? 0
    }
    
    // App version info (same as Settings)
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }
    private var appBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }
    
    // Dynamische instructietekst op basis van huidige stap
    private var instructionText: String {
        if showingQRScanner {
            return "Scan de QR-code van je club. Deze vind je op [jouw-vereniging].kantinekoning.com/ios-app-connect"
        }
        
        guard let scanned = store.onboardingScan else {
            // Welkomscherm (geen vereniging geselecteerd)
            return "Zoek je club of scan de QR-code om je team(s) te kiezen en meldingen te ontvangen wanneer jouw team is ingedeeld."
        }
        
        // Vereniging is geselecteerd
        if step == nil {
            // Stap 1: Rol selectie
            return "Kies je rol bij \(scanned.name). Als speler of ouder kies je 'Verenigingslid'."
        } else if step == .manager {
            if store.searchResults.isEmpty {
                // Stap 2a: Manager email invoeren
                return "Voer je e-mailadres in waarmee je bekend bent als teammanager bij \(scanned.name)."
            } else {
                // Stap 2b: Manager teams selecteren
                return "Selecteer de teams waarvoor je als teammanager meldingen wilt ontvangen."
            }
        } else if step == .member {
            // Stap 2c: Lid teams zoeken en selecteren
            return "Zoek en selecteer je team(s) bij \(scanned.name) om meldingen te ontvangen."
        }
        
        // Fallback
        return "Zoek je club of scan de QR-code om je team(s) te kiezen en meldingen te ontvangen wanneer jouw team is ingedeeld."
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Witte achtergrond voor hele app
            Color.white.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Background afbeelding helemaal bovenaan (onder status bar) - ZONDER overlay
                    GeometryReader { geo in
                        let minY = geo.frame(in: .global).minY
                        let imageHeight = max(0, 170 + minY)
                        
                        Image("Background")
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: imageHeight)
                            .offset(y: -minY)
                            .mask(
                                DiagonalShape()
                                    .frame(height: imageHeight)
                                    .offset(y: -minY)
                            )
                    }
                    .frame(height: 120)
                    
                    // Extra ruimte tussen background en logo
                    Spacer().frame(height: 40)
                    
                    // Content container
                    VStack(spacing: 24) {
                        // Logo (altijd tonen)
                        BrandAssets.logoImage()
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                        
                        // Titel (alleen op welkom scherm)
                        if !showingQRScanner {
                            VStack(spacing: -2) {
                                Text("KANTINEDIENSTEN")
                                    .font(KKFont.heading(30))
                                    .fontWeight(.regular)
                                    .kerning(-1.2)
                                    .foregroundStyle(KKTheme.textPrimary)
                                ZigZagWebsiteWord("EENVOUDIG")
                                    .padding(.vertical, -6)
                                Text("PLANNEN.")
                                    .font(KKFont.heading(30))
                                    .fontWeight(.regular)
                                    .kerning(-1.2)
                                    .foregroundStyle(KKTheme.textPrimary)
                            }
                            .multilineTextAlignment(.center)
                        }
                        
                        // Instructietekst (dynamisch op basis van huidige stap)
                        Text(instructionText)
                            .font(KKFont.body(16))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(KKTheme.textSecondary)
                            .padding(.horizontal, 24)

                if let scanned = store.onboardingScan {
                    if step == nil {
                        // Step 1: Role selection after scan
                        ClubEnrollContainer(
                            tenantName: scanned.name,
                            selectedRole: $selectedRole,
                            onContinue: { 
                                if let sel = selectedRole { 
                                    // Clear search results when choosing role
                                    store.searchResults = []
                                    selectedMemberTeams = []
                                    selectedManagerTeams = []
                                    step = sel 
                                } 
                            }
                        )
                        .padding(.bottom, 8)
                        // Terug naar welkom scherm
                        SubtleActionButton(icon: "chevron.left", text: "Terug") {
                            store.onboardingScan = nil
                            store.searchResults = []
                            store.tenantSearchResults = []
                            selectedRole = nil
                            selectedMemberTeams = []
                            selectedManagerTeams = []
                            searchQuery = ""
                            tenantSearchQuery = ""
                            email = ""
                            showingQRScanner = false
                            scanning = false
                        }
                    } else if step == .manager {
                        if store.searchResults.isEmpty {
                            // Step 2a: Manager email verification
                            ManagerVerifySection(email: $email, isLoading: submitting, errorText: $errorText, onSubmit: {
                                // Valideer email eerst
                                let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmedEmail.isEmpty {
                                    errorText = "Vul een e-mailadres in"
                                    return
                                }
                                if !isValidEmail(trimmedEmail) {
                                    errorText = "Vul een geldig e-mailadres in"
                                    return
                                }
                                
                                submitting = true
                                errorText = nil
                                store.submitEmail(trimmedEmail, for: scanned.slug, selectedTeamCodes: []) { result in
                                    submitting = false
                                    if case .failure(let err) = result { errorText = ErrorTranslations.translate(err) }
                                }
                            })
                            .padding(.bottom, 8)
                            // Terug - want misschien toch verenigingslid willen worden
                            SubtleActionButton(icon: "chevron.left", text: "Terug") { 
                                store.searchResults = []
                                errorText = nil
                                step = nil 
                            }
                        } else {
                            // Step 2b: Manager team selection
                            ManagerTeamPickerSection(allowed: sortedAllowedTeams(),
                                                     selected: $selectedManagerTeams,
                                                     onSubmit: submitManagerTeams,
                                                     enrolledIds: enrolledTeamIdsForTenant(scanned.slug))
                            .padding(.bottom, 8)
                            // Terug - want misschien andere teams willen of email wijzigen
                            SubtleActionButton(icon: "chevron.left", text: "Terug") { 
                                store.searchResults = []
                                selectedManagerTeams = []
                                email = ""
                                errorText = nil
                            }
                        }
                    } else if step == .member {
                        // Step 2c: Member team search
                        MemberSearchSection(
                            tenant: scanned.slug,
                            searchQuery: $searchQuery,
                            results: store.searchResults,
                            selected: $selectedMemberTeams,
                            onSearch: { q in store.searchTeams(tenant: scanned.slug, query: q) },
                            onSubmit: registerMember
                        )
                        .padding(.bottom, 8)
                        // Terug - want misschien toch teammanager willen worden
                        SubtleActionButton(icon: "chevron.left", text: "Terug") { 
                            store.searchResults = []
                            selectedMemberTeams = []
                            searchQuery = ""
                            step = nil 
                        }
                    }
                } else if showingQRScanner {
                    // QR Scanner (when explicitly chosen)
                    VStack(spacing: 16) {
                        ZStack {
                            QRScannerView(isActive: scanning) { code in
                                handleScanned(code)
                            }
                            CrosshairOverlay()
                        }
                        .aspectRatio(1.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 24)
                        
                        // Terug naar welkom scherm
                        SubtleActionButton(icon: "chevron.left", text: "Terug") {
                            store.searchResults = []
                            store.tenantSearchResults = []
                            tenantSearchQuery = ""
                            showingQRScanner = false
                            scanning = false
                        }
                    }
                } else {
                    // Welkom scherm met tenant search
                    TenantSearchSection(
                        searchQuery: $tenantSearchQuery,
                        results: store.tenantSearchResults,
                        onTenantSelected: { tenant in
                            // Simuleer QR scan met gekozen tenant
                            store.handleQRScan(slug: tenant.slug, name: tenant.name)
                        },
                        onQRScanTapped: {
                            // Clear all state for fresh scan
                            store.onboardingScan = nil
                            store.searchResults = []
                            selectedRole = nil
                            step = nil
                            selectedMemberTeams = []
                            selectedManagerTeams = []
                            searchQuery = ""
                            tenantSearchQuery = ""
                            email = ""
                            errorText = nil
                            
                            showingQRScanner = true
                            
                            // Request camera permission and start scanning
                            switch AVCaptureDevice.authorizationStatus(for: .video) {
                            case .authorized:
                                scanning = true
                            case .notDetermined:
                                AVCaptureDevice.requestAccess(for: .video) { granted in
                                    DispatchQueue.main.async {
                                        if granted {
                                            scanning = true
                                        }
                                    }
                                }
                            default:
                                // Camera permission denied - scanner will show empty
                                break
                            }
                        }
                    )
                }


                
                // Show back button only if there are existing enrollments AND we're not in a scanned state AND not showing QR scanner
                if !store.model.tenants.isEmpty && store.onboardingScan == nil && !showingQRScanner {
                    SubtleActionButton(icon: "chevron.left", text: "Terug") {
                        store.appPhase = .registered
                    }
                    .padding(.top, 16)
                }
                
                // Show version info when no enrollments yet (geen instellingen bereikbaar)
                if store.model.tenants.isEmpty && store.onboardingScan == nil && !showingQRScanner {
                    Spacer().frame(height: 40)
                    
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
                }
                    }
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: keyboardHeight)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let adjusted = max(0, frame.height - safeAreaBottom - 80)
                keyboardHeight = adjusted
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onTapGesture {
            // Dismiss keyboard when tapping on non-interactive areas
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    private func request() {
        submitting = true
        guard let tenantSlug = store.onboardingScan?.slug else {
            Logger.error("No tenant found in onboardingScan - this should not happen in normal flow")
            errorText = "Er is een probleem opgetreden. Probeer opnieuw te scannen."
            return
        }
        store.submitEmail(email, for: tenantSlug, selectedTeamCodes: []) { result in
            submitting = false
            switch result {
            case .success:
                break // Teams will appear in UI
            case .failure(let err):
                errorText = ErrorTranslations.translate(err)
            }
        }
    }

    private func simulateOpenMagicLink() {
        let url = URL(string: "kantinekoning://device-enroll?token=STUB")!
        store.handleIncomingURL(url)
    }

    private func toggleSelect(_ t: SearchTeam) {
        if selectedMemberTeams.contains(t.id) { selectedMemberTeams.remove(t.id) } else { selectedMemberTeams.insert(t.id) }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: trimmed)
    }

    private func registerMember() {
        guard !selectedMemberTeams.isEmpty else { return }
        Logger.debug("Registering member with teams: \(Array(selectedMemberTeams))")
        // Use team codes, not IDs for backend
        let teamCodes = store.searchResults.filter { selectedMemberTeams.contains($0.id) }.compactMap { $0.code ?? $0.id }
        Logger.debug("📋 Team codes to register: \(teamCodes)")
        guard let tenantSlug = store.onboardingScan?.slug,
              let tenantName = store.onboardingScan?.name else {
            Logger.error("No tenant found in onboardingScan - this should not happen in normal flow")
            errorText = "Er is een probleem opgetreden. Probeer opnieuw te scannen."
            return
        }
        store.registerMember(tenantSlug: tenantSlug, tenantName: tenantName, teamIds: teamCodes) { result in
            if case .failure(let err) = result { errorText = ErrorTranslations.translate(err) }
        }
    }

    private func submitManagerTeams() {
        guard !selectedManagerTeams.isEmpty else { return }
        submitting = true
        // Convert team IDs to team codes for backend
        let teamCodes = store.searchResults.filter { selectedManagerTeams.contains($0.id) }.compactMap { $0.code ?? $0.id }
        Logger.debug("📋 Manager team codes to submit: \(teamCodes)")
        guard let tenantSlug = store.onboardingScan?.slug else {
            Logger.error("No tenant found in onboardingScan - this should not happen in normal flow")
            errorText = "Er is een probleem opgetreden. Probeer opnieuw te scannen."
            submitting = false
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        store.submitEmail(trimmedEmail, for: tenantSlug, selectedTeamCodes: teamCodes) { result in
            submitting = false
            if case .failure(let err) = result { errorText = ErrorTranslations.translate(err) }
        }
    }
}

// MARK: - Helpers
private extension OnboardingHostView {
    func handleScanned(_ code: String) {
        Logger.qr("📦 Raw payload=\(code)")
        scanning = false
        // Clear all state for fresh enrollment flow
        selectedRole = nil
        step = nil
        selectedMemberTeams = []
        selectedManagerTeams = []
        searchQuery = ""
        email = ""
        errorText = nil
        // Accept direct formats: 
        //  - kantinekoning://tenant?slug=&name=
        //  - kantinekoning://invite?tenant=&tenant_name=
        //  - https://kantinekoning.com/invite?tenant=&tenant_name=
        if let url = URL(string: code), (url.scheme == "kantinekoning" || (url.scheme == "https" && url.host?.contains("kantinekoning.com") == true)) {
            Logger.qr("Direct scheme host=\(url.host ?? "nil") path=\(url.path)")
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if url.host == "tenant",
               let slug = comps?.queryItems?.first(where: { $0.name == "slug" })?.value,
               let name = comps?.queryItems?.first(where: { $0.name == "name" })?.value {
                Logger.qr("✅ Parsed direct slug=\(slug) name=\(name)")
                tenant = slug
                store.handleQRScan(slug: slug, name: name)
                return
            }
            if (url.host == "invite" || url.path.contains("invite")),
               let params = DeepLink.extractInviteParams(from: url) {
                Logger.qr("✅ Parsed invite slug=\(params.tenant) name=\(params.tenantName)")
                tenant = params.tenant
                store.handleQRScan(slug: params.tenant, name: params.tenantName)
                return
            }
            if let items = comps?.queryItems {
                Logger.qr("Direct query items: \(items.map{ "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", "))")
            }
        }
        // Fallback: handle possible nested URL parameters (compat with QR server)
        if let outer = URL(string: code),
           let outerComps = URLComponents(url: outer, resolvingAgainstBaseURL: false),
           let dataParam = outerComps.queryItems?.first(where: { $0.name == "data" })?.value,
           let decoded = dataParam.removingPercentEncoding,
           let inner = URL(string: decoded),
           let innerComps = URLComponents(url: inner, resolvingAgainstBaseURL: false),
           innerComps.host == "tenant",
           let slug = innerComps.queryItems?.first(where: { $0.name == "slug" })?.value,
           let name = innerComps.queryItems?.first(where: { $0.name == "name" })?.value {
            Logger.qr("✅ Parsed nested slug=\(slug) name=\(name)")
            tenant = slug
            store.handleQRScan(slug: slug, name: name)
            return
        }
        Logger.qr("❌ Could not parse QR payload")
    }
}

// MARK: - Styled Components
private enum EnrollStep { case manager, member }

private struct ClubEnrollContainer: View {
    let tenantName: String
    @Binding var selectedRole: EnrollStep?
    let onContinue: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Gevonden club").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
                Text(tenantName).font(KKFont.title(20)).foregroundStyle(KKTheme.textPrimary)
                Text("Ik meld me aan als…").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
                VStack(spacing: 12) {
                    KKSelectableRow(title: "Teammanager", subtitle: "E‑mail vereist, beheer vrijwilligers", isSelected: selectedRole == .manager) { selectedRole = .manager }
                    KKSelectableRow(title: "Verenigingslid", subtitle: "Alleen lezen, meldingen ontvangen", isSelected: selectedRole == .member) { selectedRole = .member }
                }
                Button("Verder", action: onContinue)
                    .buttonStyle(KKPrimaryButton())
                    .disabled(selectedRole == nil)
            }
            .kkCard()
        }
        .padding(.horizontal, 24)
    }
}

private struct ManagerVerifySection: View {
    @Binding var email: String
    var isLoading: Bool
    @Binding var errorText: String?
    var onSubmit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("E-mailadres teammanager").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
            Text("Voer het e-mailadres in waarmee je als teammanager bekend bent bij deze club.")
                .font(KKFont.body(11)).foregroundStyle(KKTheme.textSecondary).italic()
            ZStack(alignment: .leading) {
                if email.isEmpty {
                    Text("manager@club.nl")
                        .foregroundColor(.secondary)
                        .padding(.leading, 16)
                        .font(KKFont.body(16))
                        .allowsHitTesting(false)
                }
                TextField("", text: $email)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(KKTheme.surfaceAlt)
                    .cornerRadius(8)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .font(KKFont.body(16))
                    .foregroundColor(KKTheme.textPrimary)
                    .onSubmit { onSubmit() }
            }
            if let errorText = errorText {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(KKTheme.textSecondary.opacity(0.7))
                        .font(.system(size: 20))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Er ging iets mis")
                            .font(KKFont.body(13))
                            .foregroundStyle(KKTheme.textPrimary)
                            .fontWeight(.medium)
                        
                        Text(errorText)
                            .font(KKFont.body(13))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(KKTheme.surface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(KKTheme.textSecondary.opacity(0.1), lineWidth: 1)
                )
            }
            Button(action: onSubmit) { 
                if isLoading {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("Controleren...")
                    }
                } else {
                    Text("Teams ophalen")
                }
            }
            .disabled(isLoading)
            .buttonStyle(KKPrimaryButton())
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

private struct MemberSearchSection: View {
    @EnvironmentObject var store: AppStore
    let tenant: TenantID
    @Binding var searchQuery: String
    let results: [SearchTeam]
    @Binding var selected: Set<TeamID>
    let onSearch: (String) -> Void
    let onSubmit: () -> Void
    
    private let maxDisplayedResults = 3
    
    // Filter out teams that are already enrolled as manager for this tenant
    private var filteredResults: [SearchTeam] {
        let existingManagerTeams = store.model.tenants[tenant]?.teams
            .filter { $0.role == .manager }
            .map { $0.id } ?? []
        
        return results.filter { team in
            // Exclude teams where user is already a manager
            !existingManagerTeams.contains(team.id) && 
            !existingManagerTeams.contains(team.code ?? "")
        }
    }
    
    private var limitedResults: [SearchTeam] {
        Array(filteredResults.prefix(maxDisplayedResults))
    }
    private var hasMoreResults: Bool {
        filteredResults.count > maxDisplayedResults
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zoek je team(s)").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
            
            // Helpful instruction text (always visible)
            Text("Teams beginnen meestal met JO13, MO11, 1, 2, 3, enzovoorts")
                .font(KKFont.body(11))
                .foregroundStyle(KKTheme.textSecondary)
                .italic()
            
            TextField("Bijv. JO11-3", text: $searchQuery)
                .kkTextField()
                .onChange(of: searchQuery) { _, newValue in onSearch(newValue) }
            
            if !limitedResults.isEmpty || hasMoreResults {
                VStack(spacing: 8) {
                    ForEach(limitedResults, id: \.id) { t in
                    KKSelectableRow(
                        title: t.name,
                        subtitle: t.code,
                        isSelected: selected.contains(t.id),
                        action: { toggle(t.id) }
                    )
                }
                
                // Show message when there are more results
                if hasMoreResults {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(KKTheme.textSecondary.opacity(0.7))
                            .font(.system(size: 20))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Meer teams gevonden")
                                .font(KKFont.body(13))
                                .foregroundStyle(KKTheme.textPrimary)
                                .fontWeight(.medium)
                            
                            Text("Er zijn \(filteredResults.count - maxDisplayedResults) meer resultaten. Typ meer letters voor een specifiekere zoekopdracht.")
                                .font(KKFont.body(13))
                                .foregroundStyle(KKTheme.textSecondary)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(KKTheme.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(KKTheme.textSecondary.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.top, 4)
                }
            }
            }
            
            Button("Aanmelden", action: onSubmit)
                .disabled(selected.isEmpty)
                .buttonStyle(KKPrimaryButton())
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
    
    private func toggle(_ id: TeamID) { 
        if selected.contains(id) { 
            selected.remove(id) 
        } else { 
            selected.insert(id) 
        } 
    }
}

private struct ManagerTeamPickerSection: View {
    let allowed: [SearchTeam]
    @Binding var selected: Set<TeamID>
    let onSubmit: () -> Void
    var enrolledIds: Set<TeamID> = []
    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kies je teams").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
                ForEach(allowed, id: \.id) { t in
                    let isDisabled = enrolledIds.contains(t.id)
                    let disabledReason = isDisabled ? "Reeds gevolgd" : nil
                    KKSelectableRow(
                        title: t.name, 
                        subtitle: t.code, 
                        isSelected: selected.contains(t.id), 
                        isDisabled: isDisabled,
                        disabledReason: disabledReason
                    ) {
                        if isDisabled { return }
                        if selected.contains(t.id) { selected.remove(t.id) } else { selected.insert(t.id) }
                    }
                }
            }
            .kkCard()
            Button("Doorgaan met \(selected.count) team\(selected.count == 1 ? "" : "s")", action: onSubmit)
                .disabled(selected.isEmpty)
                .buttonStyle(KKPrimaryButton())
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Sorting/Filter helpers
private extension OnboardingHostView {
    func sortedAllowedTeams() -> [SearchTeam] {
        // Old design sorted by code when present, else by name; ascending
        store.searchResults.sorted { a, b in
            let al = (a.code ?? a.name).localizedCaseInsensitiveCompare(b.code ?? b.name)
            return al == .orderedAscending
        }
    }
    func enrolledTeamIdsForTenant(_ tenantId: TenantID) -> Set<TeamID> {
        // Use current model enrollment to gray out already followed teams AS MANAGER
        // (members can upgrade to manager for same teams)
        let managerIds = store.model.tenants[tenantId]?.teams
            .filter { $0.role == .manager }
            .map { $0.id } ?? []
        return Set(managerIds)
    }
}
private struct HeaderHero: View {
    var showBackground: Bool = true
    var instructionText: String = "Zoek je club of scan de QR-code om je team(s) te kiezen en meldingen te ontvangen wanneer jouw team is ingedeeld."
    
    var body: some View {
        VStack(spacing: 24) {
            BrandAssets.logoImage()
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            VStack(spacing: -2) {
                Text("KANTINEDIENSTEN")
                    .font(KKFont.heading(30))
                    .fontWeight(.regular)
                    .kerning(-1.2)
                    .foregroundStyle(KKTheme.textPrimary)
                ZigZagWebsiteWord("EENVOUDIG")
                    .padding(.vertical, -6)
                Text("PLANNEN.")
                    .font(KKFont.heading(30))
                    .fontWeight(.regular)
                    .kerning(-1.2)
                    .foregroundStyle(KKTheme.textPrimary)
            }
            .multilineTextAlignment(.center)

            Text(instructionText)
                .font(KKFont.body(16))
                .multilineTextAlignment(.center)
                .foregroundStyle(KKTheme.textSecondary)
                .padding(.horizontal, 24)
        }
    }
}

// Exact zig-zag word from old design
private struct ZigZagWebsiteWord: View {
    let word: String
    init(_ word: String) { self.word = word }
    var body: some View {
        HStack(spacing: 0) {
            Text(word)
                .font(KKFont.heading(30))
                .fontWeight(.regular)
                .kerning(-1.2)
                .foregroundColor(KKTheme.accent)
                .background(
                    GeometryReader { geo in
                        let textWidth = geo.size.width
                        let textHeight: CGFloat = 30
                        let zigzagHeight = textHeight * 0.58
                        let topOffset = textHeight * (2.0/3.0)
                        Image("ZigZag")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(KKTheme.accent.opacity(0.7))
                            .frame(width: textWidth, height: zigzagHeight)
                            .offset(x: 0, y: topOffset)
                    }
                )
        }
        .frame(height: 36)
    }
}

private struct ScannerFrameView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(KKTheme.textSecondary.opacity(0.2), lineWidth: 2)
            PlusOverlay()
            Corners()
        }
    }
    private struct PlusOverlay: View {
        var body: some View {
            ZStack {
                Rectangle().fill(KKTheme.textSecondary.opacity(0.4)).frame(width: 2, height: 30)
                Rectangle().fill(KKTheme.textSecondary.opacity(0.4)).frame(width: 30, height: 2)
            }
        }
    }
    private struct Corners: View {
        var body: some View {
            GeometryReader { g in
                let w = g.size.width
                let h = g.size.height
                let l: CGFloat = 40
                let s: CGFloat = 4
                Path { p in
                    // top-left
                    p.move(to: CGPoint(x: 16, y: 16 + l))
                    p.addLine(to: CGPoint(x: 16, y: 16))
                    p.addLine(to: CGPoint(x: 16 + l, y: 16))
                    // top-right
                    p.move(to: CGPoint(x: w - 16 - l, y: 16))
                    p.addLine(to: CGPoint(x: w - 16, y: 16))
                    p.addLine(to: CGPoint(x: w - 16, y: 16 + l))
                    // bottom-left
                    p.move(to: CGPoint(x: 16, y: h - 16 - l))
                    p.addLine(to: CGPoint(x: 16, y: h - 16))
                    p.addLine(to: CGPoint(x: 16 + l, y: h - 16))
                    // bottom-right
                    p.move(to: CGPoint(x: w - 16 - l, y: h - 16))
                    p.addLine(to: CGPoint(x: w - 16, y: h - 16))
                    p.addLine(to: CGPoint(x: w - 16, y: h - 16 - l))
                }
                .strokedPath(.init(lineWidth: s, lineCap: .round, lineJoin: .round))
                .foregroundStyle(KKTheme.textPrimary)
            }
        }
    }
}

// Legacy crosshair overlay from previous app for exact look
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
                // TL
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

                // TR
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

                // BL
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

                // BR
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

                // Center plus
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

private struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(KKPrimaryButton())
    }
}

private struct FoundClubCard: View {
    let tenantName: String
    @Binding var email: String
    var isLoading: Bool
    var onSubmit: () -> Void
    var onRescan: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gevonden club").font(KKFont.body(14)).foregroundStyle(KKTheme.textSecondary)
            Text(tenantName).font(KKFont.heading(24)).fontWeight(.regular).kerning(-1.0).foregroundStyle(KKTheme.textPrimary)
            Text("E-mailadres teammanager").font(KKFont.body(14)).foregroundStyle(KKTheme.textSecondary)
            Text("Voer het e-mailadres in waarmee je als teammanager bekend bent bij deze club.")
                .font(KKFont.body(14)).foregroundStyle(KKTheme.textSecondary)
            TextField("a@b.nl", text: $email).textFieldStyle(.roundedBorder)
            Button(action: onSubmit) { isLoading ? AnyView(ProgressView().eraseToAnyView()) : AnyView(Text("Teams ophalen").frame(maxWidth: .infinity).eraseToAnyView()) }
                .buttonStyle(KKSecondaryButton())
            PrimaryActionButton(title: "Opnieuw scannen", systemImage: "qrcode.viewfinder", action: onRescan)
        }
        .kkCard()
    }
}

private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}

// MARK: - Reusable subtle action button
private struct SubtleActionButton: View {
    let icon: String
    let text: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.body)
                Text(text).font(KKFont.body(12))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(KKTheme.textSecondary)
        .padding(.horizontal, 24)
    }
}

// MARK: - Tenant Search Section
private struct TenantSearchSection: View {
    @EnvironmentObject var store: AppStore
    @Binding var searchQuery: String
    let results: [TenantSearchResult]
    let onTenantSelected: (TenantSearchResult) -> Void
    let onQRScanTapped: () -> Void
    
    private let maxDisplayedResults = 3
    
    private var limitedResults: [TenantSearchResult] {
        Array(results.prefix(maxDisplayedResults))
    }
    
    private var hasMoreResults: Bool {
        results.count > maxDisplayedResults
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header met QR scan icoon
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zoek je vereniging")
                        .font(KKFont.body(12))
                        .foregroundStyle(KKTheme.textSecondary)
                    
                    // Helpful instruction text (always visible)
                    Text("Typ de naam van je sportvereniging")
                        .font(KKFont.body(11))
                        .foregroundStyle(KKTheme.textSecondary)
                        .italic()
                }
                
                Spacer()
                
                // QR scan icoon (zoals bankieren apps)
                Button(action: onQRScanTapped) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 28))
                        .foregroundStyle(KKTheme.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            
            TextField("Bijv. VV Wilhelmus", text: $searchQuery)
                .kkTextField()
                .onChange(of: searchQuery) { _, newValue in 
                    store.searchTenants(query: newValue)
                }
            
            if !limitedResults.isEmpty || hasMoreResults || (!searchQuery.isEmpty && results.isEmpty) {
                VStack(spacing: 8) {
                ForEach(limitedResults) { tenant in
                    TenantRow(
                        tenant: tenant,
                        isEnabled: tenant.enrollmentOpen,
                        action: {
                            guard tenant.enrollmentOpen else { return }
                            onTenantSelected(tenant)
                        }
                    )
                }
                
                // Show message when there are more results
                if hasMoreResults {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(KKTheme.textSecondary.opacity(0.7))
                            .font(.system(size: 20))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Meer verenigingen gevonden")
                                .font(KKFont.body(13))
                                .foregroundStyle(KKTheme.textPrimary)
                                .fontWeight(.medium)
                            
                            Text("Er zijn \(results.count - maxDisplayedResults) meer resultaten. Typ meer letters voor een specifiekere zoekopdracht.")
                                .font(KKFont.body(13))
                                .foregroundStyle(KKTheme.textSecondary)
                        }
                        
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(KKTheme.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(KKTheme.textSecondary.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.top, 4)
                }
                
                // Show demo message when search has been performed but no results found
                if !searchQuery.isEmpty && results.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(KKTheme.textSecondary.opacity(0.7))
                            .font(.system(size: 20))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vereniging niet gevonden?")
                                .font(KKFont.body(13))
                                .foregroundStyle(KKTheme.textPrimary)
                                .fontWeight(.medium)
                            
                            Text(attributedDemoText())
                        }
                        .tint(KKTheme.accent)
                        
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(KKTheme.surface)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(KKTheme.textSecondary.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.top, 4)
                }
            }
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
    
    private func attributedDemoText() -> AttributedString {
        var result = AttributedString("Maakt jouw vereniging nog geen gebruik van Kantine Koning? Vraag dan vandaag nog een gratis demo aan op ")
        result.foregroundColor = KKTheme.textSecondary
        if let comfortaaFont = UIFont(name: "Comfortaa-Regular", size: 12) {
            result.font = Font(comfortaaFont)
        } else {
            result.font = Font(UIFont.systemFont(ofSize: 12, weight: .regular))
        }
        
        var link = AttributedString("www.kantinekoning.com/plan-een-demo")
        link.foregroundColor = KKTheme.accent
        if let comfortaaMedium = UIFont(name: "Comfortaa-Medium", size: 12) {
            link.font = Font(comfortaaMedium)
        } else {
            link.font = Font(UIFont.systemFont(ofSize: 12, weight: .medium))
        }
        
        result.append(link)
        return result
    }
}

// MARK: - Tenant Row
private struct TenantRow: View {
    let tenant: TenantSearchResult
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    // Club logo
                    if let logoUrlString = tenant.clubLogoUrl,
                       !logoUrlString.isEmpty,
                       let logoUrl = URL(string: logoUrlString) {
                        CachedAsyncImage(url: logoUrl) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            Image(systemName: "building.2")
                                .foregroundStyle(KKTheme.textSecondary)
                        }
                        .frame(width: 40, height: 40)
                        .cornerRadius(8)
                    } else {
                        // Fallback icon als geen logo (exact dezelfde styling voor uitlijning)
                        Image(systemName: "building.2")
                            .foregroundStyle(KKTheme.textSecondary)
                            .frame(width: 40, height: 40)
                            .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tenant.name)
                            .font(KKFont.body(16))
                            .foregroundStyle(isEnabled ? KKTheme.textPrimary : KKTheme.textSecondary)
                        
                        Text(tenant.slug)
                            .font(KKFont.body(12))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    if isEnabled {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(KKTheme.textSecondary)
                    } else {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.red)
                    }
                }
                
                // Toon seizoen bericht als gesloten
                if !isEnabled {
                    Text(tenant.enrollmentMessage ?? "Inschrijving momenteel gesloten")
                        .font(KKFont.body(11))
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }
            .padding()
            .background(isEnabled ? KKTheme.surface : KKTheme.surface.opacity(0.5))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isEnabled ? Color.clear : Color.red.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.6)
    }
}

// MARK: - Diagonal Shape for Background
private struct DiagonalShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start linksboven
        path.move(to: CGPoint(x: 0, y: 0))
        
        // Rechts boven
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        
        // Rechts naar beneden (iets hoger dan onderkant)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 60))
        
        // Schuin naar links beneden (onderkant)
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        
        // Terug naar start
        path.closeSubpath()
        
        return path
    }
}


