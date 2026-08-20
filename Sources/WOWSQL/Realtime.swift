import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Browser-safe realtime URL. Auth is always `?apikey=`.
public func buildRealtimeWebSocketUrl(projectUrl: String, apiKey: String) -> String {
    var origin = projectUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if origin.hasPrefix("https://") {
        origin = "wss://" + origin.dropFirst("https://".count)
    } else if origin.hasPrefix("http://") {
        origin = "ws://" + origin.dropFirst("http://".count)
    }
    let encoded = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
    return "\(origin)/realtime/v1/websocket?apikey=\(encoded)"
}

public struct RealtimeChange {
    public let event: String
    public let schema: String
    public let table: String
    public let newRow: [String: Any]?
    public let oldRow: [String: Any]?
    public let payload: [String: Any]
}

public final class WowSQLRealtime {
    let projectUrl: String
    let apiKey: String
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var manualClose = false
    private var subs: [(schema: String, table: String, event: String, cb: (RealtimeChange) -> Void)] = []
    var channels: [String: RealtimeChannel] = [:]

    public init(projectUrl: String, apiKey: String) {
        self.projectUrl = projectUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
    }

    public var url: String { buildRealtimeWebSocketUrl(projectUrl: projectUrl, apiKey: apiKey) }

    public func channel(_ name: String) -> RealtimeChannel {
        if let existing = channels[name] { return existing }
        let ch = RealtimeChannel(rt: self, name: name)
        channels[name] = ch
        return ch
    }

    @discardableResult
    public func subscribe(table: String, schema: String = "public", event: String = "*", callback: @escaping (RealtimeChange) -> Void) -> () -> Void {
        let item = (schema, table, event, callback)
        subs.append(item)
        ensureConnected()
        send(["type": "subscribe", "schema": schema, "table": table, "event": event])
        return { [weak self] in
            self?.subs.removeAll { $0.table == table && $0.schema == schema }
            self?.send(["type": "unsubscribe", "schema": schema, "table": table])
        }
    }

    public func disconnect() {
        manualClose = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    func ensureConnected() {
        if task != nil { return }
        manualClose = false
        guard let u = URL(string: url) else { return }
        task = session.webSocketTask(with: u)
        task?.resume()
        for s in subs {
            send(["type": "subscribe", "schema": s.schema, "table": s.table, "event": s.event])
        }
        channels.values.forEach { $0.rejoin() }
        listen()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.task = nil
                if !self.manualClose && (!self.subs.isEmpty || !self.channels.isEmpty) {
                    self.ensureConnected()
                }
            case .success(let message):
                if case .string(let text) = message { self.handle(text) }
                self.listen()
            }
        }
    }

    private func handle(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let name = message["channel"] as? String { channels[name]?.handleServer(message) }
        guard (message["type"] as? String) == "broadcast" else { return }
        if message["channel"] != nil && message["table"] == nil { return }
        let nested = message["payload"] as? [String: Any] ?? [:]
        let event = ((message["event"] as? String) ?? (nested["type"] as? String) ?? "").uppercased()
        let schema = (message["schema"] as? String) ?? (nested["schema"] as? String) ?? "public"
        let table = (message["table"] as? String) ?? (nested["table"] as? String) ?? ""
        guard !table.isEmpty, ["INSERT", "UPDATE", "DELETE"].contains(event) else { return }
        let change = RealtimeChange(
            event: event, schema: schema, table: table,
            newRow: nested["new"] as? [String: Any],
            oldRow: nested["old"] as? [String: Any],
            payload: nested
        )
        for s in subs where s.schema == schema && s.table == table && (s.event == "*" || s.event.uppercased() == event) {
            s.cb(change)
        }
    }
}

public final class RealtimeChannel {
    let rt: WowSQLRealtime
    public let name: String
    private var joined = false
    private var state: [String: Any] = [:]
    private var broadcast: [([String: Any]) -> Void] = []
    private var presence: [([String: Any]) -> Void] = []
    private var tracked: [String: Any]?

    init(rt: WowSQLRealtime, name: String) {
        self.rt = rt
        self.name = name
    }

    @discardableResult
    public func onBroadcast(event: String, _ cb: @escaping ([String: Any]) -> Void) -> RealtimeChannel {
        broadcast.append { msg in
            if event == "*" || event == (msg["event"] as? String) { cb(msg) }
        }
        return self
    }

    @discardableResult
    public func onPresence(_ cb: @escaping ([String: Any]) -> Void) -> RealtimeChannel {
        presence.append(cb)
        return self
    }

    @discardableResult
    public func subscribe(_ onStatus: ((String) -> Void)? = nil) -> RealtimeChannel {
        rt.ensureConnected()
        rt.send(["type": "join", "channel": name])
        joined = true
        onStatus?("SUBSCRIBED")
        return self
    }

    public func send(event: String, payload: [String: Any] = [:]) {
        rt.ensureConnected()
        if !joined { rt.send(["type": "join", "channel": name]); joined = true }
        rt.send(["type": "broadcast", "channel": name, "event": event, "payload": payload])
    }

    public func track(_ payload: [String: Any]) {
        tracked = payload
        rt.ensureConnected()
        if !joined { rt.send(["type": "join", "channel": name]); joined = true }
        rt.send(["type": "presence", "event": "track", "channel": name, "payload": payload])
    }

    public func presenceState() -> [String: Any] { state }

    public func unsubscribe() {
        rt.send(["type": "leave", "channel": name])
        joined = false
        rt.channels.removeValue(forKey: name)
    }

    func rejoin() {
        rt.send(["type": "join", "channel": name])
        if let tracked { rt.send(["type": "presence", "event": "track", "channel": name, "payload": tracked]) }
    }

    func handleServer(_ message: [String: Any]) {
        switch message["type"] as? String {
        case "joined": joined = true
        case "presence":
            let event = message["event"] as? String
            if event == "sync", let st = message["state"] as? [String: Any] { state = st }
            else if event == "join", let key = message["key"] as? String { state[key] = message["payload"] }
            else if event == "leave", let key = message["key"] as? String { state.removeValue(forKey: key) }
            presence.forEach { $0(message) }
        case "broadcast":
            let wrapped: [String: Any] = [
                "event": message["event"] ?? "",
                "payload": message["payload"] ?? [:],
                "channel": name
            ]
            broadcast.forEach { $0(wrapped) }
        default: break
        }
    }
}
