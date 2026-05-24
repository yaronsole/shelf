import Foundation

// Curated list of widely-recognized books across genres, shown as a starter grid
// on the seed-book search screen. Looked up via Google Books on first display.
enum PopularBooks {
    static let books: [(title: String, author: String)] = [
        // Literary classics
        ("The Great Gatsby", "F. Scott Fitzgerald"),
        ("To Kill a Mockingbird", "Harper Lee"),
        ("1984", "George Orwell"),
        ("Pride and Prejudice", "Jane Austen"),
        ("Beloved", "Toni Morrison"),
        ("One Hundred Years of Solitude", "Gabriel García Márquez"),

        // Contemporary literary
        ("The Goldfinch", "Donna Tartt"),
        ("A Little Life", "Hanya Yanagihara"),
        ("Normal People", "Sally Rooney"),
        ("Pachinko", "Min Jin Lee"),

        // Sci-fi / fantasy
        ("Dune", "Frank Herbert"),
        ("The Name of the Wind", "Patrick Rothfuss"),
        ("Project Hail Mary", "Andy Weir"),
        ("The Three-Body Problem", "Liu Cixin"),

        // Mystery / thriller
        ("Gone Girl", "Gillian Flynn"),
        ("The Silent Patient", "Alex Michaelides"),
        ("The Girl with the Dragon Tattoo", "Stieg Larsson"),

        // Non-fiction
        ("Sapiens", "Yuval Noah Harari"),
        ("Educated", "Tara Westover"),
        ("The Body Keeps the Score", "Bessel van der Kolk"),

        // Romance / contemporary fiction
        ("The Seven Husbands of Evelyn Hugo", "Taylor Jenkins Reid"),
        ("Where the Crawdads Sing", "Delia Owens"),

        // Memoir / essay
        ("Just Kids", "Patti Smith"),
        ("Bossypants", "Tina Fey"),
    ]
}
