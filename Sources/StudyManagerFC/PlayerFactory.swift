import Foundation

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

enum StableSeed {
    static func value(for text: String, salt: UInt64 = 0) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash ^ (salt &* 0x9E3779B97F4A7C15)
    }
}

struct NamePool {
    let first: [String]
    let last: [String]
}

enum NameDatabase {
    static let pools: [String: NamePool] = [
        "ENG": NamePool(first: ["Harry", "Jude", "Bukayo", "Phil", "Declan", "Marcus", "Cole", "Levi", "Archie", "Ollie", "Kieran", "Reece"], last: ["Bennett", "Walker", "Hayes", "Cole", "Foster", "Hughes", "Mills", "Reed", "Shaw", "Turner", "Palmer", "Whitmore"]),
        "ESP": NamePool(first: ["Mateo", "Sergio", "Pablo", "Álvaro", "Hugo", "Iker", "Marco", "Nico", "Diego", "Adrián", "Unai", "Javier"], last: ["García", "Soler", "Navarro", "Iglesias", "Romero", "Vidal", "Santos", "Molina", "Ortega", "Ramos", "Campos", "Herrera"]),
        "FRA": NamePool(first: ["Théo", "Lucas", "Enzo", "Mathis", "Rayan", "Noah", "Jules", "Amine", "Kylian", "Yanis", "Hugo", "Malo"], last: ["Moreau", "Leroy", "Girard", "Dubois", "Fontaine", "Marchand", "Bakwa", "Diallo", "Rousseau", "Clement", "Vasseur", "Perrin"]),
        "GER": NamePool(first: ["Lukas", "Jonas", "Felix", "Max", "Leon", "Finn", "David", "Karim", "Tim", "Julian", "Noah", "Elias"], last: ["Müller", "Schmidt", "Weber", "Wagner", "Becker", "Hoffmann", "Koch", "Braun", "Brandt", "Keller", "Vogel", "Friedrich"]),
        "ITA": NamePool(first: ["Lorenzo", "Matteo", "Alessandro", "Marco", "Davide", "Nicolò", "Federico", "Giacomo", "Andrea", "Riccardo", "Tommaso", "Simone"], last: ["Rossi", "Bianchi", "Romano", "Esposito", "Conti", "Ricci", "Marino", "Greco", "Lombardi", "Moretti", "Villa", "Ferrari"]),
        "POR": NamePool(first: ["Diogo", "João", "Rúben", "Gonçalo", "Vitinha", "Pedro", "Nuno", "Tiago", "André", "Miguel", "Afonso", "Duarte"], last: ["Silva", "Costa", "Pereira", "Fernandes", "Santos", "Oliveira", "Martins", "Sousa", "Rocha", "Lopes", "Carvalho", "Gomes"]),
        "NED": NamePool(first: ["Sem", "Daan", "Ruben", "Milan", "Jurriën", "Cody", "Xavi", "Wout", "Bram", "Teun", "Kees", "Joris"], last: ["de Jong", "van Dijk", "Bakker", "Visser", "Smit", "Meijer", "de Boer", "van den Berg", "Jansen", "Mulder", "de Wit", "Kok"]),
        "BEL": NamePool(first: ["Arthur", "Lucas", "Thibault", "Amadou", "Jules", "Noah", "Rayan", "Milan", "Loïc", "Senne", "Wout", "Maxim"], last: ["Peeters", "Janssens", "Maes", "Willems", "Mertens", "Claes", "Vandenberg", "Dubois", "Lambert", "De Smet", "Hermans", "Baert"]),
        "UKR": NamePool(first: ["Mykola", "Oleksandr", "Andriy", "Danylo", "Yaroslav", "Vitaliy", "Taras", "Bohdan", "Ivan", "Maksym", "Denys", "Roman"], last: ["Shevchenko", "Kovalenko", "Bondar", "Tkachenko", "Melnyk", "Kravets", "Lysenko", "Savchenko", "Rudenko", "Marchenko", "Boyko", "Zinchenko"]),
        "CRO": NamePool(first: ["Luka", "Mateo", "Ivan", "Marko", "Josip", "Nikola", "Filip", "Petar", "Ante", "Borna", "Mario", "Dario"], last: ["Kovačić", "Petrović", "Đurić", "Marković", "Jurić", "Perić", "Radić", "Vuković", "Babić", "Lovren", "Milić", "Šimić"]),
        "SRB": NamePool(first: ["Luka", "Nikola", "Stefan", "Dušan", "Filip", "Aleksandar", "Nemanja", "Miloš", "Vuk", "Lazar", "Ognjen", "Pavle"], last: ["Jovanović", "Petrović", "Nikolić", "Marković", "Đorđević", "Ilić", "Stojanović", "Pavlović", "Milošević", "Todorović", "Kostić", "Radovanović"]),
        "TUR": NamePool(first: ["Arda", "Kerem", "Hakan", "Cengiz", "Ferdi", "Yusuf", "Emre", "Berkay", "Ozan", "Mert", "Barış", "Kenan"], last: ["Yılmaz", "Kaya", "Demir", "Şahin", "Çelik", "Yıldız", "Aydın", "Öztürk", "Arslan", "Doğan", "Kılıç", "Aslan"]),
        "SCO": NamePool(first: ["Callum", "Scott", "Andrew", "Kieran", "Ryan", "John", "Lewis", "Billy", "Fraser", "Euan", "Greg", "Duncan"], last: ["MacLeod", "Campbell", "Fraser", "McLean", "Murray", "Stewart", "Ross", "Reid", "Ferguson", "Buchanan", "Docherty", "Paterson"]),
        "NOR": NamePool(first: ["Erling", "Martin", "Sander", "Kristian", "Oscar", "Emil", "Antonio", "Fredrik", "Mathias", "Jonas", "Håkon", "Sindre"], last: ["Nilsen", "Hansen", "Johansen", "Larsen", "Andersen", "Pedersen", "Berg", "Solberg", "Nygård", "Møller", "Dahl", "Holm"]),
        "DEN": NamePool(first: ["Mikkel", "Rasmus", "Christian", "Frederik", "Morten", "Emil", "Andreas", "Jonas", "Kasper", "Magnus", "Oliver", "Victor"], last: ["Nielsen", "Jensen", "Hansen", "Pedersen", "Andersen", "Christensen", "Larsen", "Sørensen", "Rasmussen", "Jørgensen", "Madsen", "Kristensen"]),
        "SWE": NamePool(first: ["Viktor", "Alexander", "Emil", "Lucas", "Hugo", "Elias", "Anton", "Gustav", "Filip", "Oscar", "Isak", "Albin"], last: ["Andersson", "Johansson", "Karlsson", "Nilsson", "Eriksson", "Larsson", "Olsson", "Persson", "Svensson", "Gustafsson", "Lindberg", "Bergström"]),
        "BRA": NamePool(first: ["Gabriel", "Lucas", "Matheus", "Vinícius", "Rodrygo", "Bruno", "Thiago", "Caio", "Danilo", "Pedro", "João", "Rafael"], last: ["Silva", "Souza", "Oliveira", "Santos", "Pereira", "Lima", "Carvalho", "Ribeiro", "Almeida", "Costa", "Nascimento", "Moraes"]),
        "ARG": NamePool(first: ["Lautaro", "Julián", "Enzo", "Alejandro", "Nicolás", "Franco", "Valentín", "Matías", "Santiago", "Thiago", "Facundo", "Emiliano"], last: ["Martínez", "Fernández", "González", "Rodríguez", "López", "Díaz", "Álvarez", "Romero", "Suárez", "Torres", "Acosta", "Medina"]),
        "URU": NamePool(first: ["Federico", "Darwin", "Nicolás", "Facundo", "Manuel", "Rodrigo", "Santiago", "Diego", "Maximiliano", "Agustín", "Sebastián", "Lucas"], last: ["Valverde", "Núñez", "Bentancur", "Pellistri", "Ugarte", "Araújo", "Varela", "Giménez", "Olivera", "Rodríguez", "Cavani", "Suárez"]),
        "COL": NamePool(first: ["Luis", "Jhon", "Rafael", "Yerry", "Davinson", "Juan", "Jorge", "Carlos", "Andrés", "Mateo", "Daniel", "Kevin"], last: ["Díaz", "Córdoba", "Santos", "Mina", "Sánchez", "Cuadrado", "Carrascal", "Bacca", "Gómez", "Arias", "Muñoz", "Castillo"]),
        "NGA": NamePool(first: ["Victor", "Ademola", "Samuel", "Alex", "Calvin", "Wilfred", "Taiwo", "Fisayo", "Terem", "Chidera", "Raphael", "Ola"], last: ["Osimhen", "Lookman", "Chukwueze", "Iwobi", "Bassey", "Ndidi", "Awoniyi", "Dele-Bashiru", "Moffi", "Ejuke", "Onyeka", "Aina"]),
        "SEN": NamePool(first: ["Sadio", "Kalidou", "Édouard", "Ismaïla", "Nicolas", "Iliman", "Pape", "Cheikh", "Lamine", "Habib", "Moussa", "Abdou"], last: ["Mané", "Koulibaly", "Mendy", "Sarr", "Jackson", "Ndiaye", "Gueye", "Diatta", "Camara", "Diallo", "Niang", "Ciss"]),
        "MAR": NamePool(first: ["Achraf", "Youssef", "Hakim", "Sofyan", "Nayef", "Azzedine", "Bilal", "Amine", "Ilias", "Ayoub", "Zakaria", "Oussama"], last: ["Hakimi", "En-Nesyri", "Ziyech", "Amrabat", "Aguerd", "Ounahi", "El Khannouss", "Harit", "Chair", "El Kaabi", "Aboukhlal", "Sahraoui"]),
        "GHA": NamePool(first: ["Mohammed", "Thomas", "Antoine", "Jordan", "Daniel", "Elisha", "Kamaldeen", "Ernest", "Fatawu", "Lawrence", "Osman", "Salis"], last: ["Kudus", "Partey", "Semenyo", "Ayew", "Amartey", "Owusu", "Sulemana", "Nuamah", "Issahaku", "Ati-Zigi", "Bukari", "Abdul Samed"]),
        "JPN": NamePool(first: ["Kaoru", "Takefusa", "Daichi", "Ritsu", "Takumi", "Hiroki", "Wataru", "Ao", "Koki", "Yuki", "Sota", "Keito"], last: ["Mitoma", "Kubo", "Kamada", "Doan", "Minamino", "Ito", "Endo", "Tanaka", "Machida", "Sugawara", "Watanabe", "Nakamura"]),
        "KOR": NamePool(first: ["Min-jae", "Heung-min", "Kang-in", "Woo-young", "Hyun-jun", "Jae-sung", "In-beom", "Seung-ho", "Ji-soo", "Dong-gyeong", "Tae-hwan", "Sang-bin"], last: ["Kim", "Son", "Lee", "Jung", "Hwang", "Cho", "Park", "Hong", "Seo", "Moon", "Kang", "Yang"]),
        "USA": NamePool(first: ["Christian", "Weston", "Tyler", "Gio", "Yunus", "Folarin", "Brenden", "Ricardo", "Antonee", "Malik", "Johnny", "Caden"], last: ["Pulisic", "McKennie", "Adams", "Reyna", "Musah", "Balogun", "Aaronson", "Pepi", "Robinson", "Tillman", "Cardoso", "Clark"])
    ]

