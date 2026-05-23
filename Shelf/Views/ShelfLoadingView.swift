import SwiftUI

// MARK: - ShelfLoadingView (LD-01, LD-02, OB-03)

struct ShelfLoadingView: View {

    // LD-01: 4 named stages
    private let stages: [String] = [
        "Reading your taste profile...",
        "Scanning thousands of titles...",
        "Shortlisting strong matches...",
        "Picking the best ones for you..."
    ]

    @State private var currentStage: Int = 0
    @State private var progressFraction: CGFloat = 0.0
    @State private var showInsight: Bool = false

    // OB-03: taste insight derived locally from UserDefaults (Option A — no secondary LLM call)
    private var tasteInsight: String? {
        let labels = UserDefaults.standard.stringArray(forKey: "selectedVibeLabels") ?? []
        guard !labels.isEmpty else { return nil }
        let shown = labels.prefix(3).joined(separator: " · ")
        return "Tuned for: \(shown)"
    }

    var body: some View {
        ZStack {
            Color(hex: "1C1C1E").ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                // Book emoji
                Text("📚")
                    .font(.system(size: 48))

                // LD-02: Stage message
                Text(stages[currentStage])
                    .font(.custom("Georgia", size: 20)).italic()
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .id(currentStage)          // forces view replace → cross-fade
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: currentStage)
                    .padding(.horizontal, 40)

                // LD-01: Progress bar + stage dots
                VStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 4)
                            Capsule()
                                .fill(Color(hex: "D4AF37"))
                                .frame(width: geo.size.width * progressFraction, height: 4)
                                .animation(.easeInOut(duration: 0.8), value: progressFraction)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 48)

                    // Dot indicators
                    HStack(spacing: 10) {
                        ForEach(0..<stages.count, id: \.self) { i in
                            Circle()
                                .fill(i <= currentStage
                                      ? Color(hex: "D4AF37")
                                      : Color.white.opacity(0.2))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: currentStage)
                }

                // OB-03: Taste insight pill
                if showInsight, let insight = tasteInsight {
                    Text(insight)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer()

                Text("This usually takes 5–10 seconds")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.bottom, 28)
            }
        }
        .onAppear { startSequence() }
    }

    // LD-01: Advance through stages, hold at stage 3 (last)
    private func startSequence() {
        let stageDuration = 2.2  // seconds per stage

        // Initial fill toward 25% (stage 0 active)
        withAnimation(.easeInOut(duration: stageDuration * 0.85)) {
            progressFraction = 0.25
        }

        // Advance to stages 1, 2, 3
        for stageIndex in 1..<stages.count {
            let delay = Double(stageIndex) * stageDuration
            let targetFraction = CGFloat(stageIndex + 1) / CGFloat(stages.count)
            let isLast = stageIndex == stages.count - 1

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentStage = stageIndex
                }
                // Last stage: quick snap to 100%; others fill steadily
                withAnimation(.easeInOut(duration: isLast ? 0.7 : stageDuration * 0.85)) {
                    progressFraction = targetFraction
                }
            }
        }

        // OB-03: reveal taste insight after first stage completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showInsight = true
            }
        }
    }
}

// MARK: - ConfettiView (unchanged — used by RecommendationsView on first reveal)

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let x, startY, size: CGFloat
    let color: Color
    let delay, duration: Double
}

struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []
    @State private var fallen = false

    private let colors: [Color] = [
        Color(hex: "D4AF37"), .white, .orange, Color(hex: "1F3D2B"), Color(hex: "1F2B3D")
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    Circle()
                        .fill(p.color.opacity(0.85))
                        .frame(width: p.size, height: p.size)
                        .position(x: p.x, y: fallen ? geo.size.height + 60 : p.startY)
                        .opacity(fallen ? 0 : 1)
                        .animation(
                            .easeIn(duration: p.duration).delay(p.delay),
                            value: fallen
                        )
                }
            }
            .onAppear {
                particles = (0..<45).map { i in
                    ConfettiParticle(
                        x: CGFloat(i) / 45 * geo.size.width + CGFloat.random(in: -15...15),
                        startY: CGFloat.random(in: -20...geo.size.height * 0.4),
                        size: CGFloat.random(in: 5...11),
                        color: colors[i % colors.count],
                        delay: Double(i) * 0.025,
                        duration: Double.random(in: 0.7...1.4)
                    )
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    fallen = true
                }
            }
        }
        .allowsHitTesting(false)
    }
}
