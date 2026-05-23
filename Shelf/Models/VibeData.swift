import SwiftUI

// MARK: - VibeOption

struct VibeOption: Identifiable {
    let id = UUID()
    let label: String
    let emoji: String
    let description: String
    let seedBooks: [String]
    let color: Color
}

// MARK: - Vibe Catalogue

let vibeOptions: [VibeOption] = [
    VibeOption(
        label: "Dark academia",
        emoji: "🕯️",
        description: "Tweed, obsession & murder",
        seedBooks: ["The Secret History", "If We Were Villains", "Ninth House", "The Atlas Six"],
        color: Color(hex: "3D2B1F")
    ),
    VibeOption(
        label: "Gut-punch endings",
        emoji: "💔",
        description: "Books that leave a mark",
        seedBooks: ["Never Let Me Go", "A Little Life", "The Road", "We Need to Talk About Kevin"],
        color: Color(hex: "3D1F2B")
    ),
    VibeOption(
        label: "Ideas that broke my brain",
        emoji: "🧠",
        description: "Science, philosophy & awe",
        seedBooks: ["Gödel Escher Bach", "The Selfish Gene", "Thinking Fast and Slow", "Sapiens"],
        color: Color(hex: "1F2B3D")
    ),
    VibeOption(
        label: "Comfort reads",
        emoji: "☕",
        description: "Warm, kind & restorative",
        seedBooks: ["The House in the Cerulean Sea", "Legends & Lattes", "A Man Called Ove", "Eleanor Oliphant is Completely Fine"],
        color: Color(hex: "2B3D1F")
    ),
    VibeOption(
        label: "Smart thrillers",
        emoji: "🔪",
        description: "Twists you didn't see coming",
        seedBooks: ["Gone Girl", "The Silent Patient", "Big Little Lies", "The Thursday Murder Club"],
        color: Color(hex: "2B1F3D")
    ),
    VibeOption(
        label: "Weird and wonderful",
        emoji: "🌀",
        description: "Strange, singular & unforgettable",
        seedBooks: ["Piranesi", "The Master and Margarita", "Kafka on the Shore", "House of Leaves"],
        color: Color(hex: "1F3D2B")
    ),
    VibeOption(
        label: "Literary slow burns",
        emoji: "📖",
        description: "Beautiful prose, quiet devastation",
        seedBooks: ["Normal People", "Stoner", "The Remains of the Day", "Middlemarch"],
        color: Color(hex: "3D3D1F")
    ),
    VibeOption(
        label: "True stories, stranger than fiction",
        emoji: "🌍",
        description: "Nonfiction that reads like a novel",
        seedBooks: ["The Devil in the White City", "Educated", "Say Nothing", "The Immortal Life of Henrietta Lacks"],
        color: Color(hex: "1F3D3D")
    )
]

// MARK: - Taste Reaction One-Liners

func tasteReactionLine(for selectedLabels: Set<String>) -> String {
    let has = { (label: String) in selectedLabels.contains(label) }

    // Specific combinations
    if has("Dark academia") && has("Gut-punch endings") {
        return "Dark academia and gut-punch endings? Shelf is very much here for this."
    }
    if has("Ideas that broke my brain") && has("Weird and wonderful") {
        return "You want your mind expanded AND bent sideways. Noted. This is going to be fun."
    }
    if has("Comfort reads") && has("Smart thrillers") {
        return "Comfort reads AND smart thrillers — you contain multitudes. Shelf respects it."
    }
    if has("Literary slow burns") && has("Gut-punch endings") {
        return "Slow burns that gut you? Shelf knows exactly where to take you."
    }

    // Single-vibe fallbacks
    if selectedLabels.count == 1 {
        switch selectedLabels.first {
        case "Dark academia":
            return "Excellent taste. A little dangerous, a little beautiful."
        case "Gut-punch endings":
            return "You're either brave or a glutton for punishment. Either way, Shelf is ready."
        case "Comfort reads":
            return "Shelf will take good care of you. Promise."
        case "Weird and wonderful":
            return "Finally, someone who wants the weird stuff. This is going to be good."
        case "Smart thrillers":
            return "You like your books sharp. Shelf can work with that."
        case "Literary slow burns":
            return "Patient readers get the best rewards. You're going to love what Shelf finds."
        case "Ideas that broke my brain":
            return "Big ideas incoming. Your brain is ready, even if the rest of you isn't."
        case "True stories, stranger than fiction":
            return "Reality is weirder than fiction. Shelf knows where to look."
        default: break
        }
    }

    // Generic fallback
    return "Shelf is getting a very clear picture of you. This is going to be good."
}