    static let fallback = NamePool(
        first: ["Leo", "Marco", "Nico", "Alex", "Daniel", "Luca", "Samir", "Jonas", "Andre", "Milan", "Rafael", "Yannick"],
        last: ["Costa", "Silva", "Moreau", "Keller", "Rossi", "Novak", "Hansen", "Petrov", "Almeida", "Fischer", "Lopes", "Mendes"]
    )

    static func pool(for code: String) -> NamePool {
        pools[code] ?? fallback
    }
}

enum PlayerFactory {
    static let starterPositions: [PlayerPosition] = [
        .goalkeeper, .goalkeeper,
        .leftBack, .centerBack, .centerBack, .centerBack, .rightBack,
        .defensiveMid, .centralMid, .centralMid, .attackingMid,
        .leftWing, .leftWing, .striker, .striker, .rightWing,
        .centerBack, .centralMid
    ]

    private static let freeAgentRarities: [PlayerRarity] = [
        .bronze, .bronze, .bronze, .bronze, .bronze, .bronze, .bronze, .bronze,
        .silver, .silver, .silver, .silver, .silver, .silver, .silver, .silver, .silver,
        .gold, .gold, .gold, .gold, .gold, .gold,
        .wonderkid, .wonderkid,
        .icon
    ]

    static func starterSquad(club: Club, season: Int) -> [Player] {
        var generator = SeededGenerator(seed: StableSeed.value(for: "starter-\(club.id)-\(season)"))
        return starterPositions.enumerated().map { index, position in
            let ratingOffset = Int.random(in: -4...3, using: &generator)
            let target = min(94, max(58, club.rating + ratingOffset - (index >= 16 ? 2 : 0)))
            let nationCode = starterNation(for: club, using: &generator)
            return makePlayer(
                targetOverall: target,
                position: position,
                nationCode: nationCode,
                season: season,
                ageRange: index >= 16 ? 18...23 : 20...32,
                forcedRarity: nil,
                using: &generator
            )
        }
    }

