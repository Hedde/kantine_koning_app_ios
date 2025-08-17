//
//  OnboardingFlowView.swift
//  Kantine Koning
//
//  Created by AI Assistant on 16/08/2025.
//

import SwiftUI



struct OnboardingFlowView: View {
	@EnvironmentObject var model: AppModel
	@State private var scanning = false
	@State private var navigateTeam = false
	@State private var navigateEmail = false
	@State private var scannedOnce = false
	@State private var navigateManager = false
	@State private var navigateMember = false
	@State private var keyboardHeight: CGFloat = 0
	private var safeAreaBottom: CGFloat {
		(UIApplication.shared.connectedScenes.first as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom ?? 0
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 24) {
					Spacer(minLength: 24)
					BrandAssets.logoImage()
						.resizable()
						.scaledToFit()
						.frame(width: 72, height: 72)

					// Headline with website SVG zig-zag underlay for "EENVOUDIG"
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

					// Scanner or results display
					if let invite = model.invite {
						// Unified container: only the inner form section changes
						ClubEnrollContainerView(invite: invite) {
							navigateTeam = true
						} onRescan: {
							model.invite = nil
							scanning = true
						}
					} else {
						// Show scanner interface
						VStack(spacing: 16) {
							ZStack {
								RoundedRectangle(cornerRadius: 16, style: .continuous)
									.fill(Color.clear)
									.aspectRatio(1.0, contentMode: .fit) // Square aspect ratio for QR codes
									.overlay(
										Group {
											if scanning {
												ZStack {
													QRScannerView(isActive: true) { code in
														scannedOnce = true
														scanning = false
														parseInvite(from: code)
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

							Button(action: { 
								if scannedOnce {
									model.invite = nil // Reset invite to show scanner again
								}
								scanning = true 
							}) {
								Label(scannedOnce ? "Opnieuw scannen" : "Scan QR-code", systemImage: "qrcode.viewfinder")
							}
							.buttonStyle(KKPrimaryButton())
							.padding(.horizontal, 24)

#if DEBUG
							Button(action: {
								if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
									scannedOnce = true
									scanning = false
									parseInvite(from: pasted)
								}
							}) {
								Label("Plak invite link", systemImage: "doc.on.clipboard")
							}
							.buttonStyle(.bordered)
							.tint(.gray)
							.padding(.horizontal, 24)
#endif

							// Show cancel only if there are existing enrollments
							if !model.enrollments.isEmpty {
								Button {
									// Exit onboarding back to home
									model.appPhase = .registered
								} label: {
									HStack(spacing: 6) {
										Image(systemName: "xmark.circle.fill")
										Text("Annuleren")
									}
								}
								.buttonStyle(.plain)
								.foregroundStyle(KKTheme.textSecondary)
							}
						}
					}

					Spacer(minLength: 24)
				}
			}
			.navigationTitle("")
			.navigationBarHidden(true)
			.background(KKTheme.surface.ignoresSafeArea())
			// Push content above the keyboard without stretching cards
			.safeAreaInset(edge: .bottom) {
				Color.clear.frame(height: keyboardHeight)
			}
			.dismissKeyboardOnTap()
			// New iOS 16+ navigation destinations
			.navigationDestination(isPresented: $navigateTeam) {
				if let invite = model.invite {
					TeamMultiPickerView(invite: invite) { teams in
						model.setSelectedTeams(teams)
						navigateEmail = true
					}
				}
			}
			.navigationDestination(isPresented: $navigateEmail) {
				EmailEntryView()
			}
			.navigationDestination(isPresented: $navigateManager) {
				if let invite = model.invite {
					ManagerVerifyView(invite: invite) {
						navigateTeam = true
					}
				}
			}
			.navigationDestination(isPresented: $navigateMember) {
				if let invite = model.invite {
					MemberEnrollView(invite: invite)
				}
			}
		}
		// Keyboard listeners
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

	private func parseInvite(from code: String) {
		print("🔍 Raw QR code: \(code)")
		
		// Handle both direct URLs and nested encoded URLs from QR server
		var urlString = code
		if let url = URL(string: code), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
			print("🌐 Parsed URL host: \(url.host ?? "no host")")
			print("🔗 Query items: \(comps.queryItems?.map { "\($0.name)=\($0.value ?? "nil")" } ?? ["none"])")
			
			// Check if 'data' parameter contains the actual invite URL
			if let dataParam = comps.queryItems?.first(where: { $0.name == "data" })?.value {
				urlString = dataParam.removingPercentEncoding ?? dataParam
				print("📦 Extracted data param: \(urlString)")
			}
		}
		
		// Now parse the actual invite URL - only need tenant info, teams come from API
		if let inviteURL = URL(string: urlString) {
			print("🎯 Final URL to parse: \(inviteURL.absoluteString)")
			print("🏠 Host: \(inviteURL.host ?? "no host")")
			
			if let inviteComps = URLComponents(url: inviteURL, resolvingAgainstBaseURL: false) {
				print("📋 All query items:")
				inviteComps.queryItems?.forEach { item in
					print("   \(item.name) = \(item.value ?? "nil")")
				}
				
				let tenantId = inviteComps.queryItems?.first(where: { $0.name == "tenant" })?.value
				var tenantName = inviteComps.queryItems?.first(where: { $0.name == "tenant_name" })?.value
				// Convert '+' (form encoding for space) to real spaces, then apply percent-decoding
				if let tn = tenantName {
					let withSpaces = tn.replacingOccurrences(of: "+", with: " ")
					tenantName = withSpaces.removingPercentEncoding ?? withSpaces
				}
				
				print("🏢 Extracted - Tenant ID: '\(tenantId ?? "nil")'")
				print("🏢 Extracted - Tenant Name: '\(tenantName ?? "nil")'")
				
				// Only need tenant info now - teams will be fetched via email API
				if let tenantId = tenantId, !tenantId.isEmpty,
				   let tenantName = tenantName, !tenantName.isEmpty {
					
					print("✅ Successfully parsed tenant:")
					print("   Tenant: \(tenantId) - \(tenantName)")
					
					// Create invite with empty teams - will be populated after email verification
					let invite = AppModel.TenantInvite(tenantId: tenantId, tenantName: tenantName, allowedTeams: [])
					model.handleScannedInvite(invite)
					return
				}
			}
		}
		
		print("❌ QR code parsing failed - incomplete or invalid tenant data")
		print("❌ Expected format: https://kantinekoning.com/invite?tenant=X&tenant_name=Y")
		
		// Don't use any fallback - let it fail visibly
		model.handleScannedInvite(.init(
			tenantId: "PARSE_ERROR", 
			tenantName: "❌ QR Code Parse Error", 
			allowedTeams: [
				AppModel.Team(id: UUID().uuidString, code: "ERROR", naam: "QR code kon niet worden gelezen")
			]
		))
	}
}

struct ClubEnrollContainerView: View {
	let invite: AppModel.TenantInvite
	let onManagerVerified: () -> Void
	let onRescan: () -> Void
	
	@State private var step: Step = .chooseRole
	@State private var selectedRole: AppModel.EnrollmentRole? = nil
	
	enum Step {
		case chooseRole
		case managerVerify
		case memberEnroll
	}
	
	var body: some View {
		VStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 12) {
				Text("Gevonden club")
					.font(KKFont.body(12))
					.foregroundStyle(KKTheme.textSecondary)
				Text(invite.tenantName)
					.font(KKFont.title(20))
					.foregroundStyle(KKTheme.textPrimary)
				
				// Swappable inner content
				Group {
					switch step {
					case .chooseRole:
						VStack(spacing: 12) {
							// Selection rows (consistent with team selection)
							Button(action: { selectedRole = .manager }) {
								HStack {
									VStack(alignment: .leading, spacing: 2) {
										Text("Teammanager")
											.font(KKFont.title(16))
											.foregroundStyle(KKTheme.textPrimary)
										Text("E‑mail vereist, beheer vrijwilligers")
											.font(KKFont.body(12))
											.foregroundStyle(KKTheme.textSecondary)
									}
									Spacer()
									Image(systemName: selectedRole == .manager ? "checkmark.circle.fill" : "circle")
										.foregroundStyle(selectedRole == .manager ? KKTheme.accent : KKTheme.textSecondary)
								}
							}
							.padding(12)
							.background((selectedRole == .manager) ? KKTheme.accent.opacity(0.1) : KKTheme.surfaceAlt)
							.cornerRadius(8)
							Button(action: { selectedRole = .member }) {
								HStack {
									VStack(alignment: .leading, spacing: 2) {
										Text("Verenigingslid")
											.font(KKFont.title(16))
											.foregroundStyle(KKTheme.textPrimary)
										Text("Alleen lezen, meldingen ontvangen")
											.font(KKFont.body(12))
											.foregroundStyle(KKTheme.textSecondary)
									}
									Spacer()
									Image(systemName: selectedRole == .member ? "checkmark.circle.fill" : "circle")
										.foregroundStyle(selectedRole == .member ? KKTheme.accent : KKTheme.textSecondary)
								}
							}
							.padding(12)
							.background((selectedRole == .member) ? KKTheme.accent.opacity(0.1) : KKTheme.surfaceAlt)
							.cornerRadius(8)
							// Primary confirm
							Button(action: {
								if selectedRole == .manager { step = .managerVerify }
								else if selectedRole == .member { step = .memberEnroll }
							}) {
								Text("Verder")
							}
							.disabled(selectedRole == nil)
							.buttonStyle(KKPrimaryButton())
						}
					case .managerVerify:
						ManagerVerifySection(invite: invite, onVerified: onManagerVerified, onBack: { step = .chooseRole })
					case .memberEnroll:
						MemberEnrollSection(invite: invite, onBack: { step = .chooseRole })
					}
				}
			}
			.kkCard()
			.padding(.horizontal, 24)
			
			// Subtle rescan below
			Button(action: onRescan) {
				HStack(spacing: 6) {
					Image(systemName: "qrcode.viewfinder")
					Text("Opnieuw scannen")
				}
			}
			.buttonStyle(.plain)
			.foregroundStyle(KKTheme.textSecondary)
			.padding(.horizontal, 24)
		}
	}
}

// Compact sections for reuse inside the container, consistent styling with outer card
private struct ManagerVerifySection: View {
	let invite: AppModel.TenantInvite
	let onVerified: () -> Void
	let onBack: () -> Void
	@EnvironmentObject var model: AppModel
	@State private var email: String = ""
	@State private var verifying = false
	@State private var errorMessage: String?
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Button(action: onBack) {
				HStack(spacing: 6) {
					Image(systemName: "chevron.left")
						.font(.body)
					Text("Terug")
						.font(KKFont.body(12))
				}
			}
			.buttonStyle(.plain)
			.foregroundStyle(KKTheme.textSecondary)

