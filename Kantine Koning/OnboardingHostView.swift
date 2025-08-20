import SwiftUI
import AVFoundation

struct OnboardingHostView: View {
    @EnvironmentObject var store: AppStore
    @State private var email: String = ""
    @State private var tenant: TenantID = "vvwilhelmus"
    @State private var submitting = false
    @State private var errorText: String?
    @State private var searchQuery: String = ""
    @State private var selectedMemberTeams: Set<TeamID> = []
    @State private var selectedManagerTeams: Set<TeamID> = []
    @State private var scanning = false
    @State private var scannedOnce = false
    @State private var step: EnrollStep? = nil
    @State private var selectedRole: EnrollStep? = nil
    @State private var keyboardHeight: CGFloat = 0
    private var safeAreaBottom: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HeaderHero()

                if let scanned = store.onboardingScan {
                    if step == nil {
                        // Step 1: Role selection after scan
                        ClubEnrollContainer(
                            tenantName: scanned.name,
                            selectedRole: $selectedRole,
                            onContinue: { if let sel = selectedRole { step = sel } }
                        )
                        .padding(.bottom, 8)
                        // Opnieuw scannen - want misschien verkeerde QR gescand
                        SubtleActionButton(icon: "qrcode.viewfinder", text: "Opnieuw scannen") {
                            store.onboardingScan = nil
                            scanning = true
                        }
                    } else if step == .manager {
                        if store.searchResults.isEmpty {
                            // Step 2a: Manager email verification
                            ManagerVerifySection(email: $email, isLoading: submitting, errorText: $errorText, onSubmit: {
                                submitting = true
                                errorText = nil
                                store.submitEmail(email, for: tenant, selectedTeamCodes: []) { result in
                                    submitting = false
                                    if case .failure(let err) = result { errorText = ErrorTranslations.translate(err) }
                                }
                            })
                            .padding(.bottom, 8)
                            // Terug - want misschien toch verenigingslid willen worden
                            SubtleActionButton(icon: "chevron.left", text: "Terug") { step = nil }
                        } else {
                            // Step 2b: Manager team selection
                            ManagerTeamPickerSection(allowed: sortedAllowedTeams(),
                                                     selected: $selectedManagerTeams,
                                                     onSubmit: submitManagerTeams,
                                                     enrolledIds: enrolledTeamIdsForTenant(tenant))
                            .padding(.bottom, 8)
                            // Terug - want misschien andere teams willen of email wijzigen
                            SubtleActionButton(icon: "chevron.left", text: "Terug") { 
                                store.searchResults = []
                                selectedManagerTeams = []
                            }
                        }
                    } else if step == .member {
                        // Step 2c: Member team search
                        MemberSearchSection(
                            tenant: tenant,
                            searchQuery: $searchQuery,
                            results: store.searchResults,
                            selected: $selectedMemberTeams,
                            onSearch: { q in store.searchTeams(tenant: tenant, query: q) },
                            onSubmit: registerMember
                        )
                        .padding(.bottom, 8)
                        // Terug - want misschien toch teammanager willen worden
                        SubtleActionButton(icon: "chevron.left", text: "Terug") { step = nil }
                    }
                } else {
                    // Old design: square scanner container with overlay
                    VStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.clear)
                                .aspectRatio(1.0, contentMode: .fit)
                                .overlay(
                                    Group {
                                        if scanning {
                                            ZStack {
                                                QRScannerView(isActive: scanning) { code in
                                                    handleScanned(code)
                                                }
                                                CrosshairOverlay()
                                            }
                                        } else {
                                            CrosshairOverlay()
                                        }
                                    }
                                )
                        }
                        .padding(.horizontal, 32)

                        Button(action: scanButtonTapped) {
                            Label(scannedOnce ? "Opnieuw scannen" : "Scan QR-code", systemImage: "qrcode.viewfinder")
                        }
                            .buttonStyle(KKPrimaryButton())
                        .padding(.horizontal, 24)
                    }
                }


                
                // Show cancel only if there are existing enrollments AND we're not in a scanned state
                if !store.model.tenants.isEmpty && store.onboardingScan == nil {
                    Button {
                        store.appPhase = .registered
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Annuleren")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KKTheme.textSecondary)
                    .padding(.top, 16)
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(minHeight: UIScreen.main.bounds.height - 1)
        }
        .background(KKTheme.surface)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: keyboardHeight)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let adjusted = max(0, frame.height - safeAreaBottom - 80)
                withAnimation(.easeOut(duration: 0.2)) { keyboardHeight = adjusted }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardHeight = 0 }
        }
    }

    private func request() {
        submitting = true
        store.submitEmail(email, for: tenant, selectedTeamCodes: []) { result in
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

    private func registerMember() {
        guard !selectedMemberTeams.isEmpty else { return }
        print("[Member] 🎯 Registering member with teams: \(Array(selectedMemberTeams))")
        // Use team codes, not IDs for backend
        let teamCodes = store.searchResults.filter { selectedMemberTeams.contains($0.id) }.compactMap { $0.code ?? $0.id }
        print("[Member] 📋 Team codes to register: \(teamCodes)")
        store.registerMember(tenantSlug: tenant, tenantName: store.onboardingScan?.name ?? tenant, teamIds: teamCodes) { result in
            if case .failure(let err) = result { errorText = ErrorTranslations.translate(err) }
        }
    }

    private func submitManagerTeams() {
        guard !selectedManagerTeams.isEmpty else { return }
        submitting = true
        store.submitEmail(email, for: tenant, selectedTeamCodes: Array(selectedManagerTeams)) { result in
            submitting = false
            if case .failure(let err) = result { errorText = ErrorTranslations.translate(err) }
        }
    }
}

// MARK: - Helpers
private extension OnboardingHostView {
    func scanButtonTapped() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startScanning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { if granted { startScanning() } }
            }
        default:
            // Keep silent; could add settings deep link
            break
        }
    }

    func startScanning() {
        print("[Onboarding] 📷 Starting scanner - clearing all cached state")
        // Always clear all onboarding state for fresh start
        store.onboardingScan = nil
        store.searchResults = []
        scanning = true
        selectedRole = nil
        step = nil
        selectedMemberTeams = []
        selectedManagerTeams = []
        searchQuery = ""
        email = ""
        errorText = nil
        print("[Onboarding] ✅ All onboarding state cleared for fresh scan")
    }

    func handleScanned(_ code: String) {
        print("[QR] 📦 Raw payload=\(code)")
        scannedOnce = true
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
        if let url = URL(string: code), url.scheme == "kantinekoning" {
            print("[QR] 🎯 Direct scheme host=\(url.host ?? "nil") path=\(url.path)")
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if url.host == "tenant",
               let slug = comps?.queryItems?.first(where: { $0.name == "slug" })?.value,
               let name = comps?.queryItems?.first(where: { $0.name == "name" })?.value {
                print("[QR] ✅ Parsed direct slug=\(slug) name=\(name)")
                tenant = slug
                store.handleQRScan(slug: slug, name: name)
                return
            }
            if url.host == "invite",
               let slug = comps?.queryItems?.first(where: { $0.name == "tenant" })?.value,
               var name = comps?.queryItems?.first(where: { $0.name == "tenant_name" })?.value {
                // Replace '+' with space, then percent-decode
                name = name.replacingOccurrences(of: "+", with: " ")
                let decodedName = name.removingPercentEncoding ?? name
                print("[QR] ✅ Parsed invite slug=\(slug) name=\(decodedName)")
                tenant = slug
                store.handleQRScan(slug: slug, name: decodedName)
                return
            }
            if let items = comps?.queryItems {
                print("[QR] ℹ️ Direct query items: \(items.map{ "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", "))")
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
            print("[QR] ✅ Parsed nested slug=\(slug) name=\(name)")
            tenant = slug
            store.handleQRScan(slug: slug, name: name)
            return
        }
        print("[QR] ❌ Could not parse QR payload")
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
        .padding(.horizontal, 12)
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
                        .padding(.leading, 12)
                        .font(KKFont.body(16))
                }
                TextField("", text: $email)
                    .padding(12)
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
                Text(errorText)
                    .font(KKFont.body(12))
                    .foregroundStyle(.red)
            }
            Button(action: onSubmit) { 
                if isLoading {
                    HStack {
                        ProgressView()
                            .tint(KKTheme.accent)
                        Text("Controleren...")
                    }
                } else {
                    Text("Teams ophalen")
                }
            }
            .disabled(isLoading)
            .buttonStyle(KKSecondaryButton())
        }
        .kkCard()
        .padding(.horizontal, 12)
    }
}