    static func aiRoster(club: Club, season: Int) -> [Player] {
        var generator = SeededGenerator(seed: StableSeed.value(for: "ai-\(club.id)-\(season)"))
        let positions: [PlayerPosition] = [
            .goalkeeper, .goalkeeper, .leftBack, .centerBack, .centerBack, .rightBack,
            .defensiveMid, .centralMid, .centralMid, .attackingMid,
            .leftWing, .striker, .striker, .rightWing, .centerBack, .centralMid
        ]
        return positions.enumerated().map { index, position in
            let offset = Int.random(in: -5...3, using: &generator)
            let nationCode = starterNation(for: club, using: &generator)
            return makePlayer(
                targetOverall: min(94, max(55, club.rating + offset - (index >= 14 ? 3 : 0))),
                position: position,
                nationCode: nationCode,
                season: season,
                ageRange: 19...32,
                forcedRarity: nil,
                using: &generator
            )
        }
    }

    static func makeFreeAgentPool(season: Int, count: Int) -> [Player] {
        var generator = SeededGenerator(seed: StableSeed.value(for: "free-agents-\(season)"))
        return (0..<count).map { _ in
            let rarity = freeAgentRarities.randomElement(using: &generator) ?? .silver
            let position = PlayerPosition.allCases.randomElement(using: &generator) ?? .centralMid
            let nation = Nations.all.randomElement()?.code ?? "ENG"
            return makePlayer(
                targetOverall: nil,
                position: position,
                nationCode: nation,
                season: season,
                ageRange: nil,
                forcedRarity: rarity,
                using: &generator
            )
        }
    }

