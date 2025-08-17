//
//  HomeView.swift
//  Kantine Koning
//
//  Created by AI Assistant on 16/08/2025.
//

import SwiftUI





struct HomeView: View {
	@EnvironmentObject var model: AppModel
	@State private var showVolunteerSheet = false
	@State private var selectedTenant: String?
	@State private var selectedTeam: String?
	@State private var showSettings = false

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				// Top Navigation Bar
				TopNavigationBar(
					onHomeAction: {
						selectedTenant = nil
						selectedTeam = nil
						showSettings = false
					},
					onSettingsAction: { showSettings.toggle() }
				)
				
				// Main Content
				if showSettings {
					SettingsView(onClose: { showSettings = false })
				} else if let selectedTenant = selectedTenant, let selectedTeam = selectedTeam {
					// Show diensten for selected team
					TeamDienstenView(tenantId: selectedTenant, teamId: selectedTeam)
				} else if let selectedTenant = selectedTenant {
					// Show teams for selected tenant
					TenantTeamsView(tenantId: selectedTenant) { teamId in
						selectedTeam = teamId
					}
				} else {
					// Show tenant selection
					TenantSelectionView { tenantId in
						selectedTenant = tenantId
						// If tenant has only one team, auto-select it
						let tenantEnrollments = model.enrollments.filter { $0.tenantId == tenantId }
						let uniqueTeams = Set(tenantEnrollments.flatMap { $0.teamIds })
						if uniqueTeams.count == 1, let singleTeam = uniqueTeams.first {
							selectedTeam = singleTeam
						}
					}
				}

				// Footer back control (subtle), shown only when not at root
				if (selectedTenant != nil) && (selectedTeam == nil) {
					Button {
						if selectedTeam != nil {
							selectedTeam = nil
						} else if selectedTenant != nil {
							selectedTenant = nil
						}
					} label: {
						HStack(spacing: 6) {
							Image(systemName: "chevron.left")
								.font(.body)
							Text("Terug")
								.font(KKFont.body(12))
						}
					}
					.buttonStyle(.plain)
					.foregroundStyle(KKTheme.textSecondary)
					.padding(.vertical, 12)
					.padding(.horizontal, 24)
				}
			}
			.background(KKTheme.surface.ignoresSafeArea())
			.onChange(of: model.pendingAction) { _, newValue in
				if case .shiftVolunteer = newValue { showVolunteerSheet = true }
			}
			.sheet(isPresented: $showVolunteerSheet) {
				if case .shiftVolunteer(let action) = model.pendingAction {
					VolunteerSubmissionView(action: action)
				}
			}
			.onReceive(model.$deepLinkNavigation) { navigation in
				if let nav = navigation {
					selectedTenant = nav.tenantId
					selectedTeam = nav.teamId
					// Clear the deep link after handling
					model.deepLinkNavigation = nil
				}
			}
		}
	}
}

// MARK: - Top Navigation Bar
struct TopNavigationBar: View {
	let onHomeAction: () -> Void
	let onSettingsAction: () -> Void
	
	var body: some View {
		HStack(spacing: 12) {
			Button(action: onHomeAction) {
				Image(systemName: "house.fill")
					.font(.title2)
					.foregroundColor(KKTheme.textSecondary)
			}
			
			Spacer()
			
			BrandAssets.logoImage()
				.resizable()
				.scaledToFit()
				.frame(width: 44, height: 44)
			
			Spacer()
			
			Button(action: onSettingsAction) {
				Image(systemName: "gearshape.fill")
					.font(.title2)
					.foregroundColor(KKTheme.textSecondary)
			}
		}
		.padding(.horizontal, 24)
		.padding(.vertical, 16)
		.background(KKTheme.surface)
		.overlay(
			Rectangle()
				.frame(height: 1)
				.foregroundColor(KKTheme.surfaceAlt)
				.padding(.top, 56)
		)
	}
}

// MARK: - Tenant Selection View
struct TenantSelectionView: View {
	@EnvironmentObject var model: AppModel
	let onTenantSelected: (String) -> Void
	
