//
//  FireMCPBridgeServer.swift
//  Ice
//
//  Authenticated local rendezvous for the embedded MCP bridge. A bundled XPC
//  service is scoped to the client process that launched it, so a standalone
//  CLI bridge cannot share MCPBackend's relay queue with the GUI app. This
//  server keeps the bridge outside the app process while forwarding every
//  request through the GUI app's one shared MCPBackend XPC session.
//

import Darwin
import Foundation
import OSLog

@available(macOS 26.0, *)
final class FireMCPBridgeServer: @unchecked Sendable {
    static let shared = FireMCPBridgeServer()

    private struct Reply: Codable {
        let response: MenuBarItemService.Response?
        let error: String?
    }

    private let logger = Logger(category: "FireMCPBridgeServer")
    private let listenerQueue = DispatchQueue(label: "com.jordanbaird.Ice.mcp.socket.listener")
    private let clientQueue = DispatchQueue(
        label: "com.jordanbaird.Ice.mcp.socket.clients",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var listenerFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let relayStateLock = NSLock()
    private var relayReady = false

    private init() {}

    func start() {
        listenerQueue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        listenerQueue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    func markRelayReady() {
        relayStateLock.lock()
        relayReady = true
        relayStateLock.unlock()
    }

    private func startOnQueue() {
        guard listenerFD == -1 else { return }

        let path = MenuBarItemService.bridgeSocketPath
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            logger.error("Could not create MCP bridge socket: errno \(errno)")
            return
        }

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout.size(ofValue: noSigPipe)))
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)

        guard Self.bind(fd, to: path), chmod(path, S_IRUSR | S_IWUSR) == 0, listen(fd, 8) == 0 else {
            logger.error("Could not bind MCP bridge socket: errno \(errno)")
            close(fd)
            unlink(path)
            return
        }

        listenerFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: listenerQueue)
        source.setEventHandler { [weak self] in
            self?.acceptClients()
        }
        self.source = source
        source.activate()
        logger.info("Authenticated MCP bridge socket active")
    }

    private func stopOnQueue() {
        setRelayReady(false)
        source?.cancel()
        source = nil
        if listenerFD >= 0 {
            close(listenerFD)
            listenerFD = -1
        }
        unlink(MenuBarItemService.bridgeSocketPath)
    }

    private func acceptClients() {
        while listenerFD >= 0 {
            let clientFD = accept(listenerFD, nil, nil)
            guard clientFD >= 0 else {
                if errno == EINTR { continue }
                return
            }

            var noSigPipe: Int32 = 1
            _ = setsockopt(
                clientFD,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout.size(ofValue: noSigPipe))
            )
            clientQueue.async { [weak self] in
                self?.handleClient(clientFD)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }

        let expectedBridge = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/IceMCPBridge")
        guard MenuBarItemService.isTrustedSocketPeer(
            fd,
            expectedExecutableURL: expectedBridge
        ) else {
            logger.notice("Rejected unauthenticated MCP bridge socket peer")
            return
        }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count == 0 { return }
            if count < 0 {
                if errno == EINTR { continue }
                return
            }
            buffer.append(contentsOf: chunk.prefix(count))

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard !line.isEmpty else { continue }
                let reply = handleLine(line)
                guard let data = try? JSONEncoder().encode(reply), Self.writeLine(data, to: fd) else {
                    return
                }
            }
        }
    }

    private func handleLine(_ data: Data) -> Reply {
        do {
            let request = try JSONDecoder().decode(MenuBarItemService.Request.self, from: data)
            guard request.isAgentFacing else {
                return Reply(response: .denied("Unsupported bridge request."), error: nil)
            }
            guard !request.requiresMainAppRelay || isRelayReady else {
                return Reply(
                    response: .denied(
                        "Fire is waiting for Accessibility permission and menu-bar setup. "
                            + "Complete the Permissions screen, then retry."
                    ),
                    error: nil
                )
            }
            let response = try MCPBackendXPCClient.agent.send(request)
            return Reply(response: response, error: nil)
        } catch {
            return Reply(response: nil, error: error.localizedDescription)
        }
    }

    private var isRelayReady: Bool {
        relayStateLock.lock()
        defer { relayStateLock.unlock() }
        return relayReady
    }

    private func setRelayReady(_ ready: Bool) {
        relayStateLock.lock()
        relayReady = ready
        relayStateLock.unlock()
    }

    private static func bind(_ fd: Int32, to path: String) -> Bool {
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            return false
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: bytes)
            destination[bytes.count] = 0
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + bytes.count + 1)
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, length) == 0
            }
        }
    }

    private static func writeLine(_ data: Data, to fd: Int32) -> Bool {
        var framed = data
        framed.append(0x0A)
        return framed.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress else { return false }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }
}
