import SwiftUI

struct SeasonOverviewView: View {
    let tenant: DomainModel.Tenant
    @EnvironmentObject var store: AppStore
    @State private var showConfetti = false
    @State private var confettiTrigger = 0
    @State private var showResetConfirmation = false
    
    // Use LOCAL data from AppStore.upcoming for statistics (Personal Performance Focus)
    private var seasonStats: SeasonStats {
        SeasonStats.calculate(from: store.upcoming, for: tenant.slug, with: tenant)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)
                
                // Header with confetti overlay (consistent with app style)
                VStack(spacing: 8) {
                    Text("SEIZOEN AFGELOPEN")
                        .font(KKFont.heading(24))
                        .fontWeight(.regular)
                        .kerning(-1.0)
                        .foregroundStyle(KKTheme.textPrimary)
                    Text(tenant.name)
                        .font(KKFont.title(16))
                        .foregroundStyle(KKTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .overlay(ConfettiView(trigger: confettiTrigger).allowsHitTesting(false))
                
                // Main statistics card
                SeasonStatsCard(stats: seasonStats)
                
                // Achievements card
                if !seasonStats.achievements.isEmpty {
                    AchievementsCard(achievements: seasonStats.achievements)
                }
                
                // Team contributions card
                if !seasonStats.teamContributions.isEmpty {
                    TeamContributionsCard(contributions: seasonStats.teamContributions)
                }
                
                // Thank you card
                ThankYouCard()
                
                // Reset button card
                ResetTenantCard(tenant: tenant) {
                    showResetConfirmation = true
                }
                
                Spacer(minLength: 100)
            }
        }
        .background(KKTheme.surface)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Trigger confetti celebration
            triggerConfetti()
        }
        .alert("Seizoen Data Verwijderen", isPresented: $showResetConfirmation) {
            Button("Annuleren", role: .cancel) { }
            Button("Verwijderen", role: .destructive) {
                resetTenant()
            }
        } message: {
            Text("Dit verwijdert alle gegevens van \(tenant.name) uit de app. Deze actie kan niet ongedaan worden gemaakt.")
        }
    }
    
    private func triggerConfetti() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { 
            showConfetti = true 
        }
        confettiTrigger += 1
        
        // Add iPhone vibration for extra celebration
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Second burst after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            confettiTrigger += 1
            let lightFeedback = UIImpactFeedbackGenerator(style: .light)
            lightFeedback.impactOccurred()
        }
    }
    
    private func resetTenant() {
        Logger.userInteraction("Reset Tenant", target: "SeasonOverview", context: ["tenant": tenant.slug])
        store.removeSeasonEndedTenant(tenant.slug)
    }
}

// MARK: - Season Stats Card
struct SeasonStatsCard: View {
    let stats: SeasonStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Jouw Prestaties")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    icon: "clock.fill",
                    title: "Totaal Uren",
                    value: String(format: "%.1f", stats.totalHours),
                    subtitle: "uur gewerkt"
                )
                
                StatCard(
                    icon: "calendar.badge.checkmark",
                    title: "Diensten",
                    value: "\(stats.totalShifts)",
                    subtitle: "voltooid"
                )
                
                if let location = stats.favoriteLocation {
                    StatCard(
                        icon: "location.fill",
                        title: "Favoriete Locatie",
                        value: location,
                        subtitle: "meest gebruikt"
                    )
                }
                
                if let month = stats.mostActiveMonth {
                    StatCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Drukste Maand",
                        value: month,
                        subtitle: "meeste diensten"
                    )
                }
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(KKTheme.accent)
            
            Text(value)
                .font(KKFont.title(16))
                .foregroundStyle(KKTheme.textPrimary)
                .multilineTextAlignment(.center)
            
            Text(title)
                .font(KKFont.body(10))
                .foregroundStyle(KKTheme.textSecondary)
                .multilineTextAlignment(.center)
            
            Text(subtitle)
                .font(KKFont.body(9))
                .foregroundStyle(KKTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(KKTheme.surfaceAlt)
        .cornerRadius(8)
    }
}

// MARK: - Achievements Card
struct AchievementsCard: View {
    let achievements: [Achievement]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Behaalde Prestaties")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            ForEach(achievements.indices, id: \.self) { index in
                AchievementRow(achievement: achievements[index])
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

struct AchievementRow: View {
    let achievement: Achievement
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.icon)
                .font(.system(size: 20))
                .foregroundStyle(.yellow)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(KKFont.title(14))
                    .foregroundStyle(KKTheme.textPrimary)
                
                Text(achievement.description)
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Team Contributions Card
struct TeamContributionsCard: View {
    let contributions: [TeamContribution]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jouw Teams")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            ForEach(contributions.indices, id: \.self) { index in
                TeamContributionRow(contribution: contributions[index])
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

struct TeamContributionRow: View {
    let contribution: TeamContribution
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(contribution.teamName)
                .font(KKFont.title(14))
                .foregroundStyle(KKTheme.textPrimary)
            
            HStack {
                Text(String(format: "%.1f uur", contribution.hoursWorked))
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
                
                Text("•")
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
                
                Text("\(contribution.shiftsCompleted) diensten")
                    .font(KKFont.body(12))
                    .foregroundStyle(KKTheme.textSecondary)
                
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Thank You Card
struct ThankYouCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bedankt!")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                
                Text("Bedankt voor je inzet dit seizoen!")
                    .font(KKFont.title(16))
                    .foregroundStyle(KKTheme.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text("Jouw vrijwilligerswerk heeft het verschil gemaakt. Tot volgend jaar!")
                    .font(KKFont.body(14))
                    .foregroundStyle(KKTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            .frame(maxWidth: .infinity)
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

// MARK: - Reset Tenant Card  
struct ResetTenantCard: View {
    let tenant: DomainModel.Tenant
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seizoen Data")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            Text("Verwijder alle gegevens van \(tenant.name) uit de app om ruimte te maken voor een nieuwe seizoen.")
                .font(KKFont.body(12))
                .foregroundStyle(KKTheme.textSecondary)
            
            Button(action: action) {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("Reset \(tenant.name)")
                        .font(KKFont.title(14))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(KKTheme.accent)
                .cornerRadius(8)
            }
        }
        .kkCard()
        .padding(.horizontal, 24)
    }
}

#Preview {
    let sampleTenant = DomainModel.Tenant(
        slug: "demo",
        name: "Demo Sportclub",
        teams: [],
        signedDeviceToken: "sample_token",
        enrollments: [],
        seasonEnded: true
    )
    
    SeasonOverviewView(tenant: sampleTenant)
        .environmentObject(AppStore())
}