	var uniqueTenants: [(String, String)] {
		let tenants = model.enrollments.map { ($0.tenantId, $0.tenantName) }
		let uniqueSet = Set(tenants.map { "\($0.0)|\($0.1)" })
		return uniqueSet.compactMap { combined in
			let parts = combined.split(separator: "|")
			guard parts.count == 2 else { return nil }
			return (String(parts[0]), String(parts[1]))
		}.sorted { $0.1 < $1.1 }
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 24) {
				Spacer(minLength: 24)
				
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
					ForEach(uniqueTenants, id: \.0) { tenantId, tenantName in
						SwipeableRow(
							onTap: { onTenantSelected(tenantId) },
							onDelete: { 
								model.removeEnrollments(for: tenantId)
							}
						) {
							HStack {
								VStack(alignment: .leading, spacing: 4) {
									Text(tenantName)
										.font(KKFont.title(18))
										.foregroundStyle(KKTheme.textPrimary)
									Text(teamCountText(for: tenantId))
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
				
				Spacer(minLength: 24)
			}
		}
	}
	
	private func teamCountText(for tenantId: String) -> String {
		let teamCount = Set(model.enrollments.filter { $0.tenantId == tenantId }.flatMap { $0.teamIds }).count
		return teamCount == 1 ? "1 team" : "\(teamCount) teams"
	}
}

// MARK: - Tenant Teams View
struct TenantTeamsView: View {
	@EnvironmentObject var model: AppModel
	let tenantId: String
	let onTeamSelected: (String) -> Void
	
	var tenantName: String {
		model.enrollments.first { $0.tenantId == tenantId }?.tenantName ?? "Club"
	}
	
	var teams: [(String, String)] {
		let teamIds = Set(model.enrollments.filter { $0.tenantId == tenantId }.flatMap { $0.teamIds })
		return teamIds.compactMap { teamId in
			// Match by code, id, or pk
			let match = model.upcomingDiensten.first { d in
				guard let t = d.team else { return false }
				return t.id == teamId || t.code == teamId || t.pk == teamId
			}
			let teamName = match?.team?.naam ?? teamIdToName(teamId)
			if match == nil {
				print("🔎 No diensten match enrollment teamId=\(teamId); sample of first team objects:")
				for d in model.upcomingDiensten.prefix(5) {
					if let t = d.team { print("   → dienst.team id=\(t.id) code=\(t.code ?? "-") pk=\(t.pk ?? "-") naam=\(t.naam)") }
				}
			}
			return (teamId, teamName)
		}.sorted { $0.1 < $1.1 }
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 24) {
				Spacer(minLength: 24)
				
				VStack(spacing: 8) {
					Text("SELECTEER TEAM")
						.font(KKFont.heading(24))
						.fontWeight(.regular)
						.kerning(-1.0)
						.foregroundStyle(KKTheme.textPrimary)
					
					Text("Bij \(tenantName)")
						.font(KKFont.title(16))
						.foregroundStyle(KKTheme.textSecondary)
				}
				.multilineTextAlignment(.center)
				
				VStack(spacing: 8) {
					ForEach(teams, id: \.0) { teamId, teamName in
						SwipeableRow(
							onTap: { onTeamSelected(teamId) },
							onDelete: { 
								model.removeTeam(teamId: teamId, from: tenantId)
							}
						) {
							HStack {
								VStack(alignment: .leading, spacing: 4) {
									Text(teamName)
										.font(KKFont.title(18))
										.foregroundStyle(KKTheme.textPrimary)
									Text(dienstCountText(for: teamId))
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
				
				Spacer(minLength: 24)
			}
		}
	}
	
	private func dienstCountText(for teamId: String) -> String {
		let dienstCount = model.upcomingDiensten.filter { $0.team?.id == teamId }.count
		return dienstCount == 0 ? "Geen diensten" : dienstCount == 1 ? "1 dienst" : "\(dienstCount) diensten"
	}
}

// MARK: - Team Diensten View
struct TeamDienstenView: View {
	@EnvironmentObject var model: AppModel
	let tenantId: String
	let teamId: String
	
	var teamName: String {
		model.upcomingDiensten.first { $0.team?.id == teamId }?.team?.naam ?? teamIdToName(teamId)
	}
	
	var diensten: [Dienst] {
		let filtered = model.upcomingDiensten.filter {
			guard $0.tenant_id == tenantId else { return false }
			guard let team = $0.team else { return false }
			return team.id == teamId || team.code == teamId || team.pk == teamId
		}
		let now = Date()
		let future = filtered.filter { $0.start_tijd >= now }.sorted { $0.start_tijd < $1.start_tijd }
		let past = filtered.filter { $0.start_tijd < now }.sorted { $0.start_tijd > $1.start_tijd }
		return future + past
	}
	
	var body: some View {
		ScrollView {
			VStack(spacing: 24) {
				Spacer(minLength: 24)
				
				VStack(spacing: 8) {
					Text(teamName.uppercased())
						.font(KKFont.heading(24))
						.fontWeight(.regular)
						.kerning(-1.0)
						.foregroundStyle(KKTheme.textPrimary)
					
					Text("Aankomende diensten")
						.font(KKFont.title(16))
						.foregroundStyle(KKTheme.textSecondary)
				}
				.multilineTextAlignment(.center)
				
				if diensten.isEmpty {
					VStack(spacing: 16) {
						Image(systemName: "calendar.badge.exclamationmark")
							.font(.system(size: 48))
							.foregroundStyle(KKTheme.textSecondary)
						
						VStack(spacing: 8) {
							Text("Geen diensten gevonden")
								.font(KKFont.title(18))
								.foregroundStyle(KKTheme.textPrimary)
							Text("Er zijn momenteel geen aankomende diensten voor dit team.")
								.font(KKFont.body(14))
								.foregroundStyle(KKTheme.textSecondary)
								.multilineTextAlignment(.center)
						}
					}
					.padding(.vertical, 32)
				} else {
					VStack(spacing: 12) {
						ForEach(diensten) { dienst in
							DienstCard(dienst: dienst, model: model)
								.opacity(dienst.start_tijd < Date() ? 0.5 : 1.0)
						}
					}
					.padding(.horizontal, 16)
				}
				
				Spacer(minLength: 24)
			}
		}
		.refreshable {
			model.loadUpcomingDiensten()
		}
	}
}

// MARK: - Dienst Card
struct DienstCard: View {
	let dienst: Dienst
	let model: AppModel
	@State private var showAddVolunteer = false
	@State private var newVolunteerName = ""
	@State private var volunteers: [String] = []
	@State private var showCelebration = false
	@State private var confettiTrigger = 0
	
	private var isManager: Bool {
		guard let teamId = dienst.team?.id else { return false }
		return model.roleFor(tenantId: dienst.tenant_id, teamId: teamId) == .manager
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			// Header with date and time
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text(dateText)
						.font(KKFont.title(18))
						.foregroundStyle(KKTheme.textPrimary)
					
					Spacer()
					
					// Location badge
					HStack(spacing: 4) {
						Image(systemName: "location.fill")
							.font(.caption)
						Text(locationText)
							.font(KKFont.body(12))
					}
					.padding(.horizontal, 8)
					.padding(.vertical, 4)
					.background(Color.blue.opacity(0.1))
					.foregroundStyle(Color.blue)
					.cornerRadius(8)
				}
				
				HStack(spacing: 4) {
					Image(systemName: "clock")
						.font(.caption)
						.foregroundStyle(KKTheme.textSecondary)
					Text(timeRangeText)
						.font(KKFont.body(14))
						.foregroundStyle(KKTheme.textSecondary)
				}
			}
			
			// Volunteer status and progress
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("Bemanning")
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
					
					Spacer()
					
					// Status indicator
					HStack(spacing: 4) {
						Text("\(volunteers.count)/\(dienst.minimum_bemanning)")
							.font(KKFont.body(12))
							.fontWeight(.medium)
						
						Circle()
							.fill(statusColor)
							.frame(width: 8, height: 8)
					}
					.foregroundStyle(statusColor)
				}
				
				// Progress bar
				ProgressView(value: Double(volunteers.count), total: Double(dienst.minimum_bemanning))
					.tint(statusColor)
					.background(Color.gray.opacity(0.2))
					.cornerRadius(4)
			}
			
			// Volunteers list
			if !volunteers.isEmpty {
				VStack(alignment: .leading, spacing: 8) {
					Text("Aangemeld:")
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
					
					LazyVStack(spacing: 6) {
						ForEach(volunteers, id: \.self) { volunteer in
							HStack {
								HStack(spacing: 8) {
									Image(systemName: "person.fill")
										.font(.caption)
										.foregroundStyle(Color.green)
									Text(volunteer)
										.font(KKFont.body(14))
										.foregroundStyle(KKTheme.textPrimary)
								}
								
								Spacer()
								
								if isManager {
									Button(action: { removeVolunteer(volunteer) }) {
										Image(systemName: "minus.circle.fill")
											.foregroundStyle(Color.red)
											.font(.title3)
									}
								}
							}
							.padding(.horizontal, 12)
							.padding(.vertical, 8)
							.background(Color.green.opacity(0.1))
							.cornerRadius(8)
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
				.overlay(
					RoundedRectangle(cornerRadius: 12)
						.stroke(Color.green.opacity(0.3), lineWidth: 1)
				)
			} else if showAddVolunteer && isManager {
				VStack(spacing: 8) {
					ZStack(alignment: .leading) {
						if newVolunteerName.isEmpty {
							Text("Naam vrijwilliger...")
								.foregroundColor(.gray)
								.padding(.leading, 12)
								.font(KKFont.body(16))
						}
						TextField("", text: $newVolunteerName)
							.padding(12)
							.background(Color.white)
							.cornerRadius(8)
							.overlay(
								RoundedRectangle(cornerRadius: 8)
									.stroke(Color.gray.opacity(0.3), lineWidth: 1)
							)
							.font(KKFont.body(16))
							.foregroundColor(KKTheme.textPrimary)
					}
						.onSubmit {
							addVolunteer()
						}
					
					HStack(spacing: 12) {
						Button("Annuleren") {
							showAddVolunteer = false
							newVolunteerName = ""
						}
						.buttonStyle(KKSecondaryButton())
						
						Button("Toevoegen") {
							addVolunteer()
						}
						.disabled(newVolunteerName.trimmingCharacters(in: .whitespaces).isEmpty)
						.buttonStyle(KKPrimaryButton())
					}
				}
			} else {
				if isManager {
					Button(action: { showAddVolunteer = true }) {
						HStack {
							Image(systemName: "plus.circle")
							Text("Vrijwilliger toevoegen")
						}
					}
					.buttonStyle(KKSecondaryButton())
				} else {
					// Read-only note for members
					HStack(spacing: 8) {
						Image(systemName: "lock.fill")
							.font(.caption)
							.foregroundStyle(KKTheme.textSecondary)
						Text("Alleen lezen (verenigingslid)")
							.font(KKFont.body(12))
							.foregroundStyle(KKTheme.textSecondary)
					}
				}
			}
		}
		.padding(16)
		.background(KKTheme.surfaceAlt)
		.cornerRadius(12)
		.dismissKeyboardOnTap()
		.overlay(
			// Confetti overlay
			ConfettiView(trigger: confettiTrigger)
				.allowsHitTesting(false)
		)
		.onAppear {
			loadMockVolunteers()
		}
	}
	
	private var dateText: String {
		Self.dateFormatter.string(from: dienst.start_tijd)
	}
	
	private var locationText: String {
		if let locatie = dienst.locatie_naam, !locatie.isEmpty {
			return locatie
		}
		return "Kantine"
	}
	
	private var timeRangeText: String {
		let start = Self.timeFormatter.string(from: dienst.start_tijd)
		let end = Self.timeFormatter.string(from: dienst.eind_tijd)
		let duration = Self.durationFormatter.string(from: dienst.start_tijd, to: dienst.eind_tijd) ?? ""
		return "\(start) - \(end) (\(duration))"
	}
	
	private var statusColor: Color {
		if volunteers.count == 0 {
			return Color.red
		} else if volunteers.count < dienst.minimum_bemanning {
			return Color.orange
		} else {
			return Color.green
		}
	}
	
	private var isFullyStaffed: Bool {
		volunteers.count >= dienst.minimum_bemanning
	}
	
	private func loadMockVolunteers() {
		// Load volunteers from dienst.aanmeldingen or fallback to empty
		volunteers = dienst.aanmeldingen ?? []
	}
	
	private func addVolunteer() {
		let name = newVolunteerName.trimmingCharacters(in: .whitespaces)
		guard isManager, !name.isEmpty, name.count <= 15, !volunteers.contains(name) else { return }
		guard dienst.start_tijd >= Date() else { return }
		
		let tenantId = dienst.tenant_id
		let dienstId = dienst.id
		newVolunteerName = ""
		showAddVolunteer = false
		model.backend.addVolunteer(tenantId: tenantId, dienstId: dienstId, name: name) { result in
			DispatchQueue.main.async {
				switch result {
				case .success(let updated):
					self.volunteers = updated.aanmeldingen ?? []
					if self.isFullyStaffed { self.triggerCelebration() }
					// Merge into model list
					if let idx = model.upcomingDiensten.firstIndex(where: { $0.id == updated.id }) {
						model.upcomingDiensten[idx] = updated
					}
				case .failure:
					// Optionally show error
					break
				}
			}
		}
	}
	
	private func removeVolunteer(_ name: String) {
		guard isManager else { return }
		guard dienst.start_tijd >= Date() else { return }
		let tenantId = dienst.tenant_id
		let dienstId = dienst.id
		model.backend.removeVolunteer(tenantId: tenantId, dienstId: dienstId, name: name) { result in
			DispatchQueue.main.async {
				switch result {
				case .success(let updated):
					self.volunteers = updated.aanmeldingen ?? []
					if let idx = model.upcomingDiensten.firstIndex(where: { $0.id == updated.id }) {
						model.upcomingDiensten[idx] = updated
					}
				case .failure:
					break
				}
			}
		}
	}
	
	private func triggerCelebration() {
		// Trigger the scale animation
		withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
			showCelebration = true
		}
		
		// Add confetti effect
		confettiTrigger += 1
		
		// Reset celebration state after animation
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
			withAnimation(.easeOut(duration: 0.3)) {
				showCelebration = false
			}
		}
		
		print("🎉 Celebration triggered! Dienst \(dienst.id) is now fully staffed!")
	}
	
	private static let dateFormatter: DateFormatter = {
		let df = DateFormatter()
		df.locale = Locale(identifier: "nl_NL")
		df.dateFormat = "d MMMM"
		return df
	}()
	
	private static let timeFormatter: DateFormatter = {
		let df = DateFormatter()
		df.dateStyle = .none
		df.timeStyle = .short
		return df
	}()
	
	private static let durationFormatter: DateComponentsFormatter = {
		let formatter = DateComponentsFormatter()
		formatter.allowedUnits = [.hour, .minute]
		formatter.unitsStyle = .abbreviated
		return formatter
	}()
}

// MARK: - Settings View
struct SettingsView: View {
	@EnvironmentObject var model: AppModel
	@Environment(\.dismiss) private var dismiss
	@State private var showCapAlert = false
	@State private var showResetConfirm = false
	let onClose: () -> Void
	
