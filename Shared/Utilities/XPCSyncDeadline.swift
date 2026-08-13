import Foundation

/// Adds a caller-side deadline to macOS 26's blocking `XPCSession.sendSync`,
/// which has no native timeout. The blocking call runs on a dedicated queue;
/// timeout cancellation is invoked from the waiting thread and a late reply is
/// discarded. Callers must not hold their session-state lock while invoking
/// this helper, so `onTimeout` can tear down the exact wedged session.
@available(macOS 26.0, *)
enum XPCSyncDeadline {
    struct TimeoutError: LocalizedError {
        let seconds: TimeInterval

        var errorDescription: String? {
            "XPC request timed out after \(seconds.formatted()) seconds"
        }
    }

    private final class ReplyBox<Value>: @unchecked Sendable {
        private enum State {
            case pending
            case completed(Result<Value, Error>)
            case timedOut
        }

        private let lock = NSLock()
        private var state: State = .pending

        func complete(_ result: Result<Value, Error>) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard case .pending = state else { return false }
            state = .completed(result)
            return true
        }

        func markTimedOut() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard case .pending = state else { return false }
            state = .timedOut
            return true
        }

        func result() -> Result<Value, Error>? {
            lock.lock()
            defer { lock.unlock() }
            guard case .completed(let result) = state else { return nil }
            return result
        }
    }

    static func send<Request: Encodable, Response: Decodable>(
        _ request: Request,
        as _: Response.Type,
        through session: XPCSession,
        timeout: TimeInterval,
        queue: DispatchQueue,
        onTimeout: @escaping @Sendable () -> Void
    ) throws -> Response {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ReplyBox<Response>()

        queue.async {
            let result = Result<Response, Error> {
                let reply = try session.sendSync(request)
                return try reply.decode(as: Response.self)
            }
            if box.complete(result) {
                semaphore.signal()
            }
        }

        if semaphore.wait(timeout: .now() + timeout) == .success,
           let result = box.result()
        {
            return try result.get()
        }

        // A reply can win between `wait` expiring and this state transition.
        // In that case use it; otherwise cancel the exact session and fail.
        if !box.markTimedOut(), let result = box.result() {
            return try result.get()
        }

        onTimeout()
        throw TimeoutError(seconds: timeout)
    }
}