			Text("E-mailadres")
				.font(KKFont.body(12))
				.foregroundStyle(KKTheme.textSecondary)
			Text("We gebruiken je e-mailadres om te bevestigen dat jij de teammanager bent en om de juiste teams op te halen.")
				.font(KKFont.body(12))
				.foregroundStyle(KKTheme.textSecondary)
				.italic()
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
					.autocapitalization(.none)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled(true)
					.submitLabel(.done)
					.font(KKFont.body(16))
					.foregroundColor(KKTheme.textPrimary)
			}
			if let errorMessage = errorMessage {
				Text(errorMessage)
					.font(KKFont.body(12))
					.foregroundStyle(.red)
			}
			Button(action: verifyTeams) {
				if verifying { HStack { ProgressView().tint(.white); Text("Controleren...") } }
				else { Text("Teams ophalen") }
			}
			.disabled(verifying)
			.buttonStyle(KKPrimaryButton())
		}
		.dismissKeyboardOnTap()
	}
	
	private func verifyTeams() {
		guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
			errorMessage = "Voer je e-mailadres in om teams op te halen"
			return
		}
		verifying = true
		errorMessage = nil
		model.backend.enrollDevice(email: email.trimmingCharacters(in: .whitespaces), tenantSlug: invite.tenantId, teamCodes: []) { result in
			DispatchQueue.main.async {
				verifying = false
				switch result {
				case .success(let teams):
					// Update invite with teams from backend so user can pick directly
					let updatedInvite = AppModel.TenantInvite(tenantId: invite.tenantId, tenantName: invite.tenantName, allowedTeams: teams)
					model.handleScannedInvite(updatedInvite)
					model.verifiedEmail = email
					onVerified()
				case .failure(let error):
					let msg = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String
					errorMessage = msg ?? "Dit e-mailadres is niet bekend als teammanager bij \(invite.tenantName)"
				}
			}
		}
	}
}

