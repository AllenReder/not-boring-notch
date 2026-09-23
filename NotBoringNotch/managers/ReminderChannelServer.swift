//
//  ReminderChannelServer.swift
//  NotBoringNotch
//
//  The HTTP surface an external process delivers a Reminder through: loopback only, token in
//  hand, JSON in the body. See docs/adr/0007-the-reminder-channel-is-a-tokened-loopback-http-port.md.
//

import Foundation
import Network

/// Listens on `127.0.0.1` for Reminders.
///
/// It is deliberately narrow: one route, one method, one content type, a bearer token, and no
/// answer beyond "accepted" — a sender is never told what the user did about its Reminder, and
/// there is nowhere for it to ask.
final class ReminderChannelServer {
    enum State {
        case ready(port: UInt16)
        /// A human-readable reason the channel is not listening, for the Settings pane.
        case failed(String)
    }

    /// The state the listener settles into. Called on the listener's own queue.
    var onStateChange: ((State) -> Void)?

    /// Every Reminder that parsed and authenticated. Called on the listener's own queue.
    var onReminder: ((Reminder) -> Void)?

    private let queue = DispatchQueue(label: "com.allenreder.notboringnotch.reminder-channel")
    private var listener: NWListener?
    private var token = ""
    private var requestedPort: UInt16 = 0

    /// The body sits inside this, plus room for the request line and headers.
    private static let maximumHeaderBytes = 8 * 1024
    /// A guard against a peer that dribbles bytes at us forever: past this many reads without a
    /// complete request, we stop listening to it.
    private static let maximumReceives = 512

    func start(port: UInt16, token: String) {
        stop()
        self.token = token
        self.requestedPort = port

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Loopback twice over — the bind address and the interface — because a channel that is
        // reachable from the network is a channel the token is doing too much work for.
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback),
                                                    port: NWEndpoint.Port(rawValue: port) ?? .any)

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            onStateChange?(.failed("The channel could not listen on port \(port): \(error.localizedDescription)"))
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onStateChange?(.ready(port: port))
            case let .failed(error):
                self.onStateChange?(.failed(Self.describe(error, port: port)))
                self.stop()
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static func describe(_ error: NWError, port: UInt16) -> String {
        if case let .posix(code) = error, code == .EADDRINUSE {
            return "Port \(port) is already in use. Choose another port below."
        }
        return "The channel stopped listening on port \(port): \(error)"
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        // The bind address is loopback, so this should never fire. It is here because the whole
        // point of this server is that the network cannot reach it.
        guard isLoopback(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data(), receives: 0)
    }

    private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case let .ipv4(address):
            return address.isLoopback
        case let .ipv6(address):
            return address.isLoopback
        case let .name(name, _):
            return name == "localhost"
        @unknown default:
            return false
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data, receives: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] chunk, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var buffer = buffer
            if let chunk { buffer.append(chunk) }

            guard buffer.count <= Reminder.maximumPayloadBytes + Self.maximumHeaderBytes else {
                send(status: 413, reason: "Payload Too Large", json: ["error": "too_large"], on: connection)
                return
            }

            switch progress(for: buffer) {
            case let .respond(response):
                send(response, on: connection)
            case .needMore:
                if isComplete || error != nil {
                    connection.cancel()
                } else if receives >= Self.maximumReceives {
                    send(status: 400, reason: "Bad Request", json: ["error": "malformed"], on: connection)
                } else {
                    // Hop through the queue rather than recursing, so a peer that sends one byte
                    // per packet cannot grow the stack.
                    queue.async { self.receive(connection, buffer: buffer, receives: receives + 1) }
                }
            }
        }
    }

    private func send(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Requests

    private enum Progress {
        /// The request has not arrived in full yet.
        case needMore
        case respond(Data)
    }

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let contentLength: Int?
        let body: Data
    }

    private func progress(for buffer: Data) -> Progress {
        guard let request = parse(buffer) else {
            return .needMore
        }

        guard request.method == "POST" else {
            return Self.failure(405, "Method Not Allowed", "method_not_allowed")
        }
        guard request.path == "/reminder" else {
            return Self.failure(404, "Not Found", "not_found")
        }
        // A web page in the user's browser can POST to 127.0.0.1 without a preflight, so refuse
        // anything that admits to coming from one.
        if let origin = request.headers["origin"], !origin.isEmpty {
            return Self.failure(403, "Forbidden", "forbidden_origin")
        }
        guard request.headers["authorization"] == "Bearer \(token)", !token.isEmpty else {
            return Self.failure(401, "Unauthorized", "unauthorized")
        }
        // Requiring JSON is not decoration: a browser sending it must preflight first, and the
        // channel does not answer preflights.
        guard (request.headers["content-type"] ?? "").lowercased().hasPrefix("application/json") else {
            return Self.failure(415, "Unsupported Media Type", "unsupported_media_type")
        }
        guard request.contentLength != nil else {
            return Self.failure(411, "Length Required", "length_required")
        }

        do {
            let reminder = try Reminder.decode(request.body)
            onReminder?(reminder)
            return .respond(Self.response(status: 202, reason: "Accepted",
                                         json: ["status": "queued", "id": reminder.id]))
        } catch let error as ReminderPayloadError {
            return .respond(Self.describe(error))
        } catch {
            return Self.failure(400, "Bad Request", "malformed")
        }
    }

    private static func failure(_ status: Int, _ reason: String, _ code: String) -> Progress {
        .respond(response(status: status, reason: reason, json: ["error": code]))
    }

    private static func describe(_ error: ReminderPayloadError) -> Data {
        switch error {
        case .tooLarge:
            return response(status: 413, reason: "Payload Too Large", json: ["error": "too_large"])
        case .malformed:
            return response(status: 400, reason: "Bad Request", json: ["error": "malformed"])
        case .missingTitle:
            return response(status: 400, reason: "Bad Request", json: ["error": "missing_title"])
        case let .unknownIconKind(kind):
            return response(status: 400, reason: "Bad Request",
                            json: ["error": "unknown_icon_kind", "kind": kind])
        case .invalidIconData:
            return response(status: 400, reason: "Bad Request", json: ["error": "invalid_icon_data"])
        case let .unknownSound(sound):
            return response(status: 400, reason: "Bad Request",
                            json: ["error": "unknown_sound", "sound": sound])
        case .invalidAction:
            return response(status: 400, reason: "Bad Request", json: ["error": "invalid_action"])
        }
    }

    /// Reads as much of a request as has arrived, or nil if it is still incomplete.
    private func parse(_ buffer: Data) -> Request? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }

        let headerText = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = headers["content-length"].flatMap(Int.init)
        let bodyStart = headerEnd.upperBound
        let declaredLength = contentLength ?? 0
        guard buffer.count - bodyStart >= declaredLength else { return nil }

        return Request(method: String(requestLine[0]),
                       path: String(requestLine[1]),
                       headers: headers,
                       contentLength: contentLength,
                       body: buffer[bodyStart ..< bodyStart + declaredLength])
    }

    private func send(status: Int, reason: String, json: [String: String], on connection: NWConnection) {
        send(Self.response(status: status, reason: reason, json: json), on: connection)
    }

    private static func response(status: Int, reason: String, json: [String: String]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        head += "\r\n"
        return Data(head.utf8) + body
    }
}
