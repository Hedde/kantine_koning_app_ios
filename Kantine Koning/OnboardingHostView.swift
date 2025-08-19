import SwiftUI

struct OnboardingHostView: View {
    @EnvironmentObject var store: AppStore
    @State private var email: String = ""
    @State private var tenant: TenantID = "vvwilhelmus"
    @State private var teamCode: TeamID = "21241"
    @State private var submitting = false
    @State private var errorText: String?
    @State private var searchQuery: String = ""
    @State private var selectedMemberTeams: Set<TeamID> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // QR Scanner
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scan vereniging QR").font(.title3)
                    QRScannerView { value in
                        // Expected payload: kantinekoning://tenant?slug=...&name=...
                        if let url = URL(string: value), url.scheme == "kantinekoning" {
                            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                            if url.host == "tenant",
                               let slug = comps?.queryItems?.first(where: { $0.name == "slug" })?.value,
                               let name = comps?.queryItems?.first(where: { $0.name == "name" })?.value {
                                tenant = slug
                                store.handleQRScan(slug: slug, name: name)
                            }
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .kkCard()
                Text("Scan QR → simplified stub").font(.headline)
                // Manager flow
                VStack(alignment: .leading, spacing: 12) {
                    Text("Teammanager").font(.title3)
                    TextField("Email", text: $email).textFieldStyle(.roundedBorder)
                    HStack { Text("Tenant"); TextField("slug", text: $tenant).textFieldStyle(.roundedBorder) }
                    HStack { Text("Team" ); TextField("code", text: $teamCode).textFieldStyle(.roundedBorder) }
                    Button(action: request) { submitting ? ProgressView() : Text("Vraag magic link aan").frame(maxWidth: .infinity) }
                        .buttonStyle(KKPrimaryButton())
                }
                .kkCard()

                // Member flow
                VStack(alignment: .leading, spacing: 12) {
                    Text("Verenigingslid").font(.title3)
                    HStack { Text("Tenant"); TextField("slug", text: $tenant).textFieldStyle(.roundedBorder) }
                    TextField("Zoek team…", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: searchQuery) { q in store.searchTeams(tenant: tenant, query: q) }
                    if !store.searchResults.isEmpty {
                        ForEach(store.searchResults, id: \.id) { t in
                            Button(action: { toggleSelect(t) }) {
                                HStack {
                                    VStack(alignment: .leading) { Text(t.name); if let code = t.code { Text(code).font(.caption).foregroundColor(.secondary) } }
                                    Spacer()
                                    if selectedMemberTeams.contains(t.id) { Image(systemName: "checkmark.circle.fill").foregroundColor(KKTheme.accent) }
                                }
                            }
                        }
                        Button("Volg geselecteerde teams") { registerMember() }
                            .buttonStyle(KKPrimaryButton())
                    }
                }
                .kkCard()

                if let e = errorText { Text(e).foregroundColor(.red).font(.footnote) }
                Divider().padding(.vertical)
                Button("Simulateer magic link openen") { simulateOpenMagicLink() }
            }
            .padding()
        }
    }

    private func request() {
        submitting = true
        store.submitEmail(email, for: tenant, selectedTeamCodes: [teamCode]) { result in
            submitting = false
            if case .failure(let err) = result { errorText = err.localizedDescription }
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
        store.registerMember(tenantSlug: tenant, tenantName: tenant, teamIds: Array(selectedMemberTeams)) { result in
            if case .failure(let err) = result { errorText = err.localizedDescription }
        }
    }
}