	// App info from Info.plist (not hardcoded)
	private var appName: String {
		if let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !displayName.isEmpty {
			return displayName
		}
		if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
			return name
		}
		return "Kantine Koning"
	}
	private var appVersion: String {
		(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
	}
	private var appBuild: String {
		(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
	}

	var body: some View {
		ScrollView {
			VStack(spacing: 24) {
				Spacer(minLength: 24)
				
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
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
					Button {
						let totalTeams = model.enrollments.reduce(0) { $0 + $1.teamIds.count }
						guard totalTeams < 5 else { showCapAlert = true; return }
						onClose()
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
							model.startNewEnrollment()
						}
					} label: {
						Label("Vereniging toevoegen", systemImage: "plus.circle.fill")
					}
					.buttonStyle(KKSecondaryButton())
					
					Button {
						let totalTeams = model.enrollments.reduce(0) { $0 + $1.teamIds.count }
						guard totalTeams < 5 else { showCapAlert = true; return }
						onClose()
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
							model.startNewEnrollment()
						}
					} label: {
						Label("Team toevoegen", systemImage: "person.2.fill")
					}
					.buttonStyle(KKSecondaryButton())
				}
				.kkCard()
				.padding(.horizontal, 24)
				
				// Destructive reset card
				VStack(alignment: .leading, spacing: 12) {
					Text("Geavanceerd")
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
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
				Text("\(appName) – versie \(appVersion) (\(appBuild))")
					.font(KKFont.body(12))
					.foregroundStyle(KKTheme.textSecondary)
					.multilineTextAlignment(.center)
					.padding(.horizontal, 24)
				
				Spacer(minLength: 24)
			}
		}
		.background(KKTheme.surface.ignoresSafeArea())
		.alert("Limiet bereikt", isPresented: $showCapAlert) {
			Button("OK", role: .cancel) { }
		} message: {
			Text("Je kunt maximaal 5 teams volgen. Verwijder eerst een team om verder te gaan.")
		}
		.alert("Weet je het zeker?", isPresented: $showResetConfirm) {
			Button("Annuleren", role: .cancel) { }
			Button("Reset", role: .destructive) {
				model.resetAll()
				onClose()
			}
		} message: {
			Text("Dit verwijdert alle lokale enrollments en gegevens van dit apparaat.")
		}
	}
}

