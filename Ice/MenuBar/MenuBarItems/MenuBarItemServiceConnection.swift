//
//  MenuBarItemServiceConnection.swift
//  Ice
//

import Foundation
import OSLog

// MARK: - MenuBarItemService.Connection

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A connection to the `MenuBarItemService` XPC service.
    final class Connection: Sendable {
        /// The shared connection.
        static let shared = Connection()

        /// The connection's underlying session.
        private let session: Session

        /// The connection's target queue.
        private let queue: DispatchQueue

        /// The connection's logger.
        private let logger: Logger

        /// Creates a new connection.
        private init() {
            let queue = DispatchQueue.targetingGlobal(
                label: "MenuBarItemService.Connection.queue",
                qos: .userInteractive,
                attributes: .concurrent
            )
            let logger = Logger(category: "MenuBarItemService.Connection")
            self.session = Session(queue: queue, logger: logger)
            self.queue = queue
            self.logger = logger
        }

        /// Starts the connection.
        func start() async {
            logger.debug("Starting MenuBarItemService connection")

            await withCheckedContinuation { continuation in
                guard let response = session.send(request: .start) else {
                    logger.error("Start request returned nil")
                    continuation.resume()
                    return
                }
                if case .start = response {
                    continuation.resume()
                } else {
                    logger.error("Start request returned invalid response \(String(describing: response))")
                    continuation.resume()
                }
            }
        }

        /// Returns the source process identifier for the given window.
        func sourcePID(for window: WindowInfo) async -> pid_t? {
            await withCheckedContinuation { continuation in
                guard let response = session.send(request: .sourcePID(window)) else {
                    logger.error("Source PID request returned nil")
                    continuation.resume(returning: nil)
                    return
                }
                if case .sourcePID(let pid) = response {
                    continuation.resume(returning: pid)
                } else {
                    logger.error("Source PID request returned invalid response \(String(describing: response))")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - MenuBarItemService.Session

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A wrapper around an XPC session.
    private final class Session: Sendable {
        /// A session's underlying storage.
        private final class Storage: @unchecked Sendable {
            struct SessionHandle: @unchecked Sendable {
                let id: UUID
                let session: XPCSession
            }

            private let name = MenuBarItemService.name
            private var session: XPCSession?
            private var sessionID: UUID?
            private let queue: DispatchQueue
            private let blockingQueue: DispatchQueue
            private let logger: Logger
            private let lock = NSLock()

            init(queue: DispatchQueue, logger: Logger) {
                self.queue = queue
                self.logger = logger
                self.blockingQueue = DispatchQueue(
                    label: "com.jordanbaird.Ice.MenuBarItemService.sendSync",
                    qos: .userInitiated,
                    attributes: .concurrent
                )
            }

            private func getOrCreateSession() throws -> SessionHandle {
                lock.lock()
                defer { lock.unlock() }
                if let session, let sessionID {
                    return SessionHandle(id: sessionID, session: session)
                }
                let id = UUID()
                let session = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                    guard let self else {
                        return
                    }
                    logger.warning("Session was cancelled with error \(error.localizedDescription)")
                    clearSession(id: id)
                }
                // Same logic as MenuBarItemService/Listener.swift's listener-side
                // guard: only enforce `.isFromSameTeam()` when we actually have
                // a team identifier. Ad-hoc-signed builds (every community fork
                // without an Apple Developer Program account) have no team
                // identifier and would silently reject our own helper service
                // — making the Menu Bar Layout pane spin forever on
                // "Loading menu bar items…" (upstream issues #744 and #891).
                if MenuBarItemService.ownTeamIdentifier() != nil {
                    session.setPeerRequirement(.isFromSameTeam())
                }
                session.setTargetQueue(queue)
                try session.activate()
                self.session = session
                sessionID = id
                return SessionHandle(id: id, session: session)
            }

            func cancel(reason: String) {
                lock.lock()
                let current = session.map { SessionHandle(id: sessionID ?? UUID(), session: $0) }
                session = nil
                sessionID = nil
                lock.unlock()
                current?.session.cancel(reason: reason)
            }

            func send(request: Request) -> Response? {
                do {
                    let handle = try getOrCreateSession()
                    do {
                        return try XPCSyncDeadline.send(
                            request,
                            as: Response.self,
                            through: handle.session,
                            timeout: 5,
                            queue: blockingQueue
                        ) { [weak self] in
                            self?.cancelSession(handle, reason: "MenuBarItemService sendSync deadline exceeded")
                        }
                    } catch {
                        clearSession(id: handle.id)
                        throw error
                    }
                } catch {
                    logger.error("Session failed with error \(error)")
                    return nil
                }
            }

            private func clearSession(id: UUID) {
                lock.lock()
                defer { lock.unlock() }
                guard sessionID == id else { return }
                session = nil
                sessionID = nil
            }

            private func cancelSession(_ handle: SessionHandle, reason: String) {
                clearSession(id: handle.id)
                handle.session.cancel(reason: reason)
            }
        }

        /// Storage protects only session creation/replacement. The blocking
        /// send never holds that lock, so a deadline can cancel concurrently.
        private let storage: Storage

        /// The session's target queue.
        private let queue: DispatchQueue

        /// The session's logger.
        private let logger: Logger

        /// Creates a new session.
        init(queue: DispatchQueue, logger: Logger) {
            self.storage = Storage(queue: queue, logger: logger)
            self.queue = queue
            self.logger = logger
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        /// Cancels the session.
        func cancel(reason: String) {
            storage.cancel(reason: reason)
        }

        /// Sends the given request to the service and returns the response.
        func send(request: Request) -> Response? {
            storage.send(request: request)
        }
    }
}
