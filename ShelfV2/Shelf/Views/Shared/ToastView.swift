import SwiftUI

enum ToastKind {
    case save, read, pass

    var icon: String {
        switch self {
        case .save: return "bookmark.fill"
        case .read: return "checkmark"
        case .pass: return "xmark"
        }
    }

    var background: Color {
        switch self {
        case .save: return Color(red: 0.10, green: 0.35, blue: 0.85)  // blue
        case .read: return Color(red: 0.10, green: 0.45, blue: 0.30)  // green
        case .pass: return Color(.systemGray2)                          // neutral gray
        }
    }
}

struct Toast: Equatable {
    let kind: ToastKind
    let message: String
}

// MARK: - Inline toast view

private struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.kind.icon)
                .font(.subheadline.weight(.bold))
            Text(toast.message)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Capsule().fill(toast.kind.background))
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
        .padding(.horizontal, 16)
    }
}

// MARK: - Modifier (binding-driven, auto-dismiss after ~1.8s)

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    @State private var dismissTask: Task<Void, Never>? = nil

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { dismiss() }
                        .padding(.top, 4)
                        .zIndex(100)
                        .onAppear { scheduleAutoDismiss() }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toast)
    }

    private func dismiss() {
        dismissTask?.cancel()
        toast = nil
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .milliseconds(1800))
            if Task.isCancelled { return }
            await MainActor.run { self.toast = nil }
        }
    }
}

extension View {
    /// Attach a top toast bound to an optional Toast. Auto-dismisses after ~1.8s.
    func toast(_ binding: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: binding))
    }
}
