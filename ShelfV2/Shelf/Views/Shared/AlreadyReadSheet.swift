import SwiftUI

struct AlreadyReadSheet: View {
    let title: String
    var onLoved: () -> Void
    var onDidntLike: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.separator))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            Text(Strings.ForYou.AlreadyRead.title)
                .font(.title3.bold())
                .padding(.bottom, 4)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

            HStack(spacing: 16) {
                Button {
                    onLoved()
                    dismiss()
                } label: {
                    Label(Strings.ForYou.AlreadyRead.lovedIt, systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color(.systemPink))

                Button {
                    onDidntLike()
                    dismiss()
                } label: {
                    Label(Strings.ForYou.AlreadyRead.didntLike, systemImage: "hand.thumbsdown")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.hidden)
    }
}
