import SwiftUI

/// One-time gesture hint popup. Used on first entry to For You and Shelf.
struct GestureHintPopup: View {
    let title: String
    let subtitle: String
    let rows: [(chip: String, description: String)]
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    ForEach(rows, id: \.chip) { row in
                        GestureRow(chip: row.chip, description: row.description)
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Text("got it")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(hex: 0x1A1A1A))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Factory

    static func forYou(onDismiss: @escaping () -> Void) -> GestureHintPopup {
        GestureHintPopup(
            title: "how shelf works",
            subtitle: "two gestures, no buttons",
            rows: [
                (chip: "tap",        description: "open details — then react"),
                (chip: "long press", description: "save straight to your shelf"),
            ],
            onDismiss: onDismiss
        )
    }

    static func shelf(onDismiss: @escaping () -> Void) -> GestureHintPopup {
        GestureHintPopup(
            title: "your shelf",
            subtitle: "two things to know",
            rows: [
                (chip: "tap",        description: "open on Amazon"),
                (chip: "swipe left", description: "remove from shelf"),
            ],
            onDismiss: onDismiss
        )
    }
}

private struct GestureRow: View {
    let chip: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Text(chip)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: 0x1A1A1A))
                .clipShape(Capsule())
                .fixedSize()

            Text(description)
                .font(.subheadline)
                .foregroundStyle(Color(.label))
        }
    }
}
