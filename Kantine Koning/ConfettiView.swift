import SwiftUI

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
