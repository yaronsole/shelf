#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/shelf-model-migration.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
# Last shipped schema reviewed for this change. Using the real source preserves
# SwiftData's entity/model names when exercising automatic additive migration.
git show 46e56afe935c03070241ad74dc01a84e1ee46cac:ShelfV2/Shelf/Models/SwiftDataModels.swift > "$check_dir/LegacyModels.swift"
cat > "$check_dir/Write.swift" <<'SWIFT'
import Foundation
import SwiftData
@main struct Check {
    @MainActor static func main() throws {
        let config = ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let container = try ModelContainer(for: CachedRecommendation.self, ReadingListItem.self, LocalSeedBook.self, configurations: config)
        container.mainContext.insert(ReadingListItem(id: "old-save", title: "Old saved book", author: "Author", coverURL: "", blurb: "Why I saved it"))
        try container.mainContext.save()
    }
}
SWIFT
cat > "$check_dir/Read.swift" <<'SWIFT'
import Foundation
import SwiftData
@main struct Check {
    @MainActor static func main() throws {
        let config = ModelConfiguration(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let container = try ModelContainer(for: CachedRecommendation.self, ReadingListItem.self, LocalSeedBook.self, configurations: config)
        let books = try container.mainContext.fetch(FetchDescriptor<ReadingListItem>())
        precondition(books.count == 1 && books[0].id == "old-save")
        precondition(books[0].blurb == "Why I saved it" && !books[0].isUpNext)
        books[0].isUpNext = true
        try container.mainContext.save()
        print("PASS: existing saved-book store upgrades without losing books or context")
    }
}
SWIFT
swiftc -parse-as-library -module-name ShelfModelMigration ShelfV2/Shelf/Config/DomainConfig.swift "$check_dir/LegacyModels.swift" "$check_dir/Write.swift" -o "$check_dir/write"
"$check_dir/write" "$check_dir/books.store"
swiftc -parse-as-library -module-name ShelfModelMigration ShelfV2/Shelf/Config/DomainConfig.swift ShelfV2/Shelf/Models/SwiftDataModels.swift "$check_dir/Read.swift" -o "$check_dir/read"
"$check_dir/read" "$check_dir/books.store"
