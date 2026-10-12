import SwiftUI

// MARK: - Toast kinds (TST-1 through TST-8)

enum ToastKind {
    case actionFailed
    case savedToShelf      // TST-1
    case passed            // TST-2
    case reactedRead       // TST-3
    case reactedPass       // TST-4
    case removedFromShelf  // TST-5
    case removedFromTaste  // TST-6
    case firstGeneration   // TST-7
    case dailyRefresh      // TST-8

    var message: String {
        switch self {
        case .actionFailed:     return "Couldn’t sync that change. Please try again."
        case .savedToShelf:     return "added to your shelf"
        case .passed:           return "noted, moving on"
        case .reactedRead:      return "added to the books you love"
        case .reactedPass:      return "noted, not your thing"
        case .removedFromShelf: return "off the shelf"
        case .removedFromTaste: return "removed from your taste"
        case .firstGeneration:  return "shaping your shelf — browse Discover while we cook"
        case .dailyRefresh:     return "fresh picks for today"
        }
    }

    var iconName: String {
        switch self {
        case .actionFailed:     return "exclamationmark.icloud"
        case .savedToShelf:     return "bookmark.fill"
        case .passed:           return "arrow.right"
        case .reactedRead:      return "checkmark"
        case .reactedPass:      return "arrow.right"
        case .removedFromShelf: return "xmark"
        case .removedFromTaste: return "xmark"
        case .firstGeneration:  return "sparkles"
        case .dailyRefresh:     return "sparkles"
        }
    }

    // Spec: colored circle icon matching action category
    var iconColor: Color {
        switch self {
        case .actionFailed:     return Color.orange
        case .savedToShelf:     return Color(hexString: "FAC775") // gold
        case .passed:           return Color(hexString: "CECBF6") // lavender
        case .reactedRead:      return Color(hexString: "9FE1CB") // mint
        case .reactedPass:      return Color(hexString: "CECBF6") // lavender
        case .removedFromShelf: return Color(hexString: "F4C0D1") // pink
        case .removedFromTaste: return Color(hexString: "F4C0D1") // pink
        case .firstGeneration:  return Color(hexString: "FAC775") // gold
        case .dailyRefresh:     return Color(hexString: "9FE1CB") // mint
        }
    }
}

// MARK: - Toast item

struct ToastItem: Equatable {
    let kind: ToastKind
    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.kind == rhs.kind
    }
}

extension ToastKind: Equatable {}

// MARK: - ToastManager singleton

@Observable
final class ToastManager {
    static let shared = ToastManager()
    private init() {}

    var current: ToastItem? = nil
    var undoAction: (() -> Void)? = nil
    var actionLabel = "Undo"
    private var dismissTask: Task<Void, Never>?

    func show(_ kind: ToastKind, undo: (() -> Void)? = nil, retry: (() -> Void)? = nil) {
        // Existing callers may repeat the same confirmation. Preserve its Undo.
        if undo == nil, retry == nil, current?.kind == kind, undoAction != nil { return }
        dismissTask?.cancel()
        undoAction = undo ?? retry
        actionLabel = retry == nil ? "Undo" : "Retry"
        current = ToastItem(kind: kind)
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(undo == nil && retry == nil ? 2.0 : 6.0))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) { self.current = nil; self.undoAction = nil }
            }
        }
    }
}

// MARK: - Toast view

struct ToastView: View {
    let item: ToastItem
    var onUndo: (() -> Void)? = nil
    var actionLabel = "Undo"

    var body: some View {
        HStack(spacing: 10) {
            // 22pt colored icon circle
            ZStack {
                Circle()
                    .fill(item.kind.iconColor.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: item.kind.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(item.kind.iconColor)
            }

            Text(item.kind.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let onUndo {
                Button(actionLabel, action: onUndo)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(minWidth: 160, maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: 0x1A1A1A))
        )
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Toast overlay (place at root, above tab bar)

struct ToastOverlay: View {
    @State private var manager = ToastManager.shared

    var body: some View {
        VStack {
            Spacer()
            if let item = manager.current {
                ToastView(item: item, onUndo: manager.undoAction == nil ? nil : {
                    let action = manager.undoAction
                    manager.current = nil
                    manager.undoAction = nil
                    action?()
                }, actionLabel: manager.actionLabel)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    // 24pt above the tab bar (tab bar ~49pt + home indicator ~34pt)
                    .padding(.bottom, 107)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.25), value: manager.current)
    }
}
