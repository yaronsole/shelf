import SwiftUI

struct WelcomeView: View {
    var onGetStarted: () -> Void

    private let cream = Color(hex: 0xFAF6F0)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1) Base cream
                cream.ignoresSafeArea()

                // 2) Animated cover wall — pinned to the top so the looping
                //    offset stays visible (centering ate the content before).
                SplashCoverScrollView()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(0.85)

                // 3) Cream gradients top + bottom to fade the covers into the chrome
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [cream, cream.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 160)
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [cream.opacity(0), cream],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 280)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // 4) Foreground content — wordmark centered, CTA at the bottom
                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 10) {
                        Text(Strings.Onboarding.Welcome.appName)
                            .font(.system(size: 48, weight: .bold, design: .serif))
                            .foregroundStyle(Color(hex: 0x1A1A1A))

                        Text(Strings.Onboarding.Welcome.valueProp)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(hex: 0x1A1A1A).opacity(0.65))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

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
