import SwiftUI

struct HomeHostView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationView {
            List {
                NotificationPermissionCard()
                Section("Verenigingen") {
                    ForEach(Array(store.model.tenants.values), id: \.slug) { tenant in
                        NavigationLink(destination: TeamsView(tenant: tenant).environmentObject(store)) {
                            VStack(alignment: .leading) {
                                Text(tenant.name).font(.headline)
                                Text(tenant.slug).foregroundColor(.secondary).font(.caption)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { store.removeTenant(tenant.slug) } label: { Label("Verwijder", systemImage: "trash") }
                        }
                    }
                }
                if !store.upcoming.isEmpty {
                    Section("Diensten") {
                        ForEach(store.upcoming, id: \.id) { d in
                            NavigationLink(destination: DienstDetail(dienst: d).environmentObject(store)) {
                                VStack(alignment: .leading) {
                                    Text(d.status)
                                    Text(d.startTime, style: .date).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kantine Koning")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("Reset") { store.resetAll() }
                        Button("Refresh") { store.refreshDiensten() }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if store.pendingCTA != nil {
                        Button("Open actie") { store.performCTA() }
                            .buttonStyle(KKPrimaryButton())
                    }
                }
            }
        }
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
    @EnvironmentObject var store: AppStore
    var body: some View {
        List(tenant.teams, id: \.id) { team in
            VStack(alignment: .leading) {
                Text(team.name)
                Text(team.id).font(.caption).foregroundColor(.secondary)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { store.removeTeam(team.id, from: tenant.slug) } label: { Label("Verwijder", systemImage: "trash") }
            }
        }
        .navigationTitle(tenant.name)
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
                    }
                }
                HStack {
                    TextField("Naam", text: $name)
                    Button("Voeg toe") { add() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || working)
                }
                if let e = errorText { Text(e).foregroundColor(.red).font(.footnote) }
            }
        }
        .navigationTitle("Dienst")
    }

    private func add() {
        working = true
        store.addVolunteer(tenant: dienst.tenantId, dienstId: dienst.id, name: name) { result in
            working = false
            if case .failure(let err) = result { errorText = err.localizedDescription }
        }
    }

    private func remove(_ v: String) {
        working = true
        store.removeVolunteer(tenant: dienst.tenantId, dienstId: dienst.id, name: v) { result in
            working = false
            if case .failure(let err) = result { errorText = err.localizedDescription }
        }
    }
}


