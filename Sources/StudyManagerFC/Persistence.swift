import Foundation

struct PersistenceStore {
    let directory: URL
    let saveURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseDirectory: URL? = nil) {
        let root: URL
        if let baseDirectory {
            root = baseDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            root = support.appendingPathComponent("StudyManagerFC", isDirectory: true)
        }
        directory = root
        saveURL = root.appendingPathComponent("career.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> GameState? {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return nil }
        let data = try Data(contentsOf: saveURL)
        do {
            return try decoder.decode(GameState.self, from: data)
        } catch {
            preserveCorruptSave()
            throw error
        }
    }

    func save(_ state: GameState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: saveURL, options: .atomic)
    }

    private func preserveCorruptSave() {
        let backup = directory.appendingPathComponent("career-corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: saveURL, to: backup)
    }
}
