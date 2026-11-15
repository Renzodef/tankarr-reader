import Foundation

/// Queue before starting URLSession's timeout. Off-screen requests leave the queue
/// immediately, and covers cannot consume the connections needed by navigation.
public actor ReaderRequestGate {
    private var available: Int
    private var waiting: [(UUID, CheckedContinuation<Void, Error>)] = []

    public init(limit: Int) { precondition(limit > 0); available = limit }

    public func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if available > 0 { available -= 1; return }
            try await withCheckedThrowingContinuation { continuation in
                waiting.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    public func release() {
        if waiting.isEmpty { available += 1 }
        else { waiting.removeFirst().1.resume() }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.0 == id }) else { return }
        waiting.remove(at: index).1.resume(throwing: CancellationError())
    }
}
