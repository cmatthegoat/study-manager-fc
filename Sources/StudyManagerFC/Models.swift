import Foundation

enum GameRules {
    static let clubCashPerMinute = 10
    static let xpPerMinute = 6
    static let minutesPerMatch = 90
    static let startingCash = 600
    /// Club Cash paid for ticking off a todo, before the subject's cash multiplier.
    static let clubCashPerTodo = 100
    static let benchLimit = 7
    static let xpPerLevel = 750
    /// Club Cash paid to each player for every level gained.
    static let clubCashPerLevelUp = 500
    /// Chance that a qualifying study session, extra session or match brings a transfer offer.
    static let transferOfferChance = 0.25
    static let freeAgentPoolTarget = 84
    static let retirementAge = 40
    static let academyIntakePerSeason = 3
    /// Competitive matches between each batch of academy prospects.
    static let matchesPerAcademyIntake = 5
    static let maxAcademyLevel = 5
    /// Exams earn this multiplier on top of the subject multiplier.
    static let examRewardMultiplier = 2.0
    /// Base cash and XP for an assessment ranked 1st in its class. Lower places pay less.
    static let assessmentBaseCash = 400
    static let assessmentBaseXP = 300
    /// Each place below 1st takes this share off the base reward, down to a floor.
    static let assessmentRankStep = 0.1
    static let assessmentRankFloor = 0.2

    /// Reward for an assessment's class rank (1 = best). Marks and overall rank never count.
    static func assessmentRankFactor(classRank: Int?) -> Double {
        guard let classRank, classRank >= 1 else { return 0 }
        return max(assessmentRankFloor, 1.0 - Double(classRank - 1) * assessmentRankStep)
    }
    /// Club Cash needed to move the academy from `level` to `level + 1`.
    static func academyUpgradeCost(from level: Int) -> Int? {
        let costs = [1_500, 3_000, 6_000, 12_000]
        guard level >= 1, level <= costs.count else { return nil }
        return costs[level - 1]
    }
}

enum PositionGroup: String, Codable, CaseIterable, Identifiable {
    case goalkeeper
    case defence
    case midfield
    case attack

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .goalkeeper: "GK"
        case .defence: "DEF"
        case .midfield: "MID"
        case .attack: "ATT"
        }
    }

    var displayName: String {
        switch self {
        case .goalkeeper: "Goalkeeper"
        case .defence: "Defence"
        case .midfield: "Midfield"
        case .attack: "Attack"
        }
    }
}

enum PlayerPosition: String, Codable, CaseIterable, Identifiable, Hashable {
    case goalkeeper
    case leftBack
    case centerBack
    case rightBack
    case defensiveMid
    case centralMid
    case attackingMid
    case leftWing
    case striker
    case rightWing

    var id: String { rawValue }

    var abbreviation: String {
        switch self {
        case .goalkeeper: "GK"
        case .leftBack: "LB"
        case .centerBack: "CB"
        case .rightBack: "RB"
        case .defensiveMid: "CDM"
        case .centralMid: "CM"
        case .attackingMid: "CAM"
        case .leftWing: "LW"
        case .striker: "ST"
        case .rightWing: "RW"
        }
    }

    var displayName: String {
        switch self {
        case .goalkeeper: "Goalkeeper"
        case .leftBack: "Left Back"
        case .centerBack: "Centre Back"
        case .rightBack: "Right Back"
        case .defensiveMid: "Defensive Midfielder"
        case .centralMid: "Central Midfielder"
        case .attackingMid: "Attacking Midfielder"
        case .leftWing: "Left Winger"
        case .striker: "Striker"
        case .rightWing: "Right Winger"
        }
    }

    var group: PositionGroup {
        switch self {
        case .goalkeeper: .goalkeeper
        case .leftBack, .centerBack, .rightBack: .defence
        case .defensiveMid, .centralMid, .attackingMid: .midfield
        case .leftWing, .striker, .rightWing: .attack
        }
    }

    var scoringWeight: Double {
        switch self {
        case .goalkeeper: 0.02
        case .leftBack, .rightBack: 0.45
        case .centerBack: 0.35
        case .defensiveMid: 0.7
        case .centralMid: 1.8
        case .attackingMid: 3.2
        case .leftWing, .rightWing: 4.4
        case .striker: 7.0
        }
    }

    var attributesBias: (pace: Int, shooting: Int, passing: Int, defending: Int, physical: Int) {
        switch self {
        case .goalkeeper: (-6, -18, -2, 10, 7)
        case .leftBack, .rightBack: (8, -8, 2, 3, 0)
        case .centerBack: (-4, -14, -4, 12, 9)
        case .defensiveMid: (-4, -8, 5, 8, 5)
        case .centralMid: (0, 0, 10, 0, 0)
        case .attackingMid: (3, 4, 8, -10, -4)
        case .leftWing, .rightWing: (10, 4, 1, -12, -6)
        case .striker: (6, 12, -6, -14, 2)
        }
    }
}

enum PlayerRarity: String, Codable, CaseIterable, Identifiable, Hashable, Comparable {
    case bronze
    case silver
    case gold
    case wonderkid
    case icon

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .wonderkid: "Wonderkid"
        case .icon: "Icon"
        }
    }

    var sortOrder: Int {
        switch self {
        case .bronze: 0
        case .silver: 1
        case .gold: 2
        case .wonderkid: 3
        case .icon: 4
        }
    }

    static func < (lhs: PlayerRarity, rhs: PlayerRarity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

struct PlayerAttributes: Codable, Hashable {
    var pace: Int
    var shooting: Int
    var passing: Int
    var defending: Int
    var physical: Int
}

enum PlayerPricing {
    /// A player's price is driven by overall rating: every extra point of overall is
    /// worth roughly 16% more than the one below it. Elite players therefore cost an
    /// order of magnitude more than solid squad options.
    static let baselineOverall = 60
    static let baselineFee = 250
    static let growthPerOverall = 1.16

    static func fee(forOverall overall: Int) -> Int {
        let steps = Double(max(0, overall - baselineOverall))
        return Int((Double(baselineFee) * pow(growthPerOverall, steps)).rounded())
    }
}

struct Player: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var nationCode: String
    var position: PlayerPosition
    var age: Int
    var overall: Int
    var potential: Int
    var rarity: PlayerRarity
    var attributes: PlayerAttributes
    var retirementAge: Int
    var joinedSeason: Int
    /// The row in the game database this player came from. Nil for generated players
    /// (academy prospects, free agents and careers started before the database import).
    var dbID: Int? = nil
    /// The club that owns this player in the database. Nil once they play for you.
    var clubID: String? = nil
    /// Whether this player is listed on the user's transfer market (set when listPlayer is called)
    var isUserListing: Bool = false
    /// Asking price in Club Cash when listed (nil = AI will make automatic offers)
    var listingPrice: Int? = nil
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nationCode
        case position
        case age
        case overall
        case potential
        case rarity
        case attributes
        case retirementAge
        case joinedSeason
        case dbID
        case clubID
        case isUserListing
        case listingPrice
        case isInjured
        case matchesMissed
    }
    /// True if the player is currently injured and cannot play.
    var isInjured: Bool = false
    /// Number of matches this player must miss due to injury (0 = fully recovered).
    var matchesMissed: Int = 0

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var nation: Nation {
        Nations.nation(for: nationCode)
    }

    var marketValue: Int {
        PlayerPricing.fee(forOverall: overall)
    }

    var releaseValue: Int {
        switch rarity {
        case .bronze: max(20, overall * 2)
        case .silver: max(60, overall * 3)
        case .gold: max(150, overall * 5)
        case .wonderkid: max(250, overall * 6)
        case .icon: max(600, overall * 11)
        }
    }

    func fitScore(for slot: LineupSlot) -> Int {
        if position == slot.position { return 2 }
        if position.group == slot.position.group { return 1 }
        return 0
    }

    func adjustedRating(for slot: LineupSlot) -> Int {
        switch fitScore(for: slot) {
        case 2: overall
        case 1: overall - 2
        default: overall - 7
        }
    }
}

