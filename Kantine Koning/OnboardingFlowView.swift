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
						// Show scan results with email verification
						ClubFoundView(invite: invite) {
							navigateTeam = true
						} onRescan: {
							model.invite = nil // Reset invite to show scanner again
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
						}
					}

					Spacer(minLength: 24)
				}
			}
			.navigationTitle("")
			.navigationBarHidden(true)
			.background(KKTheme.surface.ignoresSafeArea())
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
				let tenantName = inviteComps.queryItems?.first(where: { $0.name == "tenant_name" })?.value?.removingPercentEncoding
				
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

struct ClubFoundView: View {
	let invite: AppModel.TenantInvite
	let onTeamsVerified: () -> Void
	let onRescan: () -> Void
	
	@EnvironmentObject var model: AppModel
	@State private var email: String = ""
	@State private var verifying = false
	@State private var errorMessage: String?
	@State private var teamsVerified = false
	
	var body: some View {
		VStack(spacing: 16) {
			VStack(alignment: .leading, spacing: 12) {
				Text("Gevonden club")
					.font(KKFont.body(12))
					.foregroundStyle(KKTheme.textSecondary)
				Text(invite.tenantName)
					.font(KKFont.title(20))
					.foregroundStyle(KKTheme.textPrimary)
				
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
							Text("Teams ophalen")
						}
					}
					.disabled(verifying)
					.buttonStyle(KKSecondaryButton())
				} else {
					Button("Kies teams") { onTeamsVerified() }
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
		guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
			errorMessage = "Voer je e-mailadres in om teams op te halen"
			return
		}
		
		verifying = true
		errorMessage = nil
		
		// Mock API call to <tenant>.kantinekoning.com/api/?email=x
		let apiURL = "https://\(invite.tenantId).kantinekoning.com/api/?email=\(email)"
		print("🌐 Fetching teams from: \(apiURL)")
		
		// Simulate network delay
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
			verifying = false
			
			// Mock response based on email
			if email == "a@b.nl" {
				let teams = [
					AppModel.Team(id: "team_jo11_3", code: "JO11-3", naam: "JO11-3"),
					AppModel.Team(id: "team_jo8_2jm", code: "JO8-2JM", naam: "JO8-2JM")
				]
				
				print("✅ Teams verified for \(email): \(teams.map { $0.naam })")
				
				// Update the invite with verified teams
				let updatedInvite = AppModel.TenantInvite(
					tenantId: invite.tenantId,
					tenantName: invite.tenantName,
					allowedTeams: teams
				)
				model.handleScannedInvite(updatedInvite)
				model.verifiedEmail = email // Store for magic link validation
				teamsVerified = true
				
				// Directly navigate to team selection instead of showing "Kies teams" button
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
					onTeamsVerified()
				}
			} else {
				errorMessage = "Dit e-mailadres is niet bekend als teammanager bij \(invite.tenantName)"
				print("❌ Email \(email) not authorized for tenant \(invite.tenantId)")
			}
		}
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
					Text("We hebben een magic link naar je e-mailadres gestuurd. Open de link op dit toestel om je aanmelding te voltooien.")
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
						Text("Simuleer magic link")
					}
				}
				.disabled(simulating)
				.buttonStyle(KKPrimaryButton())
				.padding(.horizontal, 24)
				.padding(.top, 16)

				Spacer(minLength: 60)
			}
		}
		.navigationTitle("")
		.navigationBarHidden(true)
		.background(KKTheme.surface.ignoresSafeArea())
	}
}