private struct MemberSearchSection: View {
    let tenant: TenantID
    @Binding var searchQuery: String
    let results: [SearchTeam]
    @Binding var selected: Set<TeamID>
    let onSearch: (String) -> Void
    let onSubmit: () -> Void
    
    private let maxDisplayedResults = 3
    private var limitedResults: [SearchTeam] {
        Array(results.prefix(maxDisplayedResults))
    }
    private var hasMoreResults: Bool {
        results.count > maxDisplayedResults
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zoek je team(s)").font(KKFont.body(12)).foregroundStyle(KKTheme.textSecondary)
            
            // Helpful instruction text
            if searchQuery.isEmpty {
                Text("Teams beginnen meestal met JO13, MO11, 1, 2, 3, enzovoorts")
                    .font(KKFont.body(11))
                    .foregroundStyle(KKTheme.textSecondary)
                    .italic()
            }
            
            TextField("Bijv. JO11-3", text: $searchQuery)
                .kkTextField()
                .onChange(of: searchQuery) { _, newValue in onSearch(newValue) }
            
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
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(KKTheme.textSecondary)
                        Text("Er zijn \(results.count - maxDisplayedResults) meer resultaten. Typ meer letters voor een specifiekere zoekopdracht.")
                            .font(KKFont.body(12))
                            .foregroundStyle(KKTheme.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(KKTheme.surface)
                    .cornerRadius(6)
                }
            }
            
            Button("Aanmelden", action: onSubmit)
                .disabled(selected.isEmpty)
                .buttonStyle(KKPrimaryButton())
        }
        .kkCard()
        .padding(.horizontal, 12)
    }
    private func toggle(_ id: TeamID) { if selected.contains(id) { selected.remove(id) } else { selected.insert(id) } }
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
        .padding(.horizontal, 12)
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
        // Use current model enrollment to gray out already followed teams
        let ids = store.model.tenants[tenantId]?.teams.map { $0.id } ?? []
        return Set(ids)
    }
}
private struct HeaderHero: View {
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

            Text("Scan de QR-code van je club om je team(s) te kiezen en meldingen te ontvangen wanneer jou team is ingedeeld.")
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