// MARK: - Volunteer Submission View
struct VolunteerSubmissionView: View {
	@EnvironmentObject var model: AppModel
	let action: String
	@Environment(\.dismiss) private var dismiss
	@State private var names: [String] = [""]
	@State private var submitting = false
	@State private var errorMessage: String?

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 24) {
					Spacer(minLength: 24)
					
					BrandAssets.logoImage()
						.resizable()
						.scaledToFit()
						.frame(width: 72, height: 72)
					
					VStack(spacing: 8) {
						Text("VRIJWILLIGERS")
							.font(KKFont.heading(24))
							.fontWeight(.regular)
							.kerning(-1.0)
							.foregroundStyle(KKTheme.textPrimary)
						
						Text("Voeg de namen van beschikbare vrijwilligers toe")
							.font(KKFont.title(16))
							.foregroundStyle(KKTheme.textSecondary)
					}
					.multilineTextAlignment(.center)
					
					VStack(spacing: 12) {
						ForEach(names.indices, id: \.self) { index in
							ZStack(alignment: .leading) {
								if names[index].isEmpty {
									Text("Naam vrijwilliger...")
										.foregroundColor(.gray)
										.padding(.leading, 12)
										.font(KKFont.body(16))
								}
								TextField("", text: Binding(
									get: { names[index] },
									set: { names[index] = $0 }
								))
									.padding(12)
									.background(Color.white)
									.cornerRadius(8)
									.overlay(
										RoundedRectangle(cornerRadius: 8)
											.stroke(Color.gray.opacity(0.3), lineWidth: 1)
									)
									.font(KKFont.body(16))
									.foregroundColor(KKTheme.textPrimary)
							}
						}
						
						Button(action: { names.append("") }) {
							HStack {
								Image(systemName: "plus.circle")
								Text("Naam toevoegen")
							}
						}
						.buttonStyle(KKSecondaryButton())
					}
					.padding(.horizontal, 24)
					
					if let errorMessage = errorMessage {
						Text(errorMessage)
							.font(KKFont.body(14))
							.foregroundStyle(.red)
							.padding(.horizontal, 24)
					}
					
					HStack(spacing: 16) {
						Button("Annuleren") {
							dismiss()
							model.pendingAction = nil
						}
						.buttonStyle(KKSecondaryButton())
						
						Button {
							submitting = true
							let clean = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
							model.backend.submitVolunteers(actionToken: action, names: clean) { result in
								DispatchQueue.main.async {
									submitting = false
									switch result {
									case .success:
										dismiss()
										model.pendingAction = nil
									case .failure(let error):
										errorMessage = error.localizedDescription
									}
								}
							}
						} label: {
							if submitting {
								HStack {
									ProgressView()
										.tint(.white)
									Text("Bezig...")
								}
							} else {
								Text("Verstuur")
							}
						}
						.disabled(submitting)
						.buttonStyle(KKPrimaryButton())
					}
					.padding(.horizontal, 24)
					
					Spacer(minLength: 24)
				}
			}
			.background(KKTheme.surface.ignoresSafeArea())
			.navigationTitle("")
			.navigationBarHidden(true)
			.dismissKeyboardOnTap()
		}
	}
}

