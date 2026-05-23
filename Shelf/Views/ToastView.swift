import SwiftUI

struct ToastView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Gold left-border accent
            Rectangle()
                .fill(Color(hex: "D4AF37"))
                .frame(width: 4)
                .clipShape(Capsule())

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.trailing, 16)
        .background(Color(hex: "2C2C2E"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    onDismiss()
                }
            }
        }
    }
}