private struct MemberEnrollSection: View {
	let invite: AppModel.TenantInvite
	let onBack: () -> Void
	@EnvironmentObject var model: AppModel
	@State private var searchQuery: String = ""
	@State private var searchResults: [AppModel.Team] = []
	@State private var selectedMemberTeamIds: Set<String> = []
	@State private var searchWorkItem: DispatchWorkItem?
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Button(action: onBack) {
				HStack(spacing: 6) {
					Image(systemName: "chevron.left")
						.font(.body)
					Text("Terug")
						.font(KKFont.body(12))
				}
			}
			.buttonStyle(.plain)
			.foregroundStyle(KKTheme.textSecondary)
			Text("Zoek je team(s)")
				.font(KKFont.body(12))
				.foregroundStyle(KKTheme.textSecondary)
			ZStack(alignment: .leading) {
				if searchQuery.isEmpty {
					Text("Bijv. JO11-3")
						.foregroundColor(.secondary)
						.padding(.leading, 12)
						.font(KKFont.body(16))
				}
				TextField("", text: $searchQuery)
					.padding(12)
					.background(KKTheme.surfaceAlt)
					.cornerRadius(8)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled(true)
					.submitLabel(.search)
					.font(KKFont.body(16))
					.foregroundColor(KKTheme.textPrimary)
			}
			.onChange(of: searchQuery) { _, _ in debounceSearch() }
			VStack(spacing: 8) {
				ForEach(searchResults, id: \.id) { team in
					Button(action: { toggleMemberSelection(team.id) }) {
						HStack {
							VStack(alignment: .leading, spacing: 2) {
								Text(team.naam)
									.font(KKFont.title(16))
									.foregroundStyle(KKTheme.textPrimary)
								if let code = team.code {
									Text(code)
										.font(KKFont.body(12))
										.foregroundStyle(KKTheme.textSecondary)
								}
							}
							Spacer()
							Image(systemName: selectedMemberTeamIds.contains(team.id) ? "checkmark.circle.fill" : "circle")
								.foregroundStyle(selectedMemberTeamIds.contains(team.id) ? KKTheme.accent : KKTheme.textSecondary)
						}
					}
					.padding(12)
					.background(KKTheme.surfaceAlt)
					.cornerRadius(8)
				}
			}
			Button(action: registerMember) { Text("Aanmelden") }
				.disabled(selectedMemberTeamIds.isEmpty)
				.buttonStyle(KKPrimaryButton())
		}
	}
	
	private func debounceSearch() {
		searchWorkItem?.cancel()
		let work = DispatchWorkItem { performSearch() }
		searchWorkItem = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
	}
	private func performSearch() {
		let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { searchResults = []; return }
		model.backend.searchTeams(tenantId: invite.tenantId, query: q) { result in
			DispatchQueue.main.async {
				switch result {
				case .success(let teams): searchResults = teams
				case .failure: searchResults = []
				}
			}
		}
	}
	private func toggleMemberSelection(_ teamId: String) {
		if selectedMemberTeamIds.contains(teamId) { selectedMemberTeamIds.remove(teamId) } else { selectedMemberTeamIds.insert(teamId) }
	}
	private func registerMember() {
		let teamIds = Array(selectedMemberTeamIds)
		model.registerMember(tenantId: invite.tenantId, tenantName: invite.tenantName, teamIds: teamIds) { _ in }
	}
}

