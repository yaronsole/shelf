import Foundation

// All user-visible strings in one place. No hardcoded strings in views.
enum Strings {

    enum Onboarding {
        enum Welcome {
            static let appName = "Shelf"
            static let valueProp = "Your next favorite book is waiting."
            static let subtitle = "Tell us what you love."
            static let cta = "Get Started"
        }

        enum SeedSearch {
            static let title = "Books You Love"
            static let subtitle = "Tap a cover to mark it as read. Hold to save for later."
            static let searchPlaceholder = "Search by title or author…"
            static let minimumCount = "3 of 3 minimum"
            static let encouragement = "More books = better picks"
            static let continueCTA = "Continue"
            static let chipTitleMaxLength = 20
        }

        enum ChainDiscovery {
            static let title = "Add more to your taste"
            static let subtitle = "Tap a cover to mark it as read. Hold to save for later. Tap or hold again to undo."
            static let sectionPrefix = "Readers who love"
            static let sectionSuffix = "also love"
            static let continueCTA = "Continue"
            static let skipCTA = "Skip"
        }

        enum Confirmation {
            static let title = "Your Taste Profile"
            static let subtitle = "Here's what we'll use to find your picks."
            static let cta = "Build my shelf"
            static let removeWarning = "Removing this book may change your future recommendations"
            static let removeAction = "Remove"
            static let cancel = "Cancel"
        }

        enum Generating {
            static let copy = "We're curating your first picks. Check back in a few minutes — or tomorrow morning for a full fresh batch."
        }
    }

    enum Discover {
        static let tabTitle = "Discover"
        static let comfortZoneLabel = "Outside your usual"
        static let newBatchBanner = "New recommendations available"
        static let refreshAction = "Refresh"

        static let networkError = "Couldn't load your picks right now. Try again in a bit."
        static let noRecsAvailable = "New picks arrive tomorrow morning. Come back then."

        enum AlreadyRead {
            static let title = "Did you like it?"
            static let lovedIt = "Loved it"
            static let didntLike = "Didn't like it"
        }

        enum Actions {
            static let save = "Save"
            static let dismiss = "Dismiss"
            static let alreadyRead = "Already Read"
        }

        // At least 6 pairs required (DISC-12)
        static let endOfFeedTaglines: [(witty: String, cta: String)] = [
            ("You've reached the bottom of the shelf.", "Generate more"),
            ("All caught up. Impressive.", "Pull more picks"),
            ("That's this batch.", "Want more?"),
            ("The algorithm has spoken.", "Make it speak again"),
            ("End of the stack.", "Dig deeper"),
            ("Your shelf, fully explored.", "Find more"),
            ("Nothing left to scroll. For now.", "Generate fresh picks"),
            ("You read faster than we recommend.", "Generate more"),
        ]
    }

    enum ReadingList {
        static let tabTitle = "Reading List"
        static let emptyTitle = "Nothing saved yet."
        static let emptySubtitle = "Tap Save on any recommendation to add it here."
        static let showMore = "Show more"
        static let showLess = "Show less"
        static let markAsRead = "Mark as Read"
        static let remove = "Remove"
    }

    enum TasteProfile {
        static let tabTitle = "Taste"
        static let addBook = "Add Book"
        static let warningBelowMin = "You're running low on taste signals. Add more books for better picks."
        static let removeWarning = "Removing this book may change your future recommendations"
        static let removeAction = "Remove"
        static let cancel = "Cancel"
    }

    enum Settings {
        static let tabTitle = "Settings"
        static let about = "About Shelf"
        static let feedback = "Send Feedback"
        static let privacy = "Privacy Policy"
        static let terms = "Terms of Service"
        static let debugSectionTitle = "Debug Info"
        static let lastGeneration = "Last generation"
        static let batchSize = "Last batch size"
        static let never = "Never"
        static let versionPrefix = "Version"
    }

    enum Common {
        static let retry = "Try Again"
        static let done = "Done"
        static let cancel = "Cancel"
        static let remove = "Remove"
        static let add = "Add"
        static let loading = "Loading…"
    }
}