    static func makeYouthProspects(season: Int, count: Int) -> [Player] {
        var generator = SeededGenerator(seed: StableSeed.value(for: "youth-\(season)"))
        return (0..<count).map { _ in
            let position = PlayerPosition.allCases.randomElement(using: &generator) ?? .striker
            let nation = Nations.all.randomElement()?.code ?? "ENG"
            return makePlayer(
                targetOverall: nil,
                position: position,
                nationCode: nation,
                season: season,
                ageRange: 16...18,
                forcedRarity: Bool.random(using: &generator) ? .wonderkid : .gold,
                highPotential: true,
                using: &generator
            )
        }
    }

    /// Prospects promoted straight into the senior squad. They arrive as raw teenagers
    /// with high ceilings rather than ready-made first-team players.
    static func makeAcademyProspects(season: Int, count: Int) -> [Player] {
        var generator = SeededGenerator(seed: StableSeed.value(for: "academy-\(season)"))
        return (0..<count).map { _ in
            let position = PlayerPosition.allCases.randomElement(using: &generator) ?? .centralMid
            let nation = Nations.all.randomElement()?.code ?? "ENG"
            return makePlayer(
                targetOverall: Int.random(in: 58...68, using: &generator),
                position: position,
                nationCode: nation,
                season: season,
                ageRange: 16...18,
                forcedRarity: nil,
                highPotential: true,
                using: &generator
            )
        }
    }