struct Nation: Identifiable, Hashable {
    let code: String
    let name: String
    let flag: String

    var id: String { code }
}

enum Nations {
    static let all: [Nation] = [
        Nation(code: "ENG", name: "England", flag: "🏴󠁧󠁢󠁥󠁮󠁧󠁿"),
        Nation(code: "ESP", name: "Spain", flag: "🇪🇸"),
        Nation(code: "FRA", name: "France", flag: "🇫🇷"),
        Nation(code: "GER", name: "Germany", flag: "🇩🇪"),
        Nation(code: "ITA", name: "Italy", flag: "🇮🇹"),
        Nation(code: "POR", name: "Portugal", flag: "🇵🇹"),
        Nation(code: "NED", name: "Netherlands", flag: "🇳🇱"),
        Nation(code: "BEL", name: "Belgium", flag: "🇧🇪"),
        Nation(code: "UKR", name: "Ukraine", flag: "🇺🇦"),
        Nation(code: "CRO", name: "Croatia", flag: "🇭🇷"),
        Nation(code: "SRB", name: "Serbia", flag: "🇷🇸"),
        Nation(code: "TUR", name: "Türkiye", flag: "🇹🇷"),
        Nation(code: "SCO", name: "Scotland", flag: "🏴󠁧󠁢󠁳󠁣󠁴󠁿"),
        Nation(code: "NOR", name: "Norway", flag: "🇳🇴"),
        Nation(code: "DEN", name: "Denmark", flag: "🇩🇰"),
        Nation(code: "SWE", name: "Sweden", flag: "🇸🇪"),
        Nation(code: "BRA", name: "Brazil", flag: "🇧🇷"),
        Nation(code: "ARG", name: "Argentina", flag: "🇦🇷"),
        Nation(code: "URU", name: "Uruguay", flag: "🇺🇾"),
        Nation(code: "COL", name: "Colombia", flag: "🇨🇴"),
        Nation(code: "NGA", name: "Nigeria", flag: "🇳🇬"),
        Nation(code: "SEN", name: "Senegal", flag: "🇸🇳"),
        Nation(code: "MAR", name: "Morocco", flag: "🇲🇦"),
        Nation(code: "GHA", name: "Ghana", flag: "🇬🇭"),
        Nation(code: "JPN", name: "Japan", flag: "🇯🇵"),
        Nation(code: "KOR", name: "South Korea", flag: "🇰🇷"),
        Nation(code: "USA", name: "United States", flag: "🇺🇸")
    ]

    static func nation(for code: String) -> Nation {
        if let known = all.first(where: { $0.code == code }) { return known }
        if let imported = FcDatabase.shared.nation(code: code) {
            return Nation(code: imported.code, name: imported.name, flag: imported.flag)
        }
        return Nation(code: code, name: code, flag: "🏳️")
    }
}

struct Club: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let shortName: String
    let code: String
    let countryCode: String
    let primaryHex: String
    let secondaryHex: String
    let rating: Int

    var country: String {
        Nations.nation(for: countryCode).name
    }
}

