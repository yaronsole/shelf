import SwiftUI

struct WelcomeView: View {
    var onGetStarted: () -> Void

    private let cream = Color(hex: 0xFAF6F0)

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            SplashCoverScrollView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .clipped()

            // gradient overlays to fade covers into cream background
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [cream, cream.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 200)
                Spacer()
                LinearGradient(
                    colors: [cream.opacity(0), cream],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 320)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Text(Strings.Onboarding.Welcome.appName)
                        .font(.system(size: 44, weight: .bold, design: .serif))
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
        }
    }
}
