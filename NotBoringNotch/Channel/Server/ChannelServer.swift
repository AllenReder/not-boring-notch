//
//  ChannelServer.swift
//  NotBoringNotch
//
//  The HTTP surface an external process reaches the Notch Channel through: loopback only, token
//  in hand, JSON in the body.
//

import Foundation
import Network

/// Listens on `127.0.0.1` for notifications.
///
/// It is deliberately narrow: a handful of routes, one content type, a bearer token, and no answer
/// beyond "accepted" — a sender is never told what the user did about its notification, and there
/// is nowhere for it to ask.
///
///     POST   /reminder                  v1, kept for the senders written against it
///     POST   /v2/notifications          deliver
///     DELETE /v2/notifications/{id}     withdraw, from the banner and the Inbox alike
///     POST   /v2/agents/{agent}/events  a Claude Code or Codex hook, as the agent posted it
final class ChannelServer {
    enum State {
        case ready(port: UInt16)
        /// A human-readable reason the channel is not listening, for the Settings pane.
        case failed(String)
    }

    /// The state the listener settles into. Called on the listener's own queue.
    var onStateChange: ((State) -> Void)?

    /// Every notification that parsed and authenticated. Called on the listener's own queue.
    var onNotification: ((ChannelNotification) -> Void)?

    /// The id of every notification its sender withdrew. Called on the listener's own queue.
    var onWithdraw: ((String) -> Void)?

    /// Every agent hook that parsed and authenticated, in the order it arrived. Called on the
    /// listener's own queue, before the hook is answered, so a hook that waits for its answer
    /// cannot be overtaken by the next one.
    var onAgentEvent: ((AgentEnvelope) -> Void)?

    // Everything below is touched only on `queue`. `start` and `stop` hop onto it, so the token a
    // request is checked against can never be read halfway through being replaced.
    private let queue = DispatchQueue(label: "com.allenreder.notboringnotch.notch-channel")
    private var listener: NWListener?
    private var token = ""
    private var requestedPort: UInt16 = 0
    /// The connections still being read or answered, so `stop` can end them too.
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// Bumped by every `stop`. A connection accepted under an older generation belongs to a
    /// listener that has been stopped, and nothing it carries is delivered.
    private var generation = 0

    /// How long a peer has to send a whole request. Counting reads alone would let one that sends
    /// a byte and then nothing hold its connection open forever.
    private static let readDeadline: DispatchTimeInterval = .seconds(10)

    /// The body sits inside this, plus room for the request line and headers.
    private static let maximumHeaderBytes = 8 * 1024
    /// An agent hook carries the tool call it reports, whose input can be a whole file being
    /// written. Notifications are text for a person to read; this is not.
    static let maximumAgentPayloadBytes = 4 * 1024 * 1024
    /// Nothing the server accepts is longer than this.
    private static let maximumRequestBytes =
        max(ChannelNotification.maximumPayloadBytes, maximumAgentPayloadBytes) + maximumHeaderBytes
    /// A guard against a peer that dribbles bytes at us forever: past this many reads without a
    /// complete request, we stop listening to it.
    private static let maximumReceives = 4096

    func start(port: UInt16, token: String) {
        queue.sync { startOnQueue(port: port, token: token) }
    }

    func stop() {
        queue.sync { stopOnQueue() }
    }

