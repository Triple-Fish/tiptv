import Foundation

@MainActor
final class DebouncedWorkScheduler<Value: Sendable> {
    private var task: Task<Void, Never>?

    func schedule(
        delay: Duration = .zero,
        operation: @escaping @Sendable () -> Value,
        apply: @escaping @MainActor (Value) -> Void
    ) {
        task?.cancel()
        task = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated, operation: operation).value
            guard !Task.isCancelled else { return }
            apply(result)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
