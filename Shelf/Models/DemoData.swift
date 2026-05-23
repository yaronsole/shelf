import Foundation

// MARK: - Demo Books
// Five hand-picked books shown before the user enters an API key.
// Covers via OpenLibrary; ASINs route to Amazon Kindle pages.

enum DemoData {
    static let books: [Book] = [
        Book(
            title: "Piranesi",
            author: "Susanna Clarke",
            asin: "B084DS54PL",
            isbn: "9781526622433",
            coverURL: "https://covers.openlibrary.org/b/isbn/9781526622433-L.jpg",
            description: "A man lives in a surreal House of infinite halls and statues, keeping meticulous journals — until clues suggest his world is far stranger than he imagined.",
            reasoningBlurb: "If you've ever wanted a book that feels like inhabiting a dream — one with its own logic, its own beauty, its own dread — this is it. I think about this one constantly.",
            awards: ["Hugo Award Winner"],
            synopsis: "Piranesi lives in the House. The House is enormous — its halls filled with statues, its lower tiers flooded with tidal seas. He knows of only two living people: himself and the Other. Then Piranesi discovers evidence of a third.",
            publicationYear: 2020,
            pageCount: 272,
            averageRating: 4.2
        ),
        Book(
            title: "Tomorrow, and Tomorrow, and Tomorrow",
            author: "Gabrielle Zevin",
            asin: "B09JB21J36",
            isbn: "9780593321201",
            coverURL: "https://covers.openlibrary.org/b/isbn/9780593321201-L.jpg",
            description: "Two friends become creative partners building video games across three decades — a novel about love, ambition, and what it means to make something that matters.",
            reasoningBlurb: "A novel about friendship that manages to also be about creativity, ambition, and what it means to make something that matters. Not what you expect. Much better.",
            awards: ["Pulitzer Finalist", "National Book Award Finalist"],
            synopsis: "Sam and Sadie meet as children, lose touch, then reconnect in college and form a game studio that will define their lives — and test everything between them.",
            publicationYear: 2022,
            pageCount: 416,
            averageRating: 4.3
        ),
        Book(
            title: "The Remains of the Day",
            author: "Kazuo Ishiguro",
            asin: "B002TQCUOA",
            isbn: "9780679731726",
            coverURL: "https://covers.openlibrary.org/b/isbn/9780679731726-L.jpg",
            description: "An English butler takes a road trip across the countryside, and in quiet reflection confronts a lifetime of misplaced loyalty and suppressed feeling.",
            reasoningBlurb: "Nothing happens. Everything happens. The most devastating novel about regret written in the 20th century, and it reads like a gentle afternoon drive.",
            awards: ["Booker Prize Winner"],
            synopsis: "Stevens, a butler of supreme dignity, sets out on a motoring trip through England and looks back on his years of service — and the cost of his absolute devotion to duty.",
            publicationYear: 1989,
            pageCount: 258,
            averageRating: 4.1
        ),
        Book(
            title: "Mexican Gothic",
            author: "Silvia Moreno-Garcia",
            asin: "B082BFRC8T",
            isbn: "9780525620785",
            coverURL: "https://covers.openlibrary.org/b/isbn/9780525620785-L.jpg",
            description: "A glamorous socialite investigates a crumbling mansion in 1950s Mexico — only to find its English family hiding something ancient and deeply wrong.",
            reasoningBlurb: "Creepy, glamorous, and deeply strange. If Daphne du Maurier grew up on mid-century Mexico City instead of Cornwall, she might have written this.",
            awards: ["Locus Award Winner"],
            synopsis: "Noemí Taboada travels to High Place, a rotting mansion in the Mexican countryside, to rescue her cousin — and encounters a horror rooted in eugenics, fungi, and greed.",
            publicationYear: 2020,
            pageCount: 301,
            averageRating: 3.9
        ),
        Book(
            title: "The Hitchhiker's Guide to the Galaxy",
            author: "Douglas Adams",
            asin: "B0043M4ZH0",
            isbn: "9780345391803",
            coverURL: "https://covers.openlibrary.org/b/isbn/9780345391803-L.jpg",
            description: "Moments before Earth is demolished for a hyperspace bypass, Arthur Dent is whisked into the galaxy by his alien friend Ford Prefect. Chaos and philosophy ensue.",
            reasoningBlurb: "The funniest thing I can recommend without reservation to basically any human. Also somehow about the meaninglessness of existence. Highly recommend.",
            awards: [],
            synopsis: "After Earth is destroyed, Arthur Dent hitches rides across the universe, guided by The Hitchhiker's Guide — a book that, on the whole, has had a more successful life than he has.",
            publicationYear: 1979,
            pageCount: 193,
            averageRating: 4.4
        )
    ]
}
