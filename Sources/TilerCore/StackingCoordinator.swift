import Foundation

/// Application activation may reorder windows after AX reports focus success.
/// Repair stacking briefly afterward without issuing another focus request.
public final class StackingCoordinator {
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var generation = 0
    public init(schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void) {
        self.schedule = schedule
    }
    public func cancel() { generation += 1 }
    public func request(isCurrent: @escaping () -> Bool, restore: @escaping () -> Void) {
        generation += 1
        let token = generation
        for delay in [0.15, 0.4, 0.8] {
            schedule(delay) { [weak self] in
                guard let self, self.generation == token, isCurrent() else { return }
                restore()
            }
        }
    }
}
