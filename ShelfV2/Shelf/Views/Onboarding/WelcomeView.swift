import SwiftUI

struct WelcomeView: View {
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color(.label))

                VStack(spacing: 8) {
                    Text(Strings.Onboarding.Welcome.appName)
                        .font(.system(size: 44, weight: .bold, design: .serif))

                    Text(Strings.Onboarding.Welcome.valueProp)
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)

                    Text(Strings.Onboarding.Welcome.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            Button(action: onGetStarted) {
                Text(Strings.Onboarding.Welcome.cta)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(.label))
                    .foregroundStyle(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