enum ClubDatabase {
    static let all: [Club] = [
        Club(id: "real-madrid", name: "Real Madrid", shortName: "Real Madrid", code: "RMA", countryCode: "ESP", primaryHex: "F5F5F5", secondaryHex: "D4AF37", rating: rating(for: "real-madrid")),
        Club(id: "manchester-city", name: "Manchester City", shortName: "Man City", code: "MCI", countryCode: "ENG", primaryHex: "6CABDD", secondaryHex: "1C2C5B", rating: rating(for: "manchester-city")),
        Club(id: "barcelona", name: "FC Barcelona", shortName: "Barcelona", code: "BAR", countryCode: "ESP", primaryHex: "A50044", secondaryHex: "004D98", rating: rating(for: "barcelona")),
        Club(id: "bayern-munich", name: "Bayern Munich", shortName: "Bayern", code: "FCB", countryCode: "GER", primaryHex: "DC052D", secondaryHex: "FFFFFF", rating: rating(for: "bayern-munich")),
        Club(id: "liverpool", name: "Liverpool FC", shortName: "Liverpool", code: "LIV", countryCode: "ENG", primaryHex: "C8102E", secondaryHex: "00B2A9", rating: rating(for: "liverpool")),
        Club(id: "arsenal", name: "Arsenal", shortName: "Arsenal", code: "ARS", countryCode: "ENG", primaryHex: "EF0107", secondaryHex: "063672", rating: rating(for: "arsenal")),
        Club(id: "inter-milan", name: "Inter Milan", shortName: "Inter", code: "INT", countryCode: "ITA", primaryHex: "0068A8", secondaryHex: "111111", rating: rating(for: "inter-milan")),
        Club(id: "paris-saint-germain", name: "Paris Saint-Germain", shortName: "PSG", code: "PSG", countryCode: "FRA", primaryHex: "004170", secondaryHex: "DA291C", rating: rating(for: "paris-saint-germain")),
        Club(id: "atletico-madrid", name: "Atlético Madrid", shortName: "Atlético", code: "ATM", countryCode: "ESP", primaryHex: "CB3524", secondaryHex: "272E61", rating: rating(for: "atletico-madrid")),
        Club(id: "ac-milan", name: "AC Milan", shortName: "Milan", code: "MIL", countryCode: "ITA", primaryHex: "FB090B", secondaryHex: "111111", rating: rating(for: "ac-milan")),
        Club(id: "borussia-dortmund", name: "Borussia Dortmund", shortName: "Dortmund", code: "BVB", countryCode: "GER", primaryHex: "FDE100", secondaryHex: "111111", rating: rating(for: "borussia-dortmund")),
        Club(id: "manchester-united", name: "Manchester United", shortName: "Man United", code: "MUN", countryCode: "ENG", primaryHex: "DA291C", secondaryHex: "FBE122", rating: rating(for: "manchester-united")),
        Club(id: "chelsea", name: "Chelsea FC", shortName: "Chelsea", code: "CHE", countryCode: "ENG", primaryHex: "034694", secondaryHex: "FFFFFF", rating: rating(for: "chelsea")),
        Club(id: "juventus", name: "Juventus", shortName: "Juventus", code: "JUV", countryCode: "ITA", primaryHex: "F5F5F5", secondaryHex: "111111", rating: rating(for: "juventus")),
        Club(id: "napoli", name: "SSC Napoli", shortName: "Napoli", code: "NAP", countryCode: "ITA", primaryHex: "12A0D7", secondaryHex: "FFFFFF", rating: rating(for: "napoli")),
        Club(id: "benfica", name: "SL Benfica", shortName: "Benfica", code: "SLB", countryCode: "POR", primaryHex: "E30613", secondaryHex: "FFFFFF", rating: rating(for: "benfica")),
        Club(id: "porto", name: "FC Porto", shortName: "Porto", code: "POR", countryCode: "POR", primaryHex: "00428C", secondaryHex: "FFFFFF", rating: rating(for: "porto")),
        Club(id: "sporting-cp", name: "Sporting CP", shortName: "Sporting", code: "SCP", countryCode: "POR", primaryHex: "008057", secondaryHex: "FFFFFF", rating: rating(for: "sporting-cp")),
        Club(id: "ajax", name: "Ajax", shortName: "Ajax", code: "AJA", countryCode: "NED", primaryHex: "D2122E", secondaryHex: "FFFFFF", rating: rating(for: "ajax")),
        Club(id: "bayer-leverkusen", name: "Bayer Leverkusen", shortName: "Leverkusen", code: "B04", countryCode: "GER", primaryHex: "E32221", secondaryHex: "111111", rating: rating(for: "bayer-leverkusen")),
        Club(id: "roma", name: "AS Roma", shortName: "Roma", code: "ROM", countryCode: "ITA", primaryHex: "8E1F2F", secondaryHex: "F0BC42", rating: rating(for: "roma")),
        Club(id: "tottenham", name: "Tottenham Hotspur", shortName: "Tottenham", code: "TOT", countryCode: "ENG", primaryHex: "132257", secondaryHex: "FFFFFF", rating: rating(for: "tottenham")),
        Club(id: "aston-villa", name: "Aston Villa", shortName: "Villa", code: "AVL", countryCode: "ENG", primaryHex: "670E36", secondaryHex: "95BFE5", rating: rating(for: "aston-villa")),
        Club(id: "marseille", name: "Olympique de Marseille", shortName: "Marseille", code: "OM", countryCode: "FRA", primaryHex: "2FAEE0", secondaryHex: "FFFFFF", rating: rating(for: "marseille")),
        Club(id: "newcastle", name: "Newcastle United", shortName: "Newcastle", code: "NEW", countryCode: "ENG", primaryHex: "241F20", secondaryHex: "FFFFFF", rating: rating(for: "newcastle")),
        Club(id: "lazio", name: "Lazio", shortName: "Lazio", code: "LAZ", countryCode: "ITA", primaryHex: "87D8F7", secondaryHex: "FFFFFF", rating: rating(for: "lazio")),
        Club(id: "lyon", name: "Olympique Lyonnais", shortName: "Lyon", code: "OL", countryCode: "FRA", primaryHex: "14387F", secondaryHex: "DA291C", rating: rating(for: "lyon")),
        Club(id: "psv", name: "PSV Eindhoven", shortName: "PSV", code: "PSV", countryCode: "NED", primaryHex: "ED1C24", secondaryHex: "FFFFFF", rating: rating(for: "psv")),
        Club(id: "fenerbahce", name: "Fenerbahçe", shortName: "Fenerbahçe", code: "FEN", countryCode: "TUR", primaryHex: "FFED00", secondaryHex: "0A1A4F", rating: rating(for: "fenerbahce")),
        Club(id: "feyenoord", name: "Feyenoord", shortName: "Feyenoord", code: "FEY", countryCode: "NED", primaryHex: "E21E25", secondaryHex: "FFFFFF", rating: rating(for: "feyenoord")),
        Club(id: "fiorentina", name: "Fiorentina", shortName: "Fiorentina", code: "FIO", countryCode: "ITA", primaryHex: "482E92", secondaryHex: "FFFFFF", rating: rating(for: "fiorentina")),
        Club(id: "galatasaray", name: "Galatasaray", shortName: "Galatasaray", code: "GAL", countryCode: "TUR", primaryHex: "F5A623", secondaryHex: "A90432", rating: rating(for: "galatasaray")),
        Club(id: "celtic", name: "Celtic FC", shortName: "Celtic", code: "CEL", countryCode: "SCO", primaryHex: "018749", secondaryHex: "FFFFFF", rating: rating(for: "celtic")),
        Club(id: "rangers", name: "Rangers FC", shortName: "Rangers", code: "RAN", countryCode: "SCO", primaryHex: "1B458F", secondaryHex: "FFFFFF", rating: rating(for: "rangers")),
        Club(id: "red-star-belgrade", name: "Red Star Belgrade", shortName: "Red Star", code: "CRV", countryCode: "SRB", primaryHex: "D71920", secondaryHex: "FFFFFF", rating: rating(for: "red-star-belgrade")),
        Club(id: "shakhtar-donetsk", name: "Shakhtar Donetsk", shortName: "Shakhtar", code: "SHK", countryCode: "UKR", primaryHex: "F26522", secondaryHex: "111111", rating: rating(for: "shakhtar-donetsk"))
    ]

    /// Ratings come from the imported game database when it is available, so the
    /// competition is seeded on the same numbers the squads are built from.
    static func rating(for id: String) -> Int {
        if let club = FcDatabase.shared.club(id), club.rating > 0 {
            return club.rating
        }
        return ClubSquads.roundedRating(for: id)
    }

    static func club(for id: String?) -> Club? {
        guard let id else { return nil }
        return all.first(where: { $0.id == id })
    }

    static var seededPots: [[Club]] {
        let sorted = all.sorted {
            if $0.rating == $1.rating { return $0.name < $1.name }
            return $0.rating > $1.rating
        }
        return stride(from: 0, to: sorted.count, by: 9).map {
            Array(sorted[$0..<min($0 + 9, sorted.count)])
        }
    }

    static func potNumber(for clubID: String) -> Int {
        for (index, pot) in seededPots.enumerated() {
            if pot.contains(where: { $0.id == clubID }) { return index + 1 }
        }
        return 4
    }
}

struct LineupSlot: Identifiable, Hashable {
    let id: String
    let label: String
    let position: PlayerPosition
    let x: Double
    let y: Double

