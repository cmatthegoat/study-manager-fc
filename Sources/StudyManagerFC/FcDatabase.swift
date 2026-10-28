import Foundation

/// One club from the game database (`fifa_ng_db.db`). Clubs inside the app's Champions
/// League keep their existing app id, so colours, saves and fixtures keep working;
/// every other club exists to own players and to negotiate when you try to sign them.
struct FcClub: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let rating: Int
    let league: String?
    let teamID: Int
    let competition: Bool
}

/// A nation that appears in the database. `code` is the three letter code the app uses.
struct FcNation: Codable, Hashable, Identifiable {
    let code: String
    let name: String
    let flag: String

    var id: String { code }
}

/// One player row from the database. Names are absent because EA stores them in the
/// encrypted localization file; a name is generated deterministically from the player id
/// unless the data file supplies one.
struct FcPlayer: Codable, Identifiable, Hashable {
    let id: Int
    let ovr: Int
    let pot: Int
    let pos: String
    let nat: String
    let age: Int
    let club: String
    /// Present when the data file has been given real names.
    let name: String?

    var position: PlayerPosition {
        FcDatabase.positionMapping[pos] ?? .centralMid
    }

    /// `Scripts/fill-potential.py` writes the game's own potential into every row, so
    /// `pot` is usually above `ovr` and is the ceiling the player grows towards. A file
    /// that has not been through that step carries `pot` equal to `ovr`, which would leave
    /// database players unable to grow; those rows fall back to a ceiling from the same
    /// age bands the generated players use, seeded by the database id so it stays stable
    /// across launches. Real potentials in the data file win.
    var potential: Int {
        pot > ovr ? pot : PlayerFactory.databasePotential(overall: ovr, age: age, databaseID: id)
    }

    var rarity: PlayerRarity {
        if ovr >= 86 { return .icon }
        if ovr >= 78 { return .gold }
        if ovr >= 70 { return .silver }
        return .bronze
    }
}

private struct FcDatabaseFile: Codable {
    let clubs: [FcClub]
    let players: [FcPlayer]
    let nations: [FcNation]
}

/// The loaded game database: every club, every player, and the lookups the app needs.
final class FcDatabase {
    static let shared = FcDatabase.load()

    let clubs: [FcClub]
    let players: [FcPlayer]
    let nations: [FcNation]

    private let clubByID: [String: FcClub]
    private let nationByCode: [String: FcNation]
    private let playersByClub: [String: [FcPlayer]]
    /// Display names, allocated once so no two players in the database share one.
    private var allocatedNames: [Int: String] = [:]

    /// True when the database resource was found and decoded.
    var isLoaded: Bool { !players.isEmpty }

