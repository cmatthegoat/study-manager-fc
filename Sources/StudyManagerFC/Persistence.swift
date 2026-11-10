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

    /// Scans attached to Bulletproof Journal entries live beside the career file rather than
    /// inside it, so a journal full of photos does not bloat the save.
    var journalAttachmentsDirectory: URL {
        directory.appendingPathComponent("JournalAttachments", isDirectory: true)
    }

    func journalAttachmentURL(_ name: String) -> URL {
        journalAttachmentsDirectory.appendingPathComponent(name)
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

    /// How many previous careers are kept beside the live file.
    static let backupsKept = 3

    func save(_ state: GameState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        rotateBackups()
        let data = try encoder.encode(state)
        try data.write(to: saveURL, options: .atomic)
    }

    func backupURL(_ index: Int) -> URL {
        directory.appendingPathComponent("career-backup-\(index).json")
    }

    /// Shifts the previous careers along before the live file is replaced, so a bad save or
    /// an interrupted write costs at most the newest one.
    private func rotateBackups() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: saveURL.path) else { return }
        try? fm.removeItem(at: backupURL(Self.backupsKept))
        for index in stride(from: Self.backupsKept - 1, through: 1, by: -1) {
            let from = backupURL(index)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.moveItem(at: from, to: backupURL(index + 1))
        }
        try? fm.copyItem(at: saveURL, to: backupURL(1))
    }

    /// The newest backup that still decodes, for the restore action.
    func loadLatestBackup() throws -> GameState? {
        for index in 1...Self.backupsKept {
            let url = backupURL(index)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let state = try? decoder.decode(GameState.self, from: Data(contentsOf: url)) {
                return state
            }
        }
        return nil
    }

    private func preserveCorruptSave() {
        let backup = directory.appendingPathComponent("career-corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: saveURL, to: backup)
    }
}