    static let all: [LineupSlot] = [
        LineupSlot(id: "gk", label: "GK", position: .goalkeeper, x: 0.50, y: 0.91),
        LineupSlot(id: "lb", label: "LB", position: .leftBack, x: 0.13, y: 0.73),
        LineupSlot(id: "cb1", label: "CB", position: .centerBack, x: 0.37, y: 0.78),
        LineupSlot(id: "cb2", label: "CB", position: .centerBack, x: 0.63, y: 0.78),
        LineupSlot(id: "rb", label: "RB", position: .rightBack, x: 0.87, y: 0.73),
        LineupSlot(id: "cdm", label: "CDM", position: .defensiveMid, x: 0.50, y: 0.59),
        LineupSlot(id: "cm", label: "CM", position: .centralMid, x: 0.24, y: 0.49),
        LineupSlot(id: "cam", label: "CAM", position: .attackingMid, x: 0.76, y: 0.49),
        LineupSlot(id: "lw", label: "LW", position: .leftWing, x: 0.16, y: 0.26),
        LineupSlot(id: "st", label: "ST", position: .striker, x: 0.50, y: 0.18),
        LineupSlot(id: "rw", label: "RW", position: .rightWing, x: 0.84, y: 0.26)
    ]

    static func slot(for id: String) -> LineupSlot? {
        all.first(where: { $0.id == id })
    }
}

struct SquadMetrics {
    var overall: Int
    var chemistry: Int
    var attack: Int
    var midfield: Int
    var defence: Int
    var totalValue: Int
    var playerCount: Int

    static let empty = SquadMetrics(overall: 0, chemistry: 0, attack: 0, midfield: 0, defence: 0, totalValue: 0, playerCount: 0)

    static func calculate(lineup: [String: UUID], players: [Player]) -> SquadMetrics {
        let playerMap = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        var ratings: [Int] = []
        var chemistryPoints = 0
        var nations: [String: Int] = [:]
        var attack: [Int] = []
        var midfield: [Int] = []
        var defence: [Int] = []

        for slot in LineupSlot.all {
            guard let playerID = lineup[slot.id], let player = playerMap[playerID] else { continue }
            ratings.append(player.adjustedRating(for: slot))
            chemistryPoints += player.fitScore(for: slot)
            nations[player.nationCode, default: 0] += 1
            switch slot.position.group {
            case .goalkeeper, .defence:
                defence.append(player.adjustedRating(for: slot))
            case .midfield:
                midfield.append(player.adjustedRating(for: slot))
            case .attack:
                attack.append(player.adjustedRating(for: slot))
            }
        }

        guard !ratings.isEmpty else { return .empty }

        let sameNationLinks = nations.values.reduce(0) { partial, count in
            partial + max(0, count - 1)
        }
        let positionChemistry = Double(chemistryPoints) / Double(LineupSlot.all.count * 2) * 70.0
        let nationChemistry = min(30.0, Double(sameNationLinks) * 3.5)
        let chemistry = Int((positionChemistry + nationChemistry).rounded())
        let baseOverall = Double(ratings.reduce(0, +)) / Double(ratings.count)
        let missingPenalty = Double(LineupSlot.all.count - ratings.count) * 2.5
        // Overall is the raw quality of the XI only; chemistry never inflates the rating
        // used to simulate a match.
        let overall = Int((baseOverall - missingPenalty).rounded())

        func lineRating(_ values: [Int], fallback: Int) -> Int {
            guard !values.isEmpty else { return fallback }
            return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        }

        return SquadMetrics(
            overall: max(0, overall),
            chemistry: chemistry,
            attack: lineRating(attack, fallback: overall - 3),
            midfield: lineRating(midfield, fallback: overall - 3),
            defence: lineRating(defence, fallback: overall - 3),
            totalValue: players.reduce(0) { $0 + $1.marketValue },
            playerCount: players.count
        )
    }
}

enum StudyActivityKind: String, Codable, CaseIterable, Identifiable {
    case homework
    case pastPaper
    case examQuestions
    case focusSession

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homework: "Homework"
        case .pastPaper: "Past Paper"
        case .examQuestions: "Exam Questions"
        case .focusSession: "Focus Session"
        }
    }

    var unitTitle: String {
        switch self {
        case .homework: "Assignments"
        case .pastPaper: "Papers"
        case .examQuestions: "Questions"
        case .focusSession: "Minutes"
        }
    }

    var systemImage: String {
        switch self {
        case .homework: "book.closed"
        case .pastPaper: "doc.text"
        case .examQuestions: "pencil.and.list.clipboard"
        case .focusSession: "timer"
        }
    }

    var supportsMarking: Bool {
        switch self {
        case .homework, .pastPaper, .examQuestions: true
        case .focusSession: false
        }
    }

    /// How much a session of this kind is worth compared with homework. Past papers are
    /// the closest thing to the real exam, exam-style questions come next, and homework
    /// is the baseline.
    var rewardMultiplier: Double {
        switch self {
        case .pastPaper: 1.5
        case .examQuestions: 1.25
        case .homework, .focusSession: 1.0
        }
    }
}

enum StudySubject: String, Codable, CaseIterable, Identifiable {
    case ext2Maths
    case ext1Maths
    case physics
    case chemistry
    case softwareEngineering
    case englishAdvanced
    case other

    var id: String { rawValue }

    /// Saves written before Business Studies was removed still record that subject.
    /// Unknown or retired subjects decode as `.other` so old careers keep loading
    /// instead of failing the whole save.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StudySubject(rawValue: raw) ?? .other
    }

    var displayName: String {
        switch self {
        case .ext2Maths: "Mathematics Extension 2"
        case .ext1Maths: "Mathematics Extension 1"
        case .physics: "Physics"
        case .chemistry: "Chemistry"
        case .softwareEngineering: "Software Engineering"
        case .englishAdvanced: "English Advanced"
        case .other: "Other"
        }
    }

    var shortName: String {
        switch self {
        case .ext2Maths: "Ext 2 Maths"
        case .ext1Maths: "Ext 1 Maths"
        case .physics: "Physics"
        case .chemistry: "Chemistry"
        case .softwareEngineering: "Software Eng"
        case .englishAdvanced: "English Adv"
        case .other: "Other"
        }
    }

    var cashMultiplier: Double {
        switch self {
        case .ext2Maths: 1.5
        case .ext1Maths: 1.25
        case .physics: 1.25
        case .chemistry: 1.25
        case .englishAdvanced: 2.2
        case .softwareEngineering: 1.1
        case .other: 1.0
        }
    }

    var xpMultiplier: Double {
        switch self {
        case .ext2Maths: 1.4
        case .ext1Maths: 1.2
        case .physics: 1.2
        case .chemistry: 1.2
        case .englishAdvanced: 1.8
        case .softwareEngineering: 1.1
        case .other: 1.0
        }
    }
}

/// A module, topic or unit inside a subject, such as "Complex Numbers" for Ext 2 Maths.
/// Subtopics are created by the player, so the app never assumes a syllabus.
struct Subtopic: Identifiable, Codable, Hashable {
    var id: UUID
    var subject: StudySubject
    var name: String
    var createdAt: Date
}