struct ClubFoundView: View {
	let invite: AppModel.TenantInvite
	let onTeamsVerified: () -> Void
	let onRescan: () -> Void
	
	@EnvironmentObject var model: AppModel
	@State private var email: String = ""
	@State private var verifying = false
	@State private var errorMessage: String?
	@State private var teamsVerified = false
	@State private var roleSelection: AppModel.EnrollmentRole = .manager
	// Member search states
	@State private var searchQuery: String = ""
	@State private var searchResults: [AppModel.Team] = []
	@State private var selectedMemberTeamIds: Set<String> = []
	@State private var searchWorkItem: DispatchWorkItem?
	
	var body: some View {
		VStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 12) {
				Text("Gevonden club")
					.font(KKFont.body(12))
					.foregroundStyle(KKTheme.textSecondary)
				Text(invite.tenantName)
					.font(KKFont.title(20))
					.foregroundStyle(KKTheme.textPrimary)

				// Role selection
				VStack(alignment: .leading, spacing: 8) {
					Text("Mijn rol")
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
					HStack(spacing: 12) {
						roleButton(title: "Teammanager", isSelected: roleSelection == .manager) {
							roleSelection = .manager
						}
						roleButton(title: "Verenigingslid", isSelected: roleSelection == .member) {
							roleSelection = .member
						}
					}
					Text(roleSelection == .manager
						 ? "Verifieer e‑mail, kies teams en beheer vrijwilligers."
						 : "Zoek team(s) en ontvang meldingen (alleen lezen).")
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
					Text("Meerdere teams/verenigingen mogelijk (max. 5).")
						.font(KKFont.body(11))
						.foregroundStyle(KKTheme.textSecondary)
						.italic()
				}
				.padding(.top, 4)
				
				if roleSelection == .manager {
					if !teamsVerified {
						VStack(alignment: .leading, spacing: 8) {
							Text("E-mailadres teammanager")
								.font(KKFont.body(12))
								.foregroundStyle(KKTheme.textSecondary)
							Text("Voer het e-mailadres in waarmee je als teammanager bekend bent bij deze club.")
								.font(KKFont.body(11))
								.foregroundStyle(KKTheme.textSecondary)
								.italic()
							
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
									.autocapitalization(.none)
									.font(KKFont.body(16))
									.foregroundColor(KKTheme.textPrimary)
							}
						}
						
						if let errorMessage = errorMessage {
							Text(errorMessage)
								.font(KKFont.body(12))
								.foregroundStyle(.red)
						}
						
						Button {
							verifyTeams()
						} label: {
							if verifying {
								HStack {
									ProgressView()
										.tint(.white)
									Text("Controleren...")
								}
							} else {
								Text("E-mailadres verifiëren")
							}
						}
						.disabled(verifying)
						.buttonStyle(KKSecondaryButton())
					} else {
						Button("Kies teams") { onTeamsVerified() }
							.buttonStyle(KKSecondaryButton())
					}
				} else {
					// Member flow: search teams with debounce, allow multi-select, then register
					VStack(alignment: .leading, spacing: 8) {
						Text("Zoek je team(s)")
							.font(KKFont.body(12))
							.foregroundStyle(KKTheme.textSecondary)
						ZStack(alignment: .leading) {
							if searchQuery.isEmpty {
								Text("Bijv. JO11-3")
									.foregroundColor(.secondary)
									.padding(.leading, 12)
									.font(KKFont.body(16))
							}
							TextField("", text: $searchQuery)
								.padding(12)
								.background(KKTheme.surfaceAlt)
								.cornerRadius(8)
								.textInputAutocapitalization(.never)
								.autocorrectionDisabled(true)
								.submitLabel(.search)
								.font(KKFont.body(16))
								.foregroundColor(KKTheme.textPrimary)
						}
						.onChange(of: searchQuery) { _, _ in debounceSearch() }
						
						VStack(spacing: 8) {
							ForEach(searchResults, id: \.id) { team in
								Button(action: { toggleMemberSelection(team.id) }) {
									HStack {
										VStack(alignment: .leading, spacing: 2) {
											Text(team.naam)
												.font(KKFont.title(16))
												.foregroundStyle(KKTheme.textPrimary)
											if let code = team.code {
												Text(code)
													.font(KKFont.body(12))
													.foregroundStyle(KKTheme.textSecondary)
											}
										}
										Spacer()
										Image(systemName: selectedMemberTeamIds.contains(team.id) ? "checkmark.circle.fill" : "circle")
											.foregroundStyle(selectedMemberTeamIds.contains(team.id) ? KKTheme.accent : KKTheme.textSecondary)
									}
								}
								.padding(12)
								.background(KKTheme.surfaceAlt)
								.cornerRadius(8)
							}
						}
					}

					Button {
						registerMember()
					} label: {
						Text("Aanmelden")
					}
					.disabled(selectedMemberTeamIds.isEmpty)
					.buttonStyle(KKSecondaryButton())
				}
			}
			.kkCard()
			.padding(.horizontal, 24)
			
			Button(action: onRescan) {
				Label("Opnieuw scannen", systemImage: "qrcode.viewfinder")
			}
			.buttonStyle(KKPrimaryButton())
			.padding(.horizontal, 24)
		}
		.dismissKeyboardOnTap()
	}
	
	private func verifyTeams() {
		// Validate email input first
		let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			errorMessage = "Voer je e-mailadres in om te verifiëren"
			return
		}
		
		verifying = true
		errorMessage = nil
		
		// Trigger backend email check (and magic link) with empty teamCodes; we select teams in volgende stap
		model.backend.enrollDevice(email: trimmed, tenantSlug: invite.tenantId, teamCodes: []) { result in
			DispatchQueue.main.async {
				verifying = false
				switch result {
				case .success(let teams):
					// Update invite with teams from backend so user can pick directly
					let updatedInvite = AppModel.TenantInvite(tenantId: invite.tenantId, tenantName: invite.tenantName, allowedTeams: teams)
					model.handleScannedInvite(updatedInvite)
					model.verifiedEmail = trimmed
					teamsVerified = true
					onTeamsVerified()
				case .failure(let err):
					errorMessage = (err as NSError).localizedDescription
				}
			}
		}
	}

	// MARK: - Member helpers
	private func debounceSearch() {
		searchWorkItem?.cancel()
		let work = DispatchWorkItem { performSearch() }
		searchWorkItem = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
	}

	private func performSearch() {
		let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { searchResults = []; return }
		model.backend.searchTeams(tenantId: invite.tenantId, query: q) { result in
			DispatchQueue.main.async {
				switch result {
				case .success(let teams):
					self.searchResults = teams
				case .failure:
					self.searchResults = []
				}
			}
		}
	}

	private func toggleMemberSelection(_ teamId: String) {
		if selectedMemberTeamIds.contains(teamId) {
			selectedMemberTeamIds.remove(teamId)
		} else {
			selectedMemberTeamIds.insert(teamId)
		}
	}

	private func registerMember() {
		let teamIds = Array(selectedMemberTeamIds)
		model.registerMember(tenantId: invite.tenantId, tenantName: invite.tenantName, teamIds: teamIds) { result in
			// No-op; App phase will switch to registered
		}
	}

	@ViewBuilder
	private func roleButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title)
				.font(KKFont.title(16))
				.frame(maxWidth: .infinity)
				.padding(.vertical, 14)
		}
		.background(isSelected ? KKTheme.accent.opacity(0.18) : KKTheme.surfaceAlt)
		.foregroundStyle(isSelected ? KKTheme.accent : KKTheme.textPrimary)
		.cornerRadius(12)
		.overlay(
			RoundedRectangle(cornerRadius: 12)
				.stroke(isSelected ? KKTheme.accent.opacity(0.6) : Color.clear, lineWidth: 1)
		)
	}
}

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
					// ZigZag PNG positioned under the text
					GeometryReader { geo in
						let textWidth = geo.size.width
						let textHeight: CGFloat = 30
						
						// Website positioning: top-2/3 and h-[0.58em] 
						let zigzagHeight = textHeight * 0.58
						let topOffset = textHeight * (2.0/3.0)
						
						Image("ZigZag")
							.resizable()
							.renderingMode(.template) // Allows us to tint the image
							.foregroundColor(KKTheme.accent.opacity(0.7))
							.frame(width: textWidth, height: zigzagHeight)
							.offset(x: 0, y: topOffset)
					}
				)
		}
		.frame(height: 36)
	}
}