    /// A batch of academy prospects whose quality depends on the academy level. Level 1 intakes
    /// are raw teenagers with little or no potential; level 5 intakes are close to first-team
    /// quality with real ceilings.
    static func makeAcademyIntake(level: Int, season: Int, count: Int) -> [Player] {
        var generator = SeededGenerator(seed: UInt64.random(in: 1...UInt64.max))
        let clampedLevel = min(max(level, 1), GameRules.maxAcademyLevel)
        let mean = 0.15 + Double(clampedLevel - 1) * 0.175
        return (0..<count).map { _ in
            let quality = min(1, max(0, mean + Double.random(in: -0.2...0.2, using: &generator)))
            let overall = 45 + Int((quality * 25).rounded())
            let ceiling = Int((quality * 25 * Double.random(in: 0.2...1.2, using: &generator)).rounded())
            let position = PlayerPosition.allCases.randomElement(using: &generator) ?? .centralMid
            let nation = Nations.all.randomElement(using: &generator)?.code ?? "ENG"
            var player = makePlayer(
                targetOverall: overall,
                position: position,
                nationCode: nation,
                season: season,
                ageRange: 16...18,
                forcedRarity: nil,
                highPotential: false,
                using: &generator
            )
            player.potential = min(99, max(overall, overall + ceiling))
            return player
        }
    }

    static func makePackPlayer(rarity: PlayerRarity, season: Int) -> Player {
        var generator = SeededGenerator(seed: UInt64.random(in: 1...UInt64.max))
        let position = PlayerPosition.allCases.randomElement(using: &generator) ?? .centralMid
        let nation = Nations.all.randomElement()?.code ?? "ENG"
        return makePlayer(
            targetOverall: nil,
            position: position,
            nationCode: nation,
            season: season,
            ageRange: nil,
            forcedRarity: rarity,
            highPotential: rarity == .wonderkid,
            using: &generator
        )
    }

    static func makePlayer(
        targetOverall: Int?,
        position: PlayerPosition,
        nationCode: String,
        season: Int,
        ageRange: ClosedRange<Int>?,
        forcedRarity: PlayerRarity?,
        highPotential: Bool = false,
        using generator: inout SeededGenerator
    ) -> Player {
        let rarity = forcedRarity ?? .silver
        let overall = targetOverall ?? overallRange(for: rarity).randomElement(using: &generator) ?? 70
        let age: Int
        if let ageRange {
            age = Int.random(in: ageRange, using: &generator)
        } else {
            age = Int.random(in: defaultAgeRange(for: rarity), using: &generator)
        }
        let resolvedRarity = skillBasedRarity(overall: overall, age: age, seedRarity: rarity, highPotential: highPotential, generator: &generator)
        let potential = makePotential(overall: overall, age: age, highPotential: highPotential || resolvedRarity == .wonderkid, using: &generator)
        let finalRarity = forcedRarity == nil ? resolvedRarity : rarity
        let name = makeName(nationCode: nationCode, using: &generator)
        let attributes = makeAttributes(overall: overall, position: position, using: &generator)

        return Player(
            id: UUID(),
            name: name,
            nationCode: nationCode,
            position: position,
            age: age,
            overall: overall,
            potential: potential,
            rarity: finalRarity,
            attributes: attributes,
            retirementAge: GameRules.retirementAge,
            joinedSeason: season
        )
    }

