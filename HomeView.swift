//
//  HomeView.swift
//  Kantine Koning
//
//  Created by Hedde van der Heide on 16/08/2025.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var showVolunteerSheet = false
    @State private var volunteerNames: [String] = [""]
    @State private var submitting = false
    @State private var submitError: String?

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Aankomende diensten")) {
                    ForEach(model.upcomingDiensten) { dienst in
                        DienstRow(dienst: dienst) {
                            model.unregister(from: dienst) { _ in }
                        }
                    }
                }
            }
            .navigationTitle("Kantine Koning")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) { model.resetAll() } label: { Image(systemName: "arrow.uturn.left.circle") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { model.loadUpcomingDiensten() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .onChange(of: model.pendingAction) { _, newValue in
                if case .shiftVolunteer = newValue { showVolunteerSheet = true }
            }
            .sheet(isPresented: $showVolunteerSheet, onDismiss: { model.pendingAction = nil }) {
                VolunteerSubmissionView(isPresented: $showVolunteerSheet)
                    .environmentObject(model)
            }
        }
    }
}

struct DienstRow: View {
    let dienst: Dienst
    let onUnregister: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dienst.title).font(.headline)
                Text(Self.dateFormatter.string(from: dienst.date))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Uitschrijven", action: onUnregister).buttonStyle(.bordered)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
}

struct VolunteerSubmissionView: View {
    @EnvironmentObject var model: AppModel
    @Binding var isPresented: Bool
    @State private var names: [String] = [""]
    @State private var submitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Vrijwilligers")) {
                    ForEach(names.indices, id: \.self) { index in
                        TextField("Naam", text: Binding(
                            get: { names[index] },
                            set: { names[index] = $0 }
                        ))
                    }
                    Button(action: { names.append("") }) {
                        Label("Naam toevoegen", systemImage: "plus.circle")
                    }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Bevestig hulp")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuleer") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard case let .shiftVolunteer(token) = model.pendingAction else { return }
                        submitting = true
                        let clean = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        model.backend.submitVolunteers(actionToken: token, names: clean) { result in
                            DispatchQueue.main.async {
                                submitting = false
                                switch result {
                                case .success:
                                    isPresented = false
                                    model.pendingAction = nil
                                case .failure(let error):
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                    } label: { if submitting { ProgressView() } else { Text("Verstuur") } }
                }
            }
        }
    }
}