private struct CrosshairOverlay: View {
    var body: some View {
        GeometryReader { geo in
            // Square layout with better proportioned insets and corners
            let minDim = min(geo.size.width, geo.size.height)
            let inset: CGFloat = minDim * 0.15  // 15% inset for better square proportion
            let rect = CGRect(
                x: (geo.size.width - minDim) / 2 + inset,
                y: (geo.size.height - minDim) / 2 + inset,
                width: minDim - 2 * inset,
                height: minDim - 2 * inset
            )

            // Smaller, more elegant corner proportions
            let lineW: CGFloat = 2.0
            let radius: CGFloat = 16         // smaller radius
            let seg: CGFloat = 32            // shorter corner arms
            let plus: CGFloat = 16           // smaller plus

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

struct TeamMultiPickerView: View {
	let invite: AppModel.TenantInvite
	let onDone: ([AppModel.Team]) -> Void
	@State private var selectedIds: Set<String> = []

	var body: some View {
		ScrollView {
			VStack(spacing: 24) {
				Spacer(minLength: 24)
				
				BrandAssets.logoImage()
					.resizable()
					.scaledToFit()
					.frame(width: 72, height: 72)

				VStack(spacing: 8) {
					Text("KIES JE TEAMS")
						.font(KKFont.heading(24))
						.fontWeight(.regular)
						.kerning(-1.0)
						.foregroundStyle(KKTheme.textPrimary)
					
					Text("Bij \(invite.tenantName)")
						.font(KKFont.title(18))
						.foregroundStyle(KKTheme.textSecondary)
				}
				.multilineTextAlignment(.center)

				VStack(spacing: 12) {
					ForEach(invite.allowedTeams, id: \.id) { team in
						Button(action: {
							if selectedIds.contains(team.id) {
								selectedIds.remove(team.id)
							} else {
								selectedIds.insert(team.id)
							}
						}) {
							HStack {
								VStack(alignment: .leading, spacing: 4) {
									Text(team.naam)
										.font(KKFont.title(16))
										.foregroundStyle(KKTheme.textPrimary)
									if let code = team.code {
										Text(code)
											.font(KKFont.body(14))
											.foregroundStyle(KKTheme.textSecondary)
									}
								}
								Spacer()
								if selectedIds.contains(team.id) {
									Image(systemName: "checkmark.circle.fill")
										.foregroundStyle(KKTheme.accent)
										.font(.title2)
								} else {
									Image(systemName: "circle")
										.foregroundStyle(KKTheme.textSecondary)
										.font(.title2)
								}
							}
							.padding(16)
							.background(selectedIds.contains(team.id) ? KKTheme.accent.opacity(0.1) : KKTheme.surfaceAlt)
							.overlay(
								RoundedRectangle(cornerRadius: 12)
									.stroke(selectedIds.contains(team.id) ? KKTheme.accent : KKTheme.surfaceAlt, lineWidth: 2)
							)
							.cornerRadius(12)
						}
						.buttonStyle(PlainButtonStyle())
					}
				}
				.padding(.horizontal, 24)

				Button("Doorgaan met \(selectedIds.count) team\(selectedIds.count == 1 ? "" : "s")") {
					let selected = invite.allowedTeams.filter { selectedIds.contains($0.id) }
					onDone(selected)
				}
				.disabled(selectedIds.isEmpty)
				.buttonStyle(KKPrimaryButton())
				.padding(.horizontal, 24)
				.padding(.top, 16)

				Spacer(minLength: 24)
			}
		}
		.navigationTitle("")
		.navigationBarHidden(true)
		.background(KKTheme.surface.ignoresSafeArea())
	}
}

struct EmailEntryView: View {
	@EnvironmentObject var model: AppModel
	@State private var sending = false
	@State private var errorMessage: String?
	
	var body: some View {
		ScrollView {
			VStack(spacing: 24) {
				Spacer(minLength: 24)
				
				BrandAssets.logoImage()
					.resizable()
					.scaledToFit()
					.frame(width: 72, height: 72)

				VStack(spacing: 8) {
					Text("EMAIL VALIDATIE")
						.font(KKFont.heading(24))
						.fontWeight(.regular)
						.kerning(-1.0)
						.foregroundStyle(KKTheme.textPrimary)
					
					if let ctx = model.tenantContext {
						Text("Voor \(ctx.tenantName)")
							.font(KKFont.title(18))
							.foregroundStyle(KKTheme.textSecondary)
					}
				}
				.multilineTextAlignment(.center)
				
				VStack(alignment: .leading, spacing: 12) {
					Text("Bevestiging")
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
					Text("We gaan nu je e-mailadres valideren zodat we zeker weten dat jij echt de eigenaar bent van het e-mailadres en de manager van de geselecteerde teams.")
						.font(KKFont.body(14))
						.foregroundStyle(KKTheme.textSecondary)
				}
				.kkCard()
				.padding(.horizontal, 24)

				if let ctx = model.tenantContext {
					VStack(spacing: 12) {
						ForEach(ctx.selectedTeams, id: \.id) { team in
							HStack {
								VStack(alignment: .leading, spacing: 4) {
									Text(team.naam)
										.font(KKFont.title(16))
										.foregroundStyle(KKTheme.textPrimary)
									if let code = team.code {
										Text(code)
											.font(KKFont.body(14))
											.foregroundStyle(KKTheme.textSecondary)
									}
								}
								Spacer()
								Image(systemName: "checkmark.circle.fill")
									.foregroundStyle(KKTheme.accent)
									.font(.title2)
							}
							.padding(16)
							.background(KKTheme.accent.opacity(0.1))
							.overlay(
								RoundedRectangle(cornerRadius: 12)
									.stroke(KKTheme.accent, lineWidth: 2)
							)
							.cornerRadius(12)
						}
					}
					.padding(.horizontal, 24)
				}

				if let verifiedEmail = model.verifiedEmail {
					VStack(spacing: 12) {
						HStack {
							VStack(alignment: .leading, spacing: 4) {
								Text("E-mailadres voor validatie")
									.font(KKFont.body(12))
									.foregroundStyle(KKTheme.textSecondary)
								Text(verifiedEmail)
									.font(KKFont.title(16))
									.foregroundStyle(KKTheme.textPrimary)
							}
							Spacer()
							Image(systemName: "envelope.circle.fill")
								.foregroundStyle(KKTheme.accent)
								.font(.title2)
						}
						.padding(16)
						.background(KKTheme.surfaceAlt)
						.overlay(
							RoundedRectangle(cornerRadius: 12)
								.stroke(KKTheme.surfaceAlt, lineWidth: 1)
						)
						.cornerRadius(12)
					}
					.padding(.horizontal, 24)
				}

				if let errorMessage = errorMessage {
					Text(errorMessage)
						.font(KKFont.body(14))
						.foregroundStyle(.red)
						.padding(.horizontal, 24)
				}

				Button {
					sendMagicLink()
				} label: {
					if sending {
						HStack {
							ProgressView()
								.tint(.white)
							Text("Bezig...")
						}
					} else {
						Text("Valideer e-mailadres")
					}
				}
				.disabled(sending)
				.buttonStyle(KKPrimaryButton())
				.padding(.horizontal, 24)
				.padding(.top, 16)

				Spacer(minLength: 24)
			}
		}
		.navigationTitle("")
		.navigationBarHidden(true)
		.background(KKTheme.surface.ignoresSafeArea())
	}
	
	private func sendMagicLink() {
		guard let verifiedEmail = model.verifiedEmail else {
			errorMessage = "Geen geverifieerd e-mailadres gevonden. Ga terug naar team selectie."
			return
		}
		
		sending = true
		model.submitEmail(verifiedEmail) { result in
			sending = false
			if case .failure(let error) = result {
				errorMessage = error.localizedDescription
			}
		}
	}
}

struct EnrollmentPendingView: View {
	@EnvironmentObject var model: AppModel
	@State private var simulating = false

	var body: some View {
		ScrollView {
			VStack(spacing: 24) {
				Spacer(minLength: 60)
				
				BrandAssets.logoImage()
					.resizable()
					.scaledToFit()
					.frame(width: 72, height: 72)

				VStack(spacing: 8) {
					Text("CHECK JE EMAIL")
						.font(KKFont.heading(24))
						.fontWeight(.regular)
						.kerning(-1.0)
						.foregroundStyle(KKTheme.textPrimary)
					
					Text("Bijna klaar!")
						.font(KKFont.title(18))
						.foregroundStyle(KKTheme.textSecondary)
				}
				.multilineTextAlignment(.center)

				Image(systemName: "envelope.open.fill")
					.font(.system(size: 64))
					.foregroundStyle(KKTheme.accent)
					.padding(.vertical, 16)
				
				VStack(alignment: .leading, spacing: 12) {
					Text("Instructies")
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
					Text("We hebben een bevestigingslink naar je e-mailadres gestuurd. Open de link op dit toestel om je aanmelding te voltooien.")
						.font(KKFont.body(14))
						.foregroundStyle(KKTheme.textSecondary)
				}
				.kkCard()
				.padding(.horizontal, 24)

				Button {
					simulating = true
					model.simulateOpenMagicLink { _ in simulating = false }
				} label: {
					if simulating {
						HStack {
							ProgressView()
								.tint(.white)
							Text("Bezig...")
						}
					} else {
						Text("Simuleer bevestigingslink")
					}
				}
				.disabled(simulating)
				.buttonStyle(KKPrimaryButton())
				.padding(.horizontal, 24)
				.padding(.top, 16)

#if DEBUG
Button(action: {
    if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
        model.handleEnrollmentDeepLink(token: pasted) { _ in }
    }
}) {
    Label("Plak bevestigingslink token", systemImage: "doc.on.clipboard")
}
.buttonStyle(.bordered)
.tint(.gray)
.padding(.horizontal, 24)
#endif

				Spacer(minLength: 60)
			}
		}
		.navigationTitle("")
		.navigationBarHidden(true)
		.background(KKTheme.surface.ignoresSafeArea())
	}
}

struct RoleSelectionView: View {
	let invite: AppModel.TenantInvite
	let onSelectManager: () -> Void
	let onSelectMember: () -> Void
	let onRescan: () -> Void
	
	var body: some View {
		VStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 12) {
				Text("Gevonden club")
					.font(KKFont.body(12))
					.foregroundStyle(KKTheme.textSecondary)
				Text(invite.tenantName)
					.font(KKFont.title(20))
					.foregroundStyle(KKTheme.textPrimary)
				
				Text("Ik meld me aan als…")
					.font(KKFont.body(12))
					.foregroundStyle(KKTheme.textSecondary)
				
				VStack(spacing: 12) {
					Button(action: onSelectManager) {
						Text("Teammanager")
							.font(KKFont.title(16))
							.frame(maxWidth: .infinity)
							.padding(.vertical, 14)
					}
					.background(KKTheme.surfaceAlt)
					.foregroundStyle(KKTheme.textPrimary)
					.cornerRadius(12)
					.overlay(RoundedRectangle(cornerRadius: 12).stroke(KKTheme.surfaceAlt, lineWidth: 1))
					
					Button(action: onSelectMember) {
						Text("Verenigingslid")
							.font(KKFont.title(16))
							.frame(maxWidth: .infinity)
							.padding(.vertical, 14)
					}
					.background(KKTheme.surfaceAlt)
					.foregroundStyle(KKTheme.textPrimary)
					.cornerRadius(12)
					.overlay(RoundedRectangle(cornerRadius: 12).stroke(KKTheme.surfaceAlt, lineWidth: 1))
				}
			}
			.kkCard()
			.padding(.horizontal, 24)
			
			Button(action: onRescan) {
				Label("Opnieuw scannen", systemImage: "qrcode.viewfinder")
			}
			.buttonStyle(KKPrimaryButton())
			.padding(.horizontal, 24)
		}
	}
}

