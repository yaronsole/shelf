import SwiftUI

/// Curated-lists browser. Stub for Phase 3 — the actual list catalog and
/// detail views land in Phase 6.
struct DiscoverView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
                Text(Strings.Discover.comingSoon)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