struct StudySession: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var kind: StudyActivityKind
    var title: String
    var minutes: Int
    var cashEarned: Int
    var xpEarned: Int
    var quantity: Int
    var subject: StudySubject?
    var marksObtained: Int?
    var marksTotal: Int?
    /// Identifies the subtopic this work belonged to, if any.
    var subtopicID: UUID? = nil
    /// The subtopic name is stored alongside the id so history survives deleting it.
    var subtopicName: String? = nil

    var percentage: Int? {
        guard let marksObtained, let marksTotal, marksTotal > 0 else { return nil }
        return Int((Double(marksObtained) / Double(marksTotal) * 100).rounded())
    }

    var markFraction: String? {
        guard let marksObtained, let marksTotal else { return nil }
        return "\(marksObtained)/\(marksTotal)"
    }
}

/// A task that can be organized into a subject and subtopic, similar to StudySession
/// but for general to-do items outside of study tracking.
struct TodoItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var subject: StudySubject?
    var subtopicID: UUID?
    var subtopicName: String?
    var isCompleted: Bool
    var createdAt: Date
    var dueDate: Date?
    /// Set once the completion reward has been paid, so ticking a task off again
    /// cannot farm Club Cash.
    var rewardAwarded: Bool = false
    /// 1 (most urgent) through 4, or nil when the task has no priority marker.
    var priority: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subject
        case subtopicID
        case subtopicName
        case isCompleted
        case createdAt
        case dueDate
        case rewardAwarded
        case priority
    }
}

extension TodoItem {
    /// Decoded by hand so todos written before completion rewards existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subject = try container.decodeIfPresent(StudySubject.self, forKey: .subject)
        subtopicID = try container.decodeIfPresent(UUID.self, forKey: .subtopicID)
        subtopicName = try container.decodeIfPresent(String.self, forKey: .subtopicName)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        rewardAwarded = try container.decodeIfPresent(Bool.self, forKey: .rewardAwarded) ?? false
        let savedPriority = try container.decodeIfPresent(Int.self, forKey: .priority)
        priority = savedPriority.flatMap { (1...4).contains($0) ? $0 : nil }
    }
}

/// A todo typed with inline directives, such as
/// `p1 #Ext 2 Maths - Complex Numbers: finish exercise 4.2`.
/// The title keeps the words the player typed; subject, topic and priority are
/// pulled out of the text so a single field can file the task.
struct TodoInput {
    var title: String
    var subject: StudySubject?
    var subtopicName: String?
    var priority: Int?

    private static let topicSeparators: Set<Character> = ["-", "–", "—", "|"]

    static func parse(_ raw: String, subtopics: [Subtopic] = []) -> TodoInput {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return TodoInput(title: "", subject: nil, subtopicName: nil, priority: nil) }

        var input = TodoInput(title: text, subject: nil, subtopicName: nil, priority: detectPriority(in: text))
        guard let hash = text.firstIndex(of: "#") else { return input }
        let afterHash = text.index(after: hash)
        guard let match = StudySubject.tagMatch(in: text[afterHash...]) else { return input }

        input.subject = match.subject
        let prefix = text[..<hash].trimmingCharacters(in: .whitespaces)
        var rest = String(text[text.index(afterHash, offsetBy: match.consumed)...])
            .trimmingCharacters(in: .whitespaces)

        if rest.hasPrefix(":") {
            // `#Physics: draw a ray diagram` files the subject and keeps the rest as the task.
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else if let first = rest.first, topicSeparators.contains(first) {
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty {
                let (topic, taskText) = splitTopic(from: rest, subject: match.subject, subtopics: subtopics)
                input.subtopicName = topic
                rest = taskText
            }
        }

        var title = [prefix, rest]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if title.isEmpty { title = input.subtopicName ?? "" }
        if title.isEmpty { title = text.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) }
        // The marker has been read as a priority, so it does not clutter the task name.
        let cleaned = strippingPriorityMarkers(from: title)
        input.title = cleaned.isEmpty ? title : cleaned
        return input
    }

    /// Splits the text after `#subject -` into a topic name and whatever task text
    /// follows it. An existing topic is matched first (longest name wins); otherwise a
    /// colon ends the new topic's name.
    private static func splitTopic(from text: String, subject: StudySubject, subtopics: [Subtopic]) -> (topic: String, taskText: String) {
        let candidates = subtopics
            .filter { $0.subject == subject && !$0.name.isEmpty }
            .sorted { $0.name.count > $1.name.count }
        for topic in candidates {
            guard text.count >= topic.name.count else { continue }
            let end = text.index(text.startIndex, offsetBy: topic.name.count)
            guard text[..<end].compare(topic.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame else { continue }
            if end < text.endIndex {
                let next = text[end]
                if next.isLetter || next.isNumber { continue }
            }
            var remainder = String(text[end...]).trimmingCharacters(in: .whitespaces)
            if let first = remainder.first, first == ":" || first == "," || first == "-" {
                remainder = String(remainder.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return (topic.name, remainder)
        }

        if let colon = text.firstIndex(of: ":") {
            let name = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            let remainder = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            return (name, remainder.isEmpty ? name : remainder)
        }
        return (text, text)
    }

    private static func strippingPriorityMarkers(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?i)(?<![a-z0-9])p[1-4](?![0-9])") else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let stripped = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return stripped.split(whereSeparator: { $0 == " " }).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `p1`–`p4` anywhere in the task text sets the priority.
    private static func detectPriority(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "(?i)(?<![a-z0-9])p([1-4])(?![0-9])") else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let digits = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[digits])
    }
}

extension StudySubject {
    /// Names accepted in a `#subject` tag, longest first so `Ext 2 Maths` wins over `Ext 2`.
    var tagAliases: [String] {
        switch self {
        case .ext2Maths: ["Mathematics Extension 2", "Maths Extension 2", "Ext 2 Maths", "Math Ext 2", "Ext 2", "4U Maths", "4U"]
        case .ext1Maths: ["Mathematics Extension 1", "Maths Extension 1", "Ext 1 Maths", "Math Ext 1", "Ext 1", "3U Maths", "3U"]
        case .physics: ["Physics", "Phys"]
        case .chemistry: ["Chemistry", "Chem"]
        case .softwareEngineering: ["Software Engineering", "Software Eng", "Software", "SDD"]
        case .englishAdvanced: ["English Advanced", "English Adv", "English"]
        case .other: ["Other"]
        }
    }

    /// Matches a subject tag at the start of `text`, returning how many characters it used.
    static func tagMatch(in text: Substring) -> (subject: StudySubject, consumed: Int)? {
        var best: (subject: StudySubject, consumed: Int)?
        for subject in StudySubject.allCases {
            for alias in subject.tagAliases {
                guard let consumed = matchAlias(alias, atStartOf: text) else { continue }
                if consumed > (best?.consumed ?? 0) { best = (subject, consumed) }
            }
        }
        return best
    }

    private static func matchAlias(_ alias: String, atStartOf text: Substring) -> Int? {
        var index = text.startIndex
        var consumed = 0
        for character in alias.lowercased() {
            if character == " " { continue }
            while index < text.endIndex, text[index] == " " {
                index = text.index(after: index)
                consumed += 1
            }
            guard index < text.endIndex, String(text[index]).lowercased() == String(character) else { return nil }
            index = text.index(after: index)
            consumed += 1
        }
        // A tag must not stop halfway through a word: `#Ext 22` is not Ext 2.
        if index < text.endIndex {
            let next = text[index]
            if next.isLetter || next.isNumber { return nil }
        }
        return consumed
    }
}

