import Foundation

/// Serialized, bounded focus retries for asynchronous application activation.
public final class FocusCoordinator {
    private let adapter: WindowAdapter
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var generation = 0
    public init(adapter: WindowAdapter, schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void) {
        self.adapter = adapter; self.schedule = schedule
    }
    public func cancel() { generation += 1 }
    public func request(_ id: String, isCurrent: @escaping () -> Bool, afterAttempt: @escaping () -> Void, completion: @escaping (Bool) -> Void) {
        generation += 1
        attempt(id, token: generation, count: 0, isCurrent: isCurrent, afterAttempt: afterAttempt, completion: completion)
    }
    private func attempt(_ id: String, token: Int, count: Int, isCurrent: @escaping () -> Bool, afterAttempt: @escaping () -> Void, completion: @escaping (Bool) -> Void) {
        guard token == generation, isCurrent() else { return }
        let focused = adapter.focus(id)
        afterAttempt()
        if focused { completion(true); return }
        guard count < 2 else { completion(false); return }
        schedule(0.15) { [weak self] in
            self?.attempt(id, token: token, count: count+1, isCurrent: isCurrent, afterAttempt: afterAttempt, completion: completion)
        }
    }
}
