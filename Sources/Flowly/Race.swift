import Foundation

struct TimeoutError: Error, LocalizedError { var errorDescription: String? { "timed out" } }

private final class Once {
    private var done = false; private let l = NSLock()
    func take() -> Bool { l.lock(); defer { l.unlock() }; if done { return false }; done = true; return true }
}

/// A *real* timeout: returns/throws as soon as either the work finishes or the clock runs out, without waiting for
/// work that ignores cancellation (e.g. an on-device model call). The straggler is cancelled and its result ignored.
func raceTimeout<T>(_ seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { cont in
        let once = Once()
        let work = Task {
            do { let v = try await op(); if once.take() { cont.resume(returning: v) } }
            catch { if once.take() { cont.resume(throwing: error) } }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if once.take() { work.cancel(); cont.resume(throwing: TimeoutError()) }
        }
    }
}

/// Sleep that ignores cancellation (test hook for simulating a hung engine).
func uncancellableSleep(_ s: Double) async {
    await withCheckedContinuation { c in DispatchQueue.global().asyncAfter(deadline: .now() + s) { c.resume() } }
}