/// Everything a player has done for a subject or a single subtopic: time, volume of
/// work, and how the marks have actually gone.
struct StudyAggregate: Equatable {
    var sessions: Int = 0
    var minutes: Int = 0
    var marksObtained: Int = 0
    var marksTotal: Int = 0
    var homework: Int = 0
    var pastPapers: Int = 0
    var examQuestions: Int = 0
    var cashEarned: Int = 0
    var xpEarned: Int = 0

    var workCount: Int { homework + pastPapers + examQuestions }

    var hasMarks: Bool { marksTotal > 0 }

    /// Weighted average: every mark attempted counts the same, so a 20-mark paper
    /// carries more than a 5-mark homework.
    var averageRatio: Double? {
        guard marksTotal > 0 else { return nil }
        return Double(marksObtained) / Double(marksTotal)
    }

    var averagePercentage: Int? {
        averageRatio.map { Int(($0 * 100).rounded()) }
    }

    mutating func add(_ session: StudySession) {
        sessions += 1
        minutes += max(0, session.minutes)
        cashEarned += session.cashEarned
        xpEarned += session.xpEarned
        switch session.kind {
        case .homework: homework += session.quantity
        case .pastPaper: pastPapers += session.quantity
        case .examQuestions: examQuestions += session.quantity
        case .focusSession: break
        }
        if let obtained = session.marksObtained, let total = session.marksTotal, total > 0 {
            marksObtained += min(max(0, obtained), total)
            marksTotal += total
        }
    }

    static func build(from sessions: [StudySession]) -> StudyAggregate {
        var aggregate = StudyAggregate()
        for session in sessions {
            aggregate.add(session)
        }
        return aggregate
    }
}

/// A mark a student gained or lost in one topic of an assessment.
struct AssessmentTopicResult: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var subtopicID: UUID?
    var subtopicName: String
    /// Marks gained (positive) or lost (negative) within this topic.
    var marksChange: Int
}

/// A test or exam. Rewards come from `classRank` only; marks and overall rank are for the graphs.
struct Assessment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var subject: StudySubject
    var title: String
    var marksObtained: Int
    var marksTotal: Int
    /// Share of the subject's final mark, in percent (0...100).
    var weighting: Int
    /// 1 is the best place in the class for this single assessment. Nil until entered.
    var classRank: Int?
    /// Overall class position after this assessment, as the student's cumulative rank.
    var overallRank: Int?
    var cashEarned: Int = 0
    var xpEarned: Int = 0
    var topicResults: [AssessmentTopicResult] = []

    var percentage: Int? {
        guard marksTotal > 0 else { return nil }
        return Int((Double(marksObtained) / Double(marksTotal) * 100).rounded())
    }
}

/// The rewards a logged session earns. Marks are entered as marks gained over marks
/// attempted; that fraction becomes a percentage, and the percentage sets how much of
/// the base reward the session is worth.
struct StudyReward {
    let cash: Int
    let xp: Int
    /// Marks gained divided by marks attempted, 0...1. Nil when nothing was marked.
    let ratio: Double?

    var percentage: Int? { ratio.map { Int(($0 * 100).rounded()) } }

    /// Unmarked work earns the plain rate. Marked work scales from 0.8x at 0% up to
    /// 1.45x at 100%, so a strong paper is worth noticeably more than a weak one.
    static func gradeFactor(for ratio: Double?) -> Double {
        guard let ratio else { return 1.0 }
        return 0.8 + min(1, max(0, ratio)) * 0.65
    }

    static func calculate(
        kind: StudyActivityKind,
        subject: StudySubject,
        minutes: Int,
        marksObtained: Int?,
        marksTotal: Int?
    ) -> StudyReward {
        var ratio: Double?
        if let marksObtained, let marksTotal, marksTotal > 0, marksObtained >= 0 {
            ratio = min(1, Double(marksObtained) / Double(marksTotal))
        }
        let grade = gradeFactor(for: ratio)
        let cash = Double(max(0, minutes)) * Double(GameRules.clubCashPerMinute) * subject.cashMultiplier * kind.rewardMultiplier * grade
        let xp = Double(max(0, minutes)) * Double(GameRules.xpPerMinute) * subject.xpMultiplier * kind.rewardMultiplier * grade
        return StudyReward(cash: Int(cash.rounded()), xp: Int(xp.rounded()), ratio: ratio)
    }
}

struct StudyStats: Codable {
    var totalStudyMinutes: Int
    var totalSessions: Int
    var homeworkCompleted: Int
    var pastPapersCompleted: Int
    var examQuestionsSolved: Int
    var currentStreak: Int
    var bestStreak: Int
    var lastStudyDay: Date?

    static let empty = StudyStats(
        totalStudyMinutes: 0,
        totalSessions: 0,
        homeworkCompleted: 0,
        pastPapersCompleted: 0,
        examQuestionsSolved: 0,
        currentStreak: 0,
        bestStreak: 0,
        lastStudyDay: nil
    )
}

enum SeasonPhase: String, Codable, CaseIterable, Identifiable {
    case league
    case playoffs
    case roundOf16
    case quarterfinal
    case semifinal
    case final
    case complete

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .league: "League Phase"
        case .playoffs: "Knockout Playoff"
        case .roundOf16: "Round of 16"
        case .quarterfinal: "Quarter-final"
        case .semifinal: "Semi-final"
        case .final: "Final"
        case .complete: "Complete"
        }
    }

    var shortName: String {
        switch self {
        case .league: "League"
        case .playoffs: "Playoff"
        case .roundOf16: "R16"
        case .quarterfinal: "QF"
        case .semifinal: "SF"
        case .final: "Final"
        case .complete: "Done"
        }
    }

    var isKnockout: Bool {
        switch self {
        case .playoffs, .roundOf16, .quarterfinal, .semifinal, .final: true
        case .league, .complete: false
        }
    }
}

struct Fixture: Identifiable, Codable, Hashable {
    var id: UUID
    var homeClubID: String
    var awayClubID: String
    var phase: SeasonPhase
    var round: Int
    var neutralVenue: Bool
    var homeGoals: Int?
    var awayGoals: Int?
    var homePenalties: Int?
    var awayPenalties: Int?

    var isSimulated: Bool {
        homeGoals != nil && awayGoals != nil
    }

    var winnerClubID: String? {
        guard let homeGoals, let awayGoals else { return nil }
        if homeGoals > awayGoals { return homeClubID }
        if awayGoals > homeGoals { return awayClubID }
        guard let homePenalties, let awayPenalties else { return nil }
        return homePenalties > awayPenalties ? homeClubID : awayClubID
    }

    var loserClubID: String? {
        guard let winnerClubID else { return nil }
        return winnerClubID == homeClubID ? awayClubID : homeClubID
    }