    /// The player a transfer listing becomes once signed. Deterministic for a given
    /// club, player and season, so the market can preview potential before a fee is paid.
    static func transferPlayer(from seed: StarterSeed, clubID: String, season: Int) -> Player {
        var generator = SeededGenerator(seed: StableSeed.value(for: "transfer-\(clubID)-\(seed.name)-\(season)"))
        let ageRange: ClosedRange<Int> = seed.rating >= 88 ? 24...30 : seed.rating >= 84 ? 22...29 : 21...28
        let age = Int.random(in: ageRange, using: &generator)
        let rarity: PlayerRarity = seed.rating >= 90 ? .icon : seed.rating >= 86 ? .gold : seed.rating >= 82 ? .silver : .bronze
        let potentialBoost = Int.random(in: 2...6, using: &generator)
        let potential = min(99, seed.rating + potentialBoost)
        let bias = seed.position.attributesBias
        func attr(_ adjustment: Int) -> Int {
            min(99, max(40, seed.rating + adjustment + Int.random(in: -3...4, using: &generator)))
        }
        let attributes = PlayerAttributes(
            pace: attr(bias.pace),
            shooting: attr(bias.shooting),
            passing: attr(bias.passing),
            defending: attr(bias.defending),
            physical: attr(bias.physical)
        )
        return Player(
            id: UUID(),
            name: seed.name,
            nationCode: seed.nationCode,
            position: seed.position,
            age: age,
            overall: seed.rating,
            potential: potential,
            rarity: rarity,
            attributes: attributes,
            retirementAge: GameRules.retirementAge,
            joinedSeason: season
        )
    }

    static func makeName(nationCode: String, using generator: inout SeededGenerator) -> String {
        let pool = NameDatabase.pool(for: nationCode)
        let first = pool.first.randomElement(using: &generator) ?? "Alex"
        let last = pool.last.randomElement(using: &generator) ?? "Silva"
        return "\(first) \(last)"
    }

    static func autoLineup(players: [Player]) -> ([String: UUID], [UUID]) {
        var used = Set<UUID>()
        var lineup: [String: UUID] = [:]

        for slot in LineupSlot.all {
            let candidate = players
                .filter { !used.contains($0.id) }
                .max { lhs, rhs in
                    let left = lhs.adjustedRating(for: slot)
                    let right = rhs.adjustedRating(for: slot)
                    if left == right { return lhs.potential < rhs.potential }
                    return left < right
                }
            if let candidate {
                lineup[slot.id] = candidate.id
                used.insert(candidate.id)
            }
        }

        let bench = players
            .filter { !used.contains($0.id) }
            .sorted { $0.overall > $1.overall }
            .prefix(GameRules.benchLimit)
            .map(\.id)

        return (lineup, Array(bench))
    }

    private static func starterNation(for club: Club, using generator: inout SeededGenerator) -> String {
        if Int.random(in: 0..<100, using: &generator) < 42 {
            return club.countryCode
        }
        return Nations.all.randomElement(using: &generator)?.code ?? club.countryCode
    }

    private static func skillBasedRarity(
        overall: Int,
        age: Int,
        seedRarity: PlayerRarity,
        highPotential: Bool,
        generator: inout SeededGenerator
    ) -> PlayerRarity {
        if highPotential && age <= 20 { return .wonderkid }
        if seedRarity == .wonderkid && age <= 21 { return .wonderkid }
        if overall >= 86 { return .icon }
        if overall >= 78 { return .gold }
        if overall >= 70 { return .silver }
        return .bronze
    }

    private static func overallRange(for rarity: PlayerRarity) -> ClosedRange<Int> {
        switch rarity {
        case .bronze: 58...68
        case .silver: 68...77
        case .gold: 77...85
        case .wonderkid: 66...78
        case .icon: 86...93
        }
    }

    private static func defaultAgeRange(for rarity: PlayerRarity) -> ClosedRange<Int> {
        switch rarity {
        case .bronze: 19...31
        case .silver: 20...32
        case .gold: 21...33
        case .wonderkid: 16...19
        case .icon: 26...34
        }
    }

    private static func makePotential(
        overall: Int,
        age: Int,
        highPotential: Bool,
        using generator: inout SeededGenerator
    ) -> Int {
        min(99, overall + potentialBoost(age: age, highPotential: highPotential, using: &generator))
    }

