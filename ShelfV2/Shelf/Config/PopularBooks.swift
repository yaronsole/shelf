import Foundation

// Curated list of widely-recognized books across genres, eras, and cultures.
// Looked up via Open Library (Google Books fallback) on first display of the
// seed-gathering surfaces.
//
// ORDER MATTERS. The For You seed grid shows the first 24 entries, so the top
// of the list is the "front page": modern, broadly recognizable titles that are
// deliberately INTERLEAVED across genres (literary, memoir, history, YA/teen,
// sci-fi, fantasy, romance, thriller, non-fiction, international) instead of
// grouped by genre — otherwise the first screen reads as an all-classics shelf.
// The remainder (deeper cuts + canon classics) follows.
enum PopularBooks {
    static let books: [(title: String, author: String)] = [
        // ── Front 24: modern + genre-diverse (shown in the For You grid) ──
        ("Tomorrow, and Tomorrow, and Tomorrow", "Gabrielle Zevin"),   // literary
        ("Crying in H Mart", "Michelle Zauner"),                       // memoir
        ("Project Hail Mary", "Andy Weir"),                            // sci-fi
        ("The Seven Husbands of Evelyn Hugo", "Taylor Jenkins Reid"),  // book-club fiction
        ("Killers of the Flower Moon", "David Grann"),                 // narrative history / true crime
        ("The Hate U Give", "Angie Thomas"),                           // YA / teen
        ("Lessons in Chemistry", "Bonnie Garmus"),                     // contemporary fiction
        ("Educated", "Tara Westover"),                                 // memoir
        ("Babel", "R. F. Kuang"),                                      // fantasy
        ("The Silent Patient", "Alex Michaelides"),                    // thriller
        ("Sapiens", "Yuval Noah Harari"),                              // big-idea non-fiction
        ("Six of Crows", "Leigh Bardugo"),                             // YA fantasy
        ("Pachinko", "Min Jin Lee"),                                   // historical / international
        ("Normal People", "Sally Rooney"),                            // literary
        ("Atomic Habits", "James Clear"),                              // self-improvement
        ("Where the Crawdads Sing", "Delia Owens"),                    // fiction
        ("The Warmth of Other Suns", "Isabel Wilkerson"),              // history
        ("Beach Read", "Emily Henry"),                                 // romance
        ("The Three-Body Problem", "Liu Cixin"),                       // sci-fi / international
        ("Demon Copperhead", "Barbara Kingsolver"),                    // literary
        ("Born a Crime", "Trevor Noah"),                               // memoir
        ("The Fault in Our Stars", "John Green"),                      // YA / teen
        ("A Little Life", "Hanya Yanagihara"),                         // literary
        ("The Body Keeps the Score", "Bessel van der Kolk"),           // psychology / non-fiction

        // ── Deeper cuts: contemporary & award-winning ──
        ("The Goldfinch", "Donna Tartt"),
        ("The Name of the Wind", "Patrick Rothfuss"),
        ("Gone Girl", "Gillian Flynn"),
        ("The Overstory", "Richard Powers"),
        ("Piranesi", "Susanna Clarke"),
        ("The Sympathizer", "Viet Thanh Nguyen"),
        ("All the Light We Cannot See", "Anthony Doerr"),
        ("The Fifth Season", "N. K. Jemisin"),
        ("Big Little Lies", "Liane Moriarty"),
        ("Red, White & Royal Blue", "Casey McQuiston"),
        ("Trust", "Hernan Diaz"),
        ("The Underground Railroad", "Colson Whitehead"),
        ("The Hunger Games", "Suzanne Collins"),

        // ── International / translated literary fiction ──
        ("Convenience Store Woman", "Sayaka Murata"),
        ("The Vegetarian", "Han Kang"),
        ("Norwegian Wood", "Haruki Murakami"),
        ("My Brilliant Friend", "Elena Ferrante"),
        ("One Hundred Years of Solitude", "Gabriel García Márquez"),
        ("Lincoln in the Bardo", "George Saunders"),

        // ── Non-fiction / memoir / essay ──
        ("Quiet", "Susan Cain"),
        ("Thinking, Fast and Slow", "Daniel Kahneman"),
        ("Just Kids", "Patti Smith"),
        ("Bossypants", "Tina Fey"),
        ("Between the World and Me", "Ta-Nehisi Coates"),
        ("The Year of Magical Thinking", "Joan Didion"),
        ("When Breath Becomes Air", "Paul Kalanithi"),

        // ── Commercial / comedy ──
        ("Eleanor Oliphant Is Completely Fine", "Gail Honeyman"),
        ("Interpreter of Maladies", "Jhumpa Lahiri"),
        ("11/22/63", "Stephen King"),
        ("The Road", "Cormac McCarthy"),

        // ── Sci-fi / fantasy canon ──
        ("Dune", "Frank Herbert"),
        ("The Left Hand of Darkness", "Ursula K. Le Guin"),
        ("The Master and Margarita", "Mikhail Bulgakov"),

        // ── Mystery / thriller ──
        ("The Girl with the Dragon Tattoo", "Stieg Larsson"),
        ("In the Woods", "Tana French"),

        // ── Literary classics (Western canon) ──
        ("The Great Gatsby", "F. Scott Fitzgerald"),
        ("To Kill a Mockingbird", "Harper Lee"),
        ("1984", "George Orwell"),
        ("Pride and Prejudice", "Jane Austen"),
        ("Beloved", "Toni Morrison"),
        ("Slaughterhouse-Five", "Kurt Vonnegut"),
    ]
}