struct ManagerVerifyView: View {
	let invite: AppModel.TenantInvite
	let onVerified: () -> Void
	@EnvironmentObject var model: AppModel
	@State private var email: String = ""
	@State private var verifying = false
	@State private var errorMessage: String?
	
	var body: some View {
		VStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 12) {
				Text("Teammanager")
					.font(KKFont.body(12))
					.foregroundStyle(KKTheme.textSecondary)
				Text(invite.tenantName)
					.font(KKFont.title(20))
					.foregroundStyle(KKTheme.textPrimary)
				VStack(alignment: .leading, spacing: 8) {
					Text("E-mailadres")
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
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
							.autocapitalization(.none)
							.font(KKFont.body(16))
							.foregroundColor(KKTheme.textPrimary)
					}
				}
				if let errorMessage = errorMessage {
					Text(errorMessage)
						.font(KKFont.body(12))
						.foregroundStyle(.red)
				}
				Button(action: verifyTeams) {
					if verifying {
						HStack { ProgressView().tint(.white); Text("Controleren...") }
					} else {
						Text("Teams ophalen")
					}
				}
				.disabled(verifying)
				.buttonStyle(KKSecondaryButton())
			}
			.kkCard()
			.padding(.horizontal, 24)
		}
		.dismissKeyboardOnTap()
	}
	
	private func verifyTeams() {
		guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
			errorMessage = "Voer je e-mailadres in om teams op te halen"
			return
		}
		verifying = true
		errorMessage = nil
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
			verifying = false
			if email == "a@b.nl" {
				let teams = [
					AppModel.Team(id: "team_jo11_3", code: "JO11-3", naam: "JO11-3"),
					AppModel.Team(id: "team_jo8_2jm", code: "JO8-2JM", naam: "JO8-2JM")
				]
				let updatedInvite = AppModel.TenantInvite(tenantId: invite.tenantId, tenantName: invite.tenantName, allowedTeams: teams)
				model.handleScannedInvite(updatedInvite)
				model.verifiedEmail = email
				onVerified()
			} else {
				errorMessage = "Dit e-mailadres is niet bekend als teammanager bij \(invite.tenantName)"
			}
		}
	}
}