    init(clubs: [FcClub] = [], players: [FcPlayer] = [], nations: [FcNation] = []) {
        self.clubs = clubs
        self.players = players
        self.nations = nations
        self.clubByID = Dictionary(clubs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.nationByCode = Dictionary(nations.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        self.playersByClub = Dictionary(grouping: players, by: \.club)
        self.allocatedNames = Self.allocateNames(for: players)
    }

    static func load() -> FcDatabase {
        guard let url = databaseURL() else {
            NSLog("StudyManagerFC: fc-database.json not found")
            return FcDatabase()
        }
        do {
            let file = try JSONDecoder().decode(FcDatabaseFile.self, from: Data(contentsOf: url))
            // A file whose players are all at their overall was built before potentials
            // were filled in; transfers and ceilings then look frozen, so say so loudly.
            if !file.players.isEmpty, file.players.allSatisfy({ $0.pot <= $0.ovr }) {
                NSLog("StudyManagerFC: fc-database.json carries no potentials (pot == ovr for every row) — run Scripts/fill-potential.py and repackage")
            }
            return FcDatabase(clubs: file.clubs, players: file.players, nations: file.nations)
        } catch {
            NSLog("StudyManagerFC: could not read fc-database.json: \(error)")
            return FcDatabase()
        }
    }

    private static func databaseURL() -> URL? {
        // Bundle.main covers the packaged .app (Contents/Resources), where the JSON is
        // copied by Scripts/package-app.sh.
        if let url = Bundle.main.url(forResource: "fc-database", withExtension: "json") {
            return url
        }
        // Running straight from `swift build` / a hand-wrapped .app: look next to the
        // executable and one level up into the source tree.
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidates = [
            executable.deletingLastPathComponent().appendingPathComponent("fc-database.json"),
            executable.deletingLastPathComponent().appendingPathComponent("Resources/fc-database.json"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/fc-database.json")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func club(_ id: String) -> FcClub? {
        clubByID[id]
    }

    func nation(code: String) -> FcNation? {
        nationByCode[code]
    }

    func squad(for clubID: String) -> [FcPlayer] {
        playersByClub[clubID] ?? []
    }

    func player(id: Int) -> FcPlayer? {
        players.first { $0.id == id }
    }

    /// A stable display name. The data file wins when it carries one; otherwise the name
    /// is derived from the player id and nationality so it never changes between runs.
    func displayName(for player: FcPlayer) -> String {
        if let name = player.name, !name.isEmpty { return name }
        if let allocated = allocatedNames[player.id] { return allocated }
        return Self.baseName(for: player)
    }

    private static func baseName(for player: FcPlayer) -> String {
        var generator = SeededGenerator(seed: StableSeed.value(for: "fc-name-\(player.id)-\(player.nat)"))
        let pool = NameDatabase.pool(for: player.nat)
        let first = pool.first.randomElement(using: &generator) ?? "Alex"
        let last = pool.last.randomElement(using: &generator) ?? "Silva"
        return "\(first) \(last)"
    }

    /// Names are generated from nationality pools, which are far smaller than the player
    /// list, so a plain first-last pair repeats several times. Going through the players
    /// in id order and widening a name with a middle name (or, rarely, an initial) keeps
    /// every player in the database distinct.
    private static func allocateNames(for players: [FcPlayer]) -> [Int: String] {
        var used = Set<String>()
        var result: [Int: String] = [:]
        result.reserveCapacity(players.count)
        let initials = ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "O", "P", "R", "S", "T", "V", "W"]

        for player in players.sorted(by: { $0.id < $1.id }) {
            if let real = player.name, !real.isEmpty {
                result[player.id] = real
                used.insert(real)
                continue
            }
            var generator = SeededGenerator(seed: StableSeed.value(for: "fc-name-\(player.id)-\(player.nat)"))
            let pool = NameDatabase.pool(for: player.nat)
            let first = pool.first.randomElement(using: &generator) ?? "Alex"
            let last = pool.last.randomElement(using: &generator) ?? "Silva"

            var candidate = "\(first) \(last)"
            if used.contains(candidate) {
                var middleGenerator = SeededGenerator(seed: StableSeed.value(for: "fc-middle-\(player.id)"))
                let offset = Int.random(in: 0..<max(1, pool.first.count), using: &middleGenerator)
                var resolved = false
                for index in 0..<pool.first.count {
                    let middle = pool.first[(offset + index) % pool.first.count]
                    let attempt = "\(first) \(middle) \(last)"
                    if !used.contains(attempt) {
                        candidate = attempt
                        resolved = true
                        break
                    }
                }
                if !resolved {
                    for initial in initials {
                        let attempt = "\(first) \(initial). \(last)"
                        if !used.contains(attempt) {
                            candidate = attempt
                            resolved = true
                            break
                        }
                    }
                }
                if !resolved {
                    var suffix = 2
                    while used.contains("\(first) \(last) \(suffix)") { suffix += 1 }
                    candidate = "\(first) \(last) \(suffix)"
                }
            }
            used.insert(candidate)
            result[player.id] = candidate
        }
        return result
    }

    /// Twelve outfield players plus two keepers, chosen to cover the app's XI.
    static let squadPositions: [PlayerPosition] = [
        .goalkeeper, .goalkeeper,
        .leftBack, .centerBack, .centerBack, .centerBack, .rightBack,
        .defensiveMid, .centralMid, .centralMid, .attackingMid,
        .leftWing, .leftWing, .striker, .striker, .rightWing,
        .centerBack, .centralMid
    ]

    /// Mapping from database position strings to PlayerPosition enum values.
    static var positionMapping: [String: PlayerPosition] {
        let mapping: [String: PlayerPosition] = [
            "GK": .goalkeeper,
            "LB": .leftBack,
            "CB": .centerBack,
            "RB": .rightBack,
            "DM": .defensiveMid,
            "CM": .centralMid,
            "CAM": .attackingMid,
            "LW": .leftWing,
            "ST": .striker,
            "RW": .rightWing,
            "CDM": .defensiveMid,
            "LM": .leftWing,
            "RM": .rightWing,
        ]
        return mapping
    }

    /// Builds a squad for a club, best players first, covering every position the lineup
    /// needs. Extra players are kept so the squad list feels like a real club.
    func squadPlayers(for clubID: String, limit: Int = 24) -> [FcPlayer] {
        let available = squad(for: clubID).sorted { lhs, rhs in
            if lhs.ovr == rhs.ovr { return lhs.potential > rhs.potential }
            return lhs.ovr > rhs.ovr
        }
        guard !available.isEmpty else { return [] }

        var used = Set<Int>()
        var picked: [FcPlayer] = []

        func take(_ predicate: (FcPlayer) -> Bool) {
            guard let candidate = available.first(where: { !used.contains($0.id) && predicate($0) }) else { return }
            used.insert(candidate.id)
            picked.append(candidate)
        }

        for position in FcDatabase.squadPositions where picked.count < FcDatabase.squadPositions.count {
            take { FcDatabase.positionMapping[$0.rawPosition] == position || $0.position == position }
        }
        for player in available where picked.count < limit && !used.contains(player.id) {
            used.insert(player.id)
            picked.append(player)
        }
        return Array(picked.prefix(limit))
    }
}

extension FcPlayer {
    var rawPosition: String { pos }

    /// Teammates with the same generated name are disambiguated so a squad list never
    /// shows the same name twice.
    func disambiguatedName(in squad: [FcPlayer], database: FcDatabase) -> String {
        let base = database.displayName(for: self)
        let collisions = squad.filter { database.displayName(for: $0) == base }
        guard collisions.count > 1, let index = collisions.firstIndex(where: { $0.id == id }) else {
            return base
        }
        let initials = ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "P", "R", "S", "T"]
        let initial = initials[index % initials.count]
        var parts = base.split(separator: " ")
        guard parts.count >= 2 else { return base }
        parts.insert(Substring("\(initial)."), at: 1)
        return parts.joined(separator: " ")
    }
}