    /// How far above their overall a player can still grow, chosen by age band. Shared by
    /// generated players and by database rows, which arrive without a potential of their own.
    private static func potentialBoost(
        age: Int,
        highPotential: Bool,
        using generator: inout SeededGenerator
    ) -> Int {
        if highPotential {
            return Int.random(in: 12...22, using: &generator)
        }
        switch age {
        case ...18: return Int.random(in: 10...20, using: &generator)
        case ...21: return Int.random(in: 6...14, using: &generator)
        case ...24: return Int.random(in: 2...8, using: &generator)
        case ...28: return Int.random(in: 0...4, using: &generator)
        default: return Int.random(in: 0...1, using: &generator)
        }
    }

    /// A potential for a database row whose data file carries none. Seeded by the database
    /// id so a player keeps the same ceiling on every launch and in every save.
    static func databasePotential(overall: Int, age: Int, databaseID: Int) -> Int {
        var generator = SeededGenerator(seed: StableSeed.value(for: "fc-pot-\(databaseID)"))
        return min(99, overall + potentialBoost(age: age, highPotential: false, using: &generator))
    }

    private static func makeAttributes(
        overall: Int,
        position: PlayerPosition,
        using generator: inout SeededGenerator
    ) -> PlayerAttributes {
        let bias = position.attributesBias
        func attribute(_ adjustment: Int) -> Int {
            min(99, max(25, overall + adjustment + Int.random(in: -5...5, using: &generator)))
        }
        return PlayerAttributes(
            pace: attribute(bias.pace),
            shooting: attribute(bias.shooting),
            passing: attribute(bias.passing),
            defending: attribute(bias.defending),
            physical: attribute(bias.physical)
        )
    }
}

extension PlayerFactory {
    /// A player's identity is derived from their database id, so the same person has the
    /// same id on every launch and a signed player keeps their identity in the save.
    static func stableID(forDatabaseID dbID: Int) -> UUID {
        var generator = SeededGenerator(seed: StableSeed.value(for: "fc-player-\(dbID)"))
        let high = generator.next()
        let low = generator.next()
        let hex = String(format: "%016llx%016llx", high, low)
        let groups = [hex.prefix(8), hex.dropFirst(8).prefix(4), hex.dropFirst(12).prefix(4), hex.dropFirst(16).prefix(4), hex.dropFirst(20)]
        let uuid = UUID(uuidString: groups.map(String.init).joined(separator: "-")) ?? UUID()
        return uuid
    }

    /// Turns a database row into a live player. Overall, age, position and nationality are
    /// the game's own values, and potential comes from `FcPlayer.potential`, which derives a
    /// ceiling when the data file has none; attributes are derived from the overall rating
    /// with the same positional bias the rest of the app uses.
    static func player(from record: FcPlayer, name: String, season: Int) -> Player {
        var generator = SeededGenerator(seed: StableSeed.value(for: "fc-attrs-\(record.id)"))
        let attributes = makeAttributes(overall: record.ovr, position: record.position, using: &generator)
        return Player(
            id: stableID(forDatabaseID: record.id),
            name: name,
            nationCode: record.nat,
            position: record.position,
            age: record.age,
            overall: record.ovr,
            potential: record.potential,
            rarity: record.rarity,
            attributes: attributes,
            retirementAge: GameRules.retirementAge,
            joinedSeason: season,
            dbID: record.id,
            clubID: record.club
        )
    }

    /// The squad a club starts with, taken straight from the game database. Empty when
    /// the database has no players for that club, so the caller can fall back.
    static func databaseSquad(for clubID: String, season: Int, limit: Int = 24) -> [Player] {
        let database = FcDatabase.shared
        // Map the app's club ID to the database's club ID, then get the club name
        var dbClubID = clubID
        if clubID == "barcelona" { dbClubID = "fc-barcelona" }
        let club = database.club(dbClubID)
        let clubName = club?.name ?? clubID
        let records = database.squadPlayers(for: clubName, limit: limit)
        guard !records.isEmpty else { return [] }
        return records.map { record in
            let name = record.disambiguatedName(in: records, database: database)
            return player(from: record, name: name, season: season)
        }
    }
}