    var scoreline: String {
        guard let homeGoals, let awayGoals else { return "vs" }
        if let homePenalties, let awayPenalties {
            return "\(homeGoals)-\(awayGoals) (\(homePenalties)-\(awayPenalties) pens)"
        }
        return "\(homeGoals)-\(awayGoals)"
    }
}

struct MatchEvent: Identifiable, Codable, Hashable {
    var id: UUID
    var minute: Int
    var clubID: String
    var scorer: String
    /// Optional so saves made before assists were tracked still decode.
    var assister: String?
    var isPenalty: Bool
}

struct MatchReport: Identifiable, Codable, Hashable {
    var id: UUID
    var fixtureID: UUID
    var phase: SeasonPhase
    var round: Int
    var homeClubID: String
    var awayClubID: String
    var homeGoals: Int
    var awayGoals: Int
    var homePenalties: Int?
    var awayPenalties: Int?
    var events: [MatchEvent]
    var homeRating: Int
    var awayRating: Int
    var summary: String
    var playedAt: Date

    var winnerClubID: String? {
        if homeGoals > awayGoals { return homeClubID }
        if awayGoals > homeGoals { return awayClubID }
        guard let homePenalties, let awayPenalties else { return nil }
        return homePenalties > awayPenalties ? homeClubID : awayClubID
    }

    var scoreline: String {
        if let homePenalties, let awayPenalties {
            return "\(homeGoals)-\(awayGoals) (\(homePenalties)-\(awayPenalties) pens)"
        }
        return "\(homeGoals)-\(awayGoals)"
    }

    var scorersForHome: [(name: String, goals: Int)] {
        groupedScorers(for: homeClubID)
    }

    var scorersForAway: [(name: String, goals: Int)] {
        groupedScorers(for: awayClubID)
    }

    private func groupedScorers(for clubID: String) -> [(name: String, goals: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for event in events where event.clubID == clubID {
            if counts[event.scorer] == nil { order.append(event.scorer) }
            counts[event.scorer, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }
}

struct SeasonState: Codable {
    var number: Int
    var phase: SeasonPhase
    var nextLeagueRound: Int
    var fixtures: [Fixture]
    var reports: [MatchReport]
    var championClubID: String?
    var runnerUpClubID: String?
    var archived: Bool

    static func new(number: Int) -> SeasonState {
        SeasonState(
            number: number,
            phase: .league,
            nextLeagueRound: 1,
            fixtures: [],
            reports: [],
            championClubID: nil,
            runnerUpClubID: nil,
            archived: false
        )
    }

    var leagueFixtures: [Fixture] {
        fixtures.filter { $0.phase == .league }
    }

    var currentFixtures: [Fixture] {
        switch phase {
        case .league:
            return fixtures.filter { $0.phase == .league && $0.round == nextLeagueRound }
        case .complete:
            return []
        default:
            return fixtures.filter { $0.phase == phase }
        }
    }

    func fixtures(for phase: SeasonPhase) -> [Fixture] {
        fixtures.filter { $0.phase == phase }
    }

    var isLeagueComplete: Bool {
        leagueFixtures.count == 144 && leagueFixtures.allSatisfy(\.isSimulated)
    }

    var leagueRoundsPlayed: Int {
        let rounds = Dictionary(grouping: leagueFixtures, by: \.round)
        return rounds.values.filter { $0.allSatisfy(\.isSimulated) }.count
    }
}

struct StandingRow: Identifiable, Hashable {
    var id: String { club.id }
    let club: Club
    var played: Int
    var won: Int
    var drawn: Int
    var lost: Int
    var goalsFor: Int
    var goalsAgainst: Int
    var points: Int

    var goalDifference: Int { goalsFor - goalsAgainst }
}

struct TrophyRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var seasonNumber: Int
    var championClubID: String
    var championName: String
    var runnerUpClubID: String
    var runnerUpName: String
    var userClubID: String
    var userClubName: String
    var userFinish: String
    var userWasChampion: Bool
    var completedAt: Date
    /// Individual awards for the season. Optional so older saves still decode.
    var topScorerName: String?
    var topScorerClubName: String?
    var topScorerGoals: Int?
    var topAssisterName: String?
    var topAssisterClubName: String?
    var topAssisterAssists: Int?
}

struct SeasonTransition: Codable, Identifiable, Hashable {
    var id: UUID
    var completedSeason: Int
    var championName: String
    var userFinish: String
    var retirees: [String]
    var youthAdded: Int
    var newSeason: Int
}

struct PackDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let price: Int
    let playerCount: Int
    let minimumLevel: Int
    let accentHex: String
    let systemImage: String
    let rarityWeights: [PlayerRarity: Int]

    var odds: [(rarity: PlayerRarity, percent: Int)] {
        let total = rarityWeights.values.reduce(0, +)
        guard total > 0 else { return [] }
        return PlayerRarity.allCases.compactMap { rarity in
            guard let weight = rarityWeights[rarity] else { return nil }
            return (rarity, Int((Double(weight) / Double(total) * 100).rounded()))
        }
    }
}

enum PackCatalog {
    static let all: [PackDefinition] = [
        PackDefinition(
            id: "bronze",
            name: "Bronze Pack",
            subtitle: "Three squad players with a touch of senior experience.",
            price: 350,
            playerCount: 3,
            minimumLevel: 1,
            accentHex: "B47142",
            systemImage: "shippingbox",
            rarityWeights: [.bronze: 82, .silver: 18]
        ),
        PackDefinition(
            id: "silver",
            name: "Silver Pack",
            subtitle: "Three players. A strong pathway to a gold starter.",
            price: 900,
            playerCount: 3,
            minimumLevel: 2,
            accentHex: "9BA6B2",
            systemImage: "square.stack.3d.up",
            rarityWeights: [.bronze: 25, .silver: 62, .gold: 13]
        ),
        PackDefinition(
            id: "academy",
            name: "Academy Pack",
            subtitle: "Three prospects. High potential, low starting ratings.",
            price: 1200,
            playerCount: 3,
            minimumLevel: 2,
            accentHex: "4CD6B8",
            systemImage: "graduationcap",
            rarityWeights: [.silver: 40, .gold: 30, .wonderkid: 30]
        ),
        PackDefinition(
            id: "gold",
            name: "Gold Pack",
            subtitle: "Three players. At least one gold standard guaranteed.",
            price: 2200,
            playerCount: 3,
            minimumLevel: 3,
            accentHex: "D8A72A",
            systemImage: "star.square",
            rarityWeights: [.silver: 10, .gold: 82, .wonderkid: 6, .icon: 2]
        ),
        PackDefinition(
            id: "icon",
            name: "Icon Pack",
            subtitle: "One elite signing. The shortest path to a world-class XI.",
            price: 6000,
            playerCount: 1,
            minimumLevel: 5,
            accentHex: "E8D38A",
            systemImage: "crown",
            rarityWeights: [.gold: 30, .wonderkid: 25, .icon: 45]
        )
    ]

    static func pack(for id: String) -> PackDefinition? {
        all.first(where: { $0.id == id })
    }
}

struct GameState: Codable {
    static let currentSchemaVersion = 5