    private func startOnQueue(port: UInt16, token: String) {
        // Same socket, so there is nothing to rebind. A new Channel Token is not a new socket:
        // keep listening and start refusing the old token instead.
        if listener != nil, requestedPort == port {
            self.token = token
            return
        }

        stopOnQueue()
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
            guard let self, self.listener === listener else {
                connection.cancel()
                return
            }
            self.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            // A listener already replaced has nothing left to report, and stopping on its behalf
            // would stop its successor.
            guard let self, self.listener === listener else { return }
            switch state {
            case .ready:
                // The port the socket actually took, which is what a caller asking for port 0 needs
                // to hear about.
                self.onStateChange?(.ready(port: listener.port?.rawValue ?? port))
            case let .failed(error):
                self.onStateChange?(.failed(Self.stoppedMessage(error, port: port)))
                self.stopOnQueue()
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func stopOnQueue() {
        generation += 1
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }

    /// Why a listener that was running stopped, phrased for the Settings pane.
    private static func stoppedMessage(_ error: NWError, port: UInt16) -> String {
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
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.readDeadline) { [weak self] in
            // Still here means the request never finished arriving.
            guard let self, self.connections[key] != nil else { return }
            self.finish(connection)
        }
        receive(connection, buffer: Data(), receives: 0, generation: generation)
    }

    /// Ends a connection and forgets it.
    private func finish(_ connection: NWConnection) {
        connection.cancel()
        connections[ObjectIdentifier(connection)] = nil
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

    private func receive(_ connection: NWConnection, buffer: Data, receives: Int, generation: Int) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] chunk, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            // Accepted before the channel was stopped or moved: whatever it asks, the answer is
            // no answer.
            guard generation == self.generation else {
                self.finish(connection)
                return
            }

            var buffer = buffer
            if let chunk { buffer.append(chunk) }

            guard buffer.count <= Self.maximumRequestBytes else {
                send(status: 413, reason: "Payload Too Large", json: ["error": "too_large"], on: connection)
                return
            }

            switch progress(for: buffer) {
            case let .respond(response):
                send(response, on: connection)
            case .needMore:
                if isComplete || error != nil {
                    finish(connection)
                } else if receives >= Self.maximumReceives {
                    send(status: 400, reason: "Bad Request", json: ["error": "malformed"], on: connection)
                } else {
                    // Hop through the queue rather than recursing, so a peer that sends one byte
                    // per packet cannot grow the stack.
                    queue.async {
                        self.receive(connection, buffer: buffer, receives: receives + 1, generation: generation)
                    }
                }
            }
        }
    }

    private func send(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            guard let self else {
                connection.cancel()
                return
            }
            self.finish(connection)
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
        let request: Request
        switch parse(buffer) {
        case .incomplete:
            return .needMore
        case let .refused(refusal):
            return refusal
        case let .complete(parsed):
            request = parsed
        }

        guard let route = Route(method: request.method, path: request.path) else {
            return Self.failure(404, "Not Found", "not_found")
        }
        if route == .wrongMethod {
            return Self.failure(405, "Method Not Allowed", "method_not_allowed")
        }
        // A web page in the user's browser can POST to 127.0.0.1 without a preflight, so refuse
        // anything that admits to coming from one.
        if let origin = request.headers["origin"], !origin.isEmpty {
            return Self.failure(403, "Forbidden", "forbidden_origin")
        }
        guard request.headers["authorization"] == "Bearer \(token)", !token.isEmpty else {
            return Self.failure(401, "Unauthorized", "unauthorized")
        }

        switch route {
        case let .withdraw(id):
            // Idempotent, as DELETE should be: withdrawing what is already gone is not an error,
            // and the sender cannot know what the user has already cleared.
            onWithdraw?(id)
            return .respond(Self.response(status: 200, reason: "OK",
                                         json: ["status": "withdrawn", "id": id]))
        case let .agentEvent(agent):
            if let refusal = Self.refusingBody(of: request) { return refusal }

            do {
                guard let envelope = try AgentAdapter.envelope(agent: agent, payload: request.body,
                                                               headers: request.headers) else {
                    // A hook this version does not know is not the sender's mistake.
                    return .respond(Self.response(status: 202, reason: "Accepted", json: ["status": "ignored"]))
                }
                onAgentEvent?(envelope)
                return .respond(Self.response(status: 202, reason: "Accepted", json: ["status": "accepted"]))
            } catch AgentAdapterError.missingSessionID {
                return Self.failure(400, "Bad Request", "missing_session_id")
            } catch {
                return Self.failure(400, "Bad Request", "malformed")
            }
        case .deliverV1, .deliver:
            if let refusal = Self.refusingBody(of: request) { return refusal }

            do {
                let notification = route == .deliverV1
                    ? try ChannelNotification.decodeV1(request.body)
                    : try ChannelNotification.decode(request.body)
                onNotification?(notification)
                return .respond(Self.response(status: 202, reason: "Accepted",
                                             json: ["status": "queued", "id": notification.id]))
            } catch let error as ChannelPayloadError {
                return .respond(Self.describe(error))
            } catch {
                return Self.failure(400, "Bad Request", "malformed")
            }
        case .wrongMethod:
            return Self.failure(405, "Method Not Allowed", "method_not_allowed")
        }
    }

    /// The refusal a request carrying a body earns before the body is read, if any.
    private static func refusingBody(of request: Request) -> Progress? {
        // Requiring JSON is not decoration: a browser sending it must preflight first, and the
        // channel does not answer preflights.
        guard isJSON(request.headers["content-type"]) else {
            return failure(415, "Unsupported Media Type", "unsupported_media_type")
        }
        guard request.contentLength != nil else {
            return failure(411, "Length Required", "length_required")
        }
        return nil
    }

    /// What a request asks for, read from its method and path alone.
    private enum Route: Equatable {
        case deliverV1
        case deliver
        case withdraw(id: String)
        case agentEvent(AgentKind)
        /// A path the channel serves, with a method it does not take there.
        case wrongMethod

        static let notificationsPath = "/v2/notifications"
        static let agentsPath = "/v2/agents"

        /// The largest body the route accepts.
        var maximumBodyBytes: Int {
            if case .agentEvent = self { return ChannelServer.maximumAgentPayloadBytes }
            return ChannelNotification.maximumPayloadBytes
        }

        /// Nil for a path the channel does not serve at all.
        init?(method: String, path rawPath: String) {
            // A query string means nothing here, but should not turn a known path into a 404.
            let path = String(rawPath.split(separator: "?", maxSplits: 1,
                                             omittingEmptySubsequences: false)[0])

            if path == "/reminder" {
                self = method == "POST" ? .deliverV1 : .wrongMethod
            } else if path == Self.notificationsPath {
                self = method == "POST" ? .deliver : .wrongMethod
            } else if path.hasPrefix(Self.notificationsPath + "/") {
                guard let id = Self.id(String(path.dropFirst(Self.notificationsPath.count + 1))) else {
                    return nil
                }
                self = method == "DELETE" ? .withdraw(id: id) : .wrongMethod
            } else if path.hasPrefix(Self.agentsPath + "/") {
                // /v2/agents/{agent}/events, and nothing else under /v2/agents.
                let parts = path.dropFirst(Self.agentsPath.count + 1).split(separator: "/", omittingEmptySubsequences: false)
                guard parts.count == 2, parts[1] == "events", let agent = AgentKind(rawValue: String(parts[0])) else {
                    return nil
                }
                self = method == "POST" ? .agentEvent(agent) : .wrongMethod
            } else {
                return nil
            }
        }

        /// One percent-encoded path segment, decoded. An id containing `/` arrives as `%2F`.
        private static func id(_ encoded: String) -> String? {
            guard !encoded.isEmpty, !encoded.contains("/"),
                  let id = encoded.removingPercentEncoding, !id.isEmpty else {
                return nil
            }
            return id
        }
    }

    private static func failure(_ status: Int, _ reason: String, _ code: String) -> Progress {
        .respond(response(status: status, reason: reason, json: ["error": code]))
    }

    /// `application/json`, optionally with parameters (`; charset=utf-8`). Not
    /// `application/jsonp`, which a prefix match would have accepted.
    private static func isJSON(_ contentType: String?) -> Bool {
        guard let contentType else { return false }
        let mediaType = contentType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return mediaType == "application/json"
    }

    /// The refusal a payload problem earns: a code for the sender, naming the offending value
    /// when there is one to name. Only one of these is about size rather than content.
    private static func describe(_ error: ChannelPayloadError) -> Data {
        var json = ["error": error.code]
        switch error {
        case let .unknownIconKind(kind):
            json["kind"] = kind
        case let .unknownSound(sound):
            json["sound"] = sound
        case let .unknownLevel(level):
            json["level"] = level
        default:
            break
        }

        guard case .tooLarge = error else {
            return response(status: 400, reason: "Bad Request", json: json)
        }
        return response(status: 413, reason: "Payload Too Large", json: json)
    }

    private enum Parsed {
        /// The headers, or the body they announce, have not arrived in full yet.
        case incomplete
        /// The framing itself is wrong, so there is no request to route.
        case refused(Progress)
        case complete(Request)
    }

    /// Reads as much of a request as has arrived.
    ///
    /// The framing is settled the moment the headers are complete, before any body is waited for:
    /// a length that cannot be a length, two lengths that disagree, or a transfer encoding we do
    /// not speak is refused, and a body announced as too large is refused without reading it.
    private func parse(_ buffer: Data) -> Parsed {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            // Headers that go on past any sensible length are not going to end.
            return buffer.count > Self.maximumHeaderBytes
                ? .refused(Self.failure(413, "Payload Too Large", "too_large"))
                : .incomplete
        }

        let headerText = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
        var lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.isEmpty ? [] : lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else {
            return .refused(Self.failure(400, "Bad Request", "malformed"))
        }

        var headers: [String: String] = [:]
        var lengths: Set<String> = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "content-length" { lengths.insert(value) }
            headers[name] = value
        }

        guard headers["transfer-encoding"] == nil, lengths.count <= 1 else {
            return .refused(Self.failure(400, "Bad Request", "malformed"))
        }
        var contentLength: Int?
        if let declared = lengths.first {
            // Digits only: `Int("-1")` and `Int("+1")` both parse, and neither is a length.
            guard !declared.isEmpty, declared.allSatisfy(\.isASCII), declared.allSatisfy(\.isNumber),
                  let length = Int(declared) else {
                return .refused(Self.failure(400, "Bad Request", "malformed"))
            }
            let route = Route(method: String(requestLine[0]), path: String(requestLine[1]))
            guard length <= (route?.maximumBodyBytes ?? ChannelNotification.maximumPayloadBytes) else {
                return .refused(Self.failure(413, "Payload Too Large", "too_large"))
            }
            contentLength = length
        }

        let bodyStart = headerEnd.upperBound
        let declaredLength = contentLength ?? 0
        guard buffer.count - bodyStart >= declaredLength else { return .incomplete }

        return .complete(Request(method: String(requestLine[0]),
                                 path: String(requestLine[1]),
                                 headers: headers,
                                 contentLength: contentLength,
                                 body: buffer[bodyStart ..< bodyStart + declaredLength]))
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
