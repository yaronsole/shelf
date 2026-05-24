import Foundation

// Curated list of widely-recognized books across genres, eras, and cultures.
// Looked up via Google Books on first display of the seed-search screen.
// Aim: roughly balanced across literary fiction, contemporary, sci-fi/fantasy,
// mystery/thriller, non-fiction, memoir, romance, international, and YA.
enum PopularBooks {
    static let books: [(title: String, author: String)] = [
        // Literary classics (Western canon)
        ("The Great Gatsby", "F. Scott Fitzgerald"),
        ("To Kill a Mockingbird", "Harper Lee"),
        ("1984", "George Orwell"),
        ("Pride and Prejudice", "Jane Austen"),
        ("Beloved", "Toni Morrison"),
        ("Slaughterhouse-Five", "Kurt Vonnegut"),

        // International / translated literary fiction
        ("One Hundred Years of Solitude", "Gabriel García Márquez"),
        ("The Master and Margarita", "Mikhail Bulgakov"),
        ("Convenience Store Woman", "Sayaka Murata"),
        ("The Vegetarian", "Han Kang"),
        ("Norwegian Wood", "Haruki Murakami"),
        ("My Brilliant Friend", "Elena Ferrante"),

        // Contemporary literary
        ("The Goldfinch", "Donna Tartt"),
        ("A Little Life", "Hanya Yanagihara"),
        ("Normal People", "Sally Rooney"),
        ("Pachinko", "Min Jin Lee"),
        ("Tomorrow, and Tomorrow, and Tomorrow", "Gabrielle Zevin"),
        ("Demon Copperhead", "Barbara Kingsolver"),
        ("The Overstory", "Richard Powers"),
        ("Lincoln in the Bardo", "George Saunders"),

        // Sci-fi / fantasy
        ("Dune", "Frank Herbert"),
        ("The Name of the Wind", "Patrick Rothfuss"),
        ("Project Hail Mary", "Andy Weir"),
        ("The Three-Body Problem", "Liu Cixin"),
        ("The Left Hand of Darkness", "Ursula K. Le Guin"),
        ("Piranesi", "Susanna Clarke"),
        ("The Fifth Season", "N. K. Jemisin"),
        ("Babel", "R. F. Kuang"),

        // Mystery / thriller
        ("Gone Girl", "Gillian Flynn"),
        ("The Silent Patient", "Alex Michaelides"),
        ("The Girl with the Dragon Tattoo", "Stieg Larsson"),
        ("Big Little Lies", "Liane Moriarty"),
        ("In the Woods", "Tana French"),

        // Romance / contemporary fiction
        ("The Seven Husbands of Evelyn Hugo", "Taylor Jenkins Reid"),
        ("Where the Crawdads Sing", "Delia Owens"),
        ("Beach Read", "Emily Henry"),
        ("Red, White & Royal Blue", "Casey McQuiston"),

        // Non-fiction (popular)
        ("Sapiens", "Yuval Noah Harari"),
        ("Educated", "Tara Westover"),
        ("The Body Keeps the Score", "Bessel van der Kolk"),
        ("Thinking, Fast and Slow", "Daniel Kahneman"),
        ("Atomic Habits", "James Clear"),
        ("Quiet", "Susan Cain"),
        ("Killers of the Flower Moon", "David Grann"),

        // Memoir / essay
        ("Just Kids", "Patti Smith"),
        ("Bossypants", "Tina Fey"),
        ("Crying in H Mart", "Michelle Zauner"),
        ("Between the World and Me", "Ta-Nehisi Coates"),
        ("The Year of Magical Thinking", "Joan Didion"),
        ("When Breath Becomes Air", "Paul Kalanithi"),

        // Award-winning more recent
        ("The Sympathizer", "Viet Thanh Nguyen"),
        ("Trust", "Hernan Diaz"),
        ("The Underground Railroad", "Colson Whitehead"),
        ("All the Light We Cannot See", "Anthony Doerr"),

        // YA crossover
        ("The Hate U Give", "Angie Thomas"),
        ("Six of Crows", "Leigh Bardugo"),

        // Genre staples
        ("11/22/63", "Stephen King"),
        ("The Road", "Cormac McCarthy"),

        // Comedy / commercial
        ("Lessons in Chemistry", "Bonnie Garmus"),
        ("Eleanor Oliphant Is Completely Fine", "Gail Honeyman"),

        // Classic short fiction / poetry
        ("Interpreter of Maladies", "Jhumpa Lahiri"),
    ]
}
