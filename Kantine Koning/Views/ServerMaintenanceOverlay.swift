import SwiftUI

/// Full-screen overlay shown when the Kantine Koning backend is unavailable
/// Blocks the entire app with a friendly maintenance message
struct ServerMaintenanceOverlay: View {
    let onRetry: () -> Void
    @State private var isRetrying = false
    @State private var lastRetryTime: Date?
    
    private var canRetry: Bool {
        guard let lastRetry = lastRetryTime else { return true }
        return Date().timeIntervalSince(lastRetry) > 10 // 10 second cooldown
    }
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Icon
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 64))
                    .foregroundStyle(KKTheme.accent)
                
                // Title and message
                VStack(spacing: 12) {
                    Text("Even geduld...")
                        .font(KKFont.heading(28))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    
                    Text("Onze engineers werken hard om het platform te verbeteren. Dit kan enkele minuten duren.")
                        .font(KKFont.body(16))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    // Status indicator
                    if isRetrying {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Verbinding controleren...")
                                .font(KKFont.body(14))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.top, 8)
                    } else if !canRetry {
                        Text("Wacht nog even voor je het opnieuw probeert")
                            .font(KKFont.body(14))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.top, 8)
                    }
                }
                
                // Retry button
                Button(action: handleRetry) {
                    HStack(spacing: 8) {
                        if isRetrying {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        Text(isRetrying ? "Even geduld..." : "Opnieuw proberen")
                            .font(KKFont.body(16))
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(canRetry && !isRetrying ? KKTheme.accent : KKTheme.accent.opacity(0.5))
                    .clipShape(Capsule())
                }
                .disabled(!canRetry || isRetrying)
                .padding(.top, 16)
            }
            .padding(24)
        }
    }
    
    private func handleRetry() {
        guard canRetry else { return }
        
        isRetrying = true
        lastRetryTime = Date()
        
        // Call the retry action
        onRetry()
        
        // Reset after 3 seconds (enough time for API call)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            isRetrying = false
        }
    }
}

#Preview {
    ServerMaintenanceOverlay(onRetry: {})
}

