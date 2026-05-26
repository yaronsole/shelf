import SwiftUI

struct WelcomeView: View {
    var onGetStarted: () -> Void

    private let cream = Color(hex: 0xFAF6F0)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                cream.ignoresSafeArea()

                // Animated cover wall, top-aligned so the looping math works.
                // Held back in opacity so it reads as ambient background, not foreground content.
                SplashCoverScrollView()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.55)

                // Cream gradient at the bottom only — fades covers into the CTA bar
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [cream.opacity(0), cream, cream],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 260)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // CTA anchored at the bottom — no copy, just the button
                VStack {
                    Spacer()
                    Button(action: onGetStarted) {
                        Text(Strings.Onboarding.Welcome.cta)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(hex: 0x1A1A1A))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
    }
}