struct MemberEnrollView: View {
	let invite: AppModel.TenantInvite
	@EnvironmentObject var model: AppModel
	@State private var searchQuery: String = ""
	@State private var searchResults: [AppModel.Team] = []
	@State private var selectedMemberTeamIds: Set<String> = []
	@State private var searchWorkItem: DispatchWorkItem?
	
	var body: some View {
		VStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 12) {
				Text("Verenigingslid")
					.font(KKFont.body(12))
					.foregroundStyle(KKTheme.textSecondary)
				Text(invite.tenantName)
					.font(KKFont.title(20))
					.foregroundStyle(KKTheme.textPrimary)
				VStack(alignment: .leading, spacing: 8) {
					Text("Zoek je team(s)")
						.font(KKFont.body(12))
						.foregroundStyle(KKTheme.textSecondary)
					ZStack(alignment: .leading) {
						if searchQuery.isEmpty {
							Text("Bijv. JO11-3")
								.foregroundColor(.secondary)
								.padding(.leading, 12)
								.font(KKFont.body(16))
						}
						TextField("", text: $searchQuery)
							.padding(12)
							.background(KKTheme.surfaceAlt)
							.cornerRadius(8)
							.textInputAutocapitalization(.never)
							.autocorrectionDisabled(true)
							.submitLabel(.search)
							.font(KKFont.body(16))
							.foregroundColor(KKTheme.textPrimary)
					}
				}
				.onChange(of: searchQuery) { _, _ in debounceSearch() }
				VStack(spacing: 8) {
					ForEach(searchResults, id: \.id) { team in
						Button(action: { toggleMemberSelection(team.id) }) {
							HStack {
								VStack(alignment: .leading, spacing: 2) {
									Text(team.naam)
										.font(KKFont.title(16))
										.foregroundStyle(KKTheme.textPrimary)
									if let code = team.code {
										Text(code)
											.font(KKFont.body(12))
											.foregroundStyle(KKTheme.textSecondary)
									}
								}
								Spacer()
								Image(systemName: selectedMemberTeamIds.contains(team.id) ? "checkmark.circle.fill" : "circle")
									.foregroundStyle(selectedMemberTeamIds.contains(team.id) ? KKTheme.accent : KKTheme.textSecondary)
							}
						}
						.padding(12)
						.background(KKTheme.surfaceAlt)
						.cornerRadius(8)
					}
				}
			}
			.kkCard()
			.padding(.horizontal, 24)
			Button(action: registerMember) {
				Text("Aanmelden")
			}
			.disabled(selectedMemberTeamIds.isEmpty)
			.buttonStyle(KKSecondaryButton())
			.padding(.horizontal, 24)
		}
	}
	
	private func debounceSearch() {
		searchWorkItem?.cancel()
		let work = DispatchWorkItem { performSearch() }
		searchWorkItem = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
	}
	private func performSearch() {
		let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { searchResults = []; return }
		model.backend.searchTeams(tenantId: invite.tenantId, query: q) { result in
			DispatchQueue.main.async {
				switch result {
				case .success(let teams): searchResults = teams
				case .failure: searchResults = []
				}
			}
		}
	}
	private func toggleMemberSelection(_ teamId: String) {
		if selectedMemberTeamIds.contains(teamId) { selectedMemberTeamIds.remove(teamId) } else { selectedMemberTeamIds.insert(teamId) }
	}
	private func registerMember() {
		let teamIds = Array(selectedMemberTeamIds)
		model.registerMember(tenantId: invite.tenantId, tenantName: invite.tenantName, teamIds: teamIds) { _ in }
	}
}