// MARK: - Swipeable Row Component
struct SwipeableRow<Content: View>: View {
	let onTap: () -> Void
	let onDelete: () -> Void
	let content: () -> Content
	
	@State private var offset: CGFloat = 0
	@State private var showingDeleteConfirmation = false
	
	private let deleteButtonWidth: CGFloat = 80
	
	var body: some View {
		ZStack {
			// Main content
			content()
				.frame(maxWidth: .infinity)
				.offset(x: offset)
				.onTapGesture {
					if offset == 0 {
						onTap()
					} else {
						// Reset if swiped
						withAnimation(.spring()) {
							offset = 0
						}
					}
				}
				.gesture(
					DragGesture()
						.onChanged { value in
							let translation = value.translation.width
							if translation < 0 {
								offset = max(translation, -deleteButtonWidth)
							} else if offset < 0 {
								offset = min(0, offset + translation)
							}
						}
						.onEnded { value in
							let translation = value.translation.width
							let velocity = value.velocity.width
							
							withAnimation(.spring()) {
								if translation < -deleteButtonWidth/2 || velocity < -500 {
									offset = -deleteButtonWidth
								} else {
									offset = 0
								}
							}
						}
				)
			
			// Delete button overlay (positioned to the right)
			HStack {
				Spacer()
				Button(action: {
					showingDeleteConfirmation = true
				}) {
					VStack {
						Image(systemName: "trash")
							.font(.title2)
						Text("Verwijder")
							.font(.caption)
					}
					.foregroundColor(.white)
					.frame(width: deleteButtonWidth)
					.frame(maxHeight: .infinity)
					.background(Color.red)
				}
				.offset(x: offset + deleteButtonWidth)
				.opacity(offset < 0 ? 1 : 0)
			}
		}
		.clipped()
		.alert("Bevestig verwijdering", isPresented: $showingDeleteConfirmation) {
			Button("Annuleren", role: .cancel) { }
			Button("Verwijderen", role: .destructive) {
				withAnimation(.spring()) {
					offset = 0
					onDelete()
				}
			}
		} message: {
			Text("Weet je zeker dat je deze enrollment wilt verwijderen?")
		}
	}
}