    var schemaVersion: Int
    var createdAt: Date
    var managedClubID: String?
    var clubCash: Int
    var xp: Int
    var availableMatchMinutes: Int
    var study: StudyStats
    var recentSessions: [StudySession]
    var subtopics: [Subtopic]
    var players: [Player]
    var freeAgents: [Player]
    var lineup: [String: UUID]
    var bench: [UUID]
    var trophies: [TrophyRecord]
    var season: SeasonState?
    var seasonNumber: Int
    var lastTransition: SeasonTransition?
    var todos: [TodoItem]
    /// Career-long goals and assists for every simulated match, kept across seasons.
    var scoringLedger: [PlayerScoringRecord] = []
    /// Offers from other clubs for players you have listed. Kept until accepted, declined or the player leaves.
    var transferOffers: [TransferOffer] = []
    /// Youth academy level from 1 (poor intake) to `GameRules.maxAcademyLevel` (elite intake).
    var academyLevel: Int = 1
    /// Competitive matches played since the last academy intake.
    var matchesSinceAcademyIntake: Int = 0
    /// Tests and exams with their marks, weightings, class ranks and topic results.
    var assessments: [Assessment] = []

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case createdAt
        case managedClubID
        case clubCash
        case xp
        case availableMatchMinutes
        case study
        case recentSessions
        case subtopics
        case todos
        case players
        case freeAgents
        case lineup
        case bench
        case trophies
        case season
        case seasonNumber
        case lastTransition
        case scoringLedger
        case transferOffers
        case academyLevel
        case matchesSinceAcademyIntake
        case assessments
    }

    static func fresh() -> GameState {
        GameState(
            schemaVersion: currentSchemaVersion,
            createdAt: Date(),
            managedClubID: nil,
            clubCash: GameRules.startingCash,
            xp: 0,
            availableMatchMinutes: 0,
            study: .empty,
            recentSessions: [],
            subtopics: [],
            players: [],
            freeAgents: [],
            lineup: [:],
            bench: [],
            trophies: [],
            season: nil,
            seasonNumber: 1,
            lastTransition: nil,
            todos: []
        )
    }
}

extension Player {
    /// Injury fields are optional in the file so careers saved before injuries existed still open.
    /// Declared in an extension so the memberwise initializer stays available.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        nationCode = try container.decode(String.self, forKey: .nationCode)
        position = try container.decode(PlayerPosition.self, forKey: .position)
        age = try container.decode(Int.self, forKey: .age)
        overall = try container.decode(Int.self, forKey: .overall)
        potential = try container.decode(Int.self, forKey: .potential)
        rarity = try container.decode(PlayerRarity.self, forKey: .rarity)
        attributes = try container.decode(PlayerAttributes.self, forKey: .attributes)
        retirementAge = try container.decode(Int.self, forKey: .retirementAge)
        joinedSeason = try container.decode(Int.self, forKey: .joinedSeason)
        dbID = try container.decodeIfPresent(Int.self, forKey: .dbID)
        clubID = try container.decodeIfPresent(String.self, forKey: .clubID)
        isUserListing = try container.decodeIfPresent(Bool.self, forKey: .isUserListing) ?? false
        listingPrice = try container.decodeIfPresent(Int.self, forKey: .listingPrice)
        isInjured = try container.decodeIfPresent(Bool.self, forKey: .isInjured) ?? false
        matchesMissed = try container.decodeIfPresent(Int.self, forKey: .matchesMissed) ?? 0
    }
}

extension GameState {
    /// Decoded by hand so saves written before subtopics existed still open: a missing
    /// `subtopics` key simply means the player has not created any yet.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        managedClubID = try container.decodeIfPresent(String.self, forKey: .managedClubID)
        clubCash = try container.decode(Int.self, forKey: .clubCash)
        xp = try container.decode(Int.self, forKey: .xp)
        availableMatchMinutes = try container.decode(Int.self, forKey: .availableMatchMinutes)
        study = try container.decodeIfPresent(StudyStats.self, forKey: .study) ?? StudyStats.empty
        recentSessions = try container.decodeIfPresent([StudySession].self, forKey: .recentSessions) ?? []
        subtopics = try container.decodeIfPresent([Subtopic].self, forKey: .subtopics) ?? []
        players = try container.decodeIfPresent([Player].self, forKey: .players) ?? []
        freeAgents = try container.decodeIfPresent([Player].self, forKey: .freeAgents) ?? []
        lineup = try container.decodeIfPresent([String: UUID].self, forKey: .lineup) ?? [:]
        bench = try container.decodeIfPresent([UUID].self, forKey: .bench) ?? []
        trophies = try container.decodeIfPresent([TrophyRecord].self, forKey: .trophies) ?? []
        season = try container.decodeIfPresent(SeasonState.self, forKey: .season)
        seasonNumber = try container.decodeIfPresent(Int.self, forKey: .seasonNumber) ?? 1
        lastTransition = try container.decodeIfPresent(SeasonTransition.self, forKey: .lastTransition)
        todos = try container.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
        scoringLedger = try container.decodeIfPresent([PlayerScoringRecord].self, forKey: .scoringLedger) ?? []
        transferOffers = try container.decodeIfPresent([TransferOffer].self, forKey: .transferOffers) ?? []
        academyLevel = try container.decodeIfPresent(Int.self, forKey: .academyLevel) ?? 1
        matchesSinceAcademyIntake = try container.decodeIfPresent(Int.self, forKey: .matchesSinceAcademyIntake) ?? 0
        assessments = try container.decodeIfPresent([Assessment].self, forKey: .assessments) ?? []
    }
}

/// An offer from another club for one of your listed players.
struct TransferOffer: Identifiable, Codable, Hashable {
    var id: UUID
    var playerID: UUID
    var clubName: String
    var amount: Int
    var createdAt: Date
}

/// One player's goals and assists in one club's matches. Keyed by name and club so the
/// leaderboard can combine every simulated game, including matches the user never played.
struct PlayerScoringRecord: Codable, Hashable {
    var name: String
    var clubID: String
    var goals: Int
    var assists: Int
}

extension Array where Element == PlayerScoringRecord {
    /// Adds every match in a list to the ledger.
    mutating func record(reports: [MatchReport]) {
        for report in reports {
            record(report: report)
        }
    }

    /// Adds every goal and assist in a match to the ledger.
    mutating func record(report: MatchReport) {
        for event in report.events {
            add(name: event.scorer, clubID: event.clubID, goals: 1, assists: 0)
            if let assister = event.assister {
                add(name: assister, clubID: event.clubID, goals: 0, assists: 1)
            }
        }
    }

    private mutating func add(name: String, clubID: String, goals: Int, assists: Int) {
        if let index = firstIndex(where: { $0.name == name && $0.clubID == clubID }) {
            self[index].goals += goals
            self[index].assists += assists
        } else {
            append(PlayerScoringRecord(name: name, clubID: clubID, goals: goals, assists: assists))
        }
    }
}
