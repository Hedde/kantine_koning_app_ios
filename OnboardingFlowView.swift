//
//  OnboardingFlowView.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 16/08/2025.
//

import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject var model: AppModel
    @State private var showScanner = false
    @State private var navigateTeam = false
    @State private var navigateEmail = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "crown.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)
                Text("Welkom bij Kantine Koning")
                    .font(.title.bold())
                Text("Scan de QR-code van je club om je team te kiezen en meldingen te ontvangen wanneer jou team is ingedeeld.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)

                Button(action: { showScanner = true }) {
                    Label("Scan QR-code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)

                if let invite = model.invite {
                    VStack(spacing: 8) {
                        Text("Gevonden club: \(invite.tenantName)")
                        NavigationLink("Kies team", isActive: $navigateTeam) {
                            TeamPickerView(invite: invite) { team in
                                model.selectTeam(team)
                                navigateEmail = true
                            }
                        }
                        .buttonStyle(.bordered)
                        .onAppear { navigateTeam = true }
                    }
                    .padding()
                }

                NavigationLink(isActive: $navigateEmail) {
                    EmailEntryView()
                } label: { EmptyView() }

                Spacer()
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { code in
                    showScanner = false
                    parseInvite(from: code)
                }
                .ignoresSafeArea()
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }

    private func parseInvite(from code: String) {
        // Accept either URL or plain text. Try to extract tenant and teams.
        if let url = URL(string: code), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let tenantId = comps.queryItems?.first(where: { $0.name == "tenant" })?.value ?? url.host ?? "tenant_demo"
            let tenantName = comps.queryItems?.first(where: { $0.name == "tenant_name" })?.value ?? "Jouw Club"
            let teamsParam = comps.queryItems?.first(where: { $0.name == "teams" })?.value
            let teams: [AppModel.Team]
            if let teamsParam {
                let parts = teamsParam.split(separator: ",").map(String.init)
                teams = parts.enumerated().map { index, name in
                    AppModel.Team(id: "team_\(index+1)", name: name)
                }
            } else {
                teams = [
                    AppModel.Team(id: "team_1", name: "JO13-1"),
                    AppModel.Team(id: "team_2", name: "MO15-2"),
                    AppModel.Team(id: "team_3", name: "Heren 1")
                ]
            }
            model.handleScannedInvite(.init(tenantId: tenantId, tenantName: tenantName, allowedTeamIds: teams))
        } else {
            // Fallback
            model.handleScannedInvite(.init(tenantId: "tenant_demo", tenantName: "Demo Club", allowedTeamIds: [
                AppModel.Team(id: "team_1", name: "JO13-1"),
                AppModel.Team(id: "team_2", name: "MO15-2")
            ]))
        }
    }
}

struct TeamPickerView: View {
    let invite: AppModel.TenantInvite
    let onSelect: (AppModel.Team) -> Void

    var body: some View {
        List(invite.allowedTeamIds) { team in
            Button(action: { onSelect(team) }) {
                HStack {
                    Image(systemName: "person.3.fill")
                    Text(team.name)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle("Kies team")
    }
}

struct EmailEntryView: View {
    @EnvironmentObject var model: AppModel
    @State private var email: String = ""
    @State private var sending = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(header: Text("E-mailadres")) {
                TextField("naam@club.nl", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            Section {
                Button {
                    sending = true
                    model.submitEmail(email) { result in
                        sending = false
                        if case .failure(let error) = result {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    if sending { ProgressView() } else { Text("Stuur magic link") }
                }
                .disabled(sending || email.isEmpty)
            }
        }
        .navigationTitle("Email")
    }
}

struct EnrollmentPendingView: View {
    @EnvironmentObject var model: AppModel
    @State private var simulating = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "envelope.open.fill").font(.system(size: 64))
            Text("Check je email")
                .font(.title3.bold())
            Text("Open de link op dit toestel om je aan te melden.")
                .foregroundStyle(.secondary)
            Button("Simuleer magic link") {
                simulating = true
                model.simulateOpenMagicLink { _ in simulating = false }
            }
            .buttonStyle(.borderedProminent)
            .disabled(simulating)
            Spacer()
        }
        .padding()
        .navigationTitle("Bevestigen")
    }
}