// MARK: - Confetti Effect
struct ConfettiView: View {
	let trigger: Int
	@State private var animate = false
	@State private var showConfetti = false
	
	var body: some View {
		ZStack {
			if showConfetti {
				ForEach(0..<15, id: \.self) { _ in
					ConfettiPiece()
						.opacity(animate ? 0 : 1)
						.scaleEffect(animate ? 0.5 : 1)
						.offset(
							x: animate ? Double.random(in: -100...100) : 0,
							y: animate ? Double.random(in: -50...150) : 0
						)
						.rotationEffect(.degrees(animate ? Double.random(in: 0...360) : 0))
				}
			}
		}
		.onChange(of: trigger) { _, _ in
			guard trigger > 0 else { return }
			
			// Show confetti and start animation
			showConfetti = true
			animate = false
			
			withAnimation(.easeOut(duration: 1.5)) {
				animate = true
			}
			
			// Hide confetti completely after animation
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
				animate = false
				showConfetti = false
			}
		}
	}
}

struct ConfettiPiece: View {
	let colors: [Color] = [.yellow, .orange, .red, .pink, .purple, .blue, .green]
	let shapes = ["circle.fill", "diamond.fill", "triangle.fill", "square.fill"]
	
	var body: some View {
		Image(systemName: shapes.randomElement() ?? "circle.fill")
			.foregroundColor(colors.randomElement() ?? .orange)
			.font(.system(size: 8))
	}
}
