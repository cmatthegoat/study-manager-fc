import Foundation

/// Holds the one career state that still needs writing. Commits replace whatever was waiting,
/// so a burst of edits — one per keystroke — costs a single write of the latest state rather
/// than a file write per keystroke. `submit` tells the caller whether it must wake the writer,
/// which keeps a single drain running on the save queue.
final class SavePump: @unchecked Sendable {
    struct Job {
        let store: PersistenceStore
        let state: GameState
        let onError: @Sendable (String) -> Void
    }

    private let lock = NSLock()
    private var pending: Job?

    /// Stores `state` as the career to write. True when nothing was waiting, so the caller
    /// has to schedule the writer.
    func submit(
        _ store: PersistenceStore,
        _ state: GameState,
        onError: @escaping @Sendable (String) -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let wasIdle = pending == nil
        pending = Job(store: store, state: state, onError: onError)
        return wasIdle
    }

    /// Takes the newest job, leaving the pump empty for the next commit.
    func take() -> Job? {
        lock.lock()
        defer { lock.unlock() }
        let job = pending
        pending = nil
        return job
    }
}
