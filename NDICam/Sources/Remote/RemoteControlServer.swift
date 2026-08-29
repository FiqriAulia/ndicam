import Foundation
import Network

/// Tiny opt-in HTTP server for controlling the camera from a desktop browser
/// (e.g. an OBS custom browser dock). No third-party code, no dependencies, and
/// nothing runs unless the user turns it on in Settings.
///
/// Routes:
///   GET  /            → control page (single self-contained HTML file)
///   GET  /state       → { "state": CameraControlState, "ranges": CameraControlRanges }
///   POST /control     → body = CameraControlState JSON, applied live
///   POST /broadcast   → toggle NDI on/off
///   POST /camera      → flip front/back
final class RemoteControlServer: @unchecked Sendable {

    private let queue = DispatchQueue(label: "ndicam.remote")
    private var listener: NWListener?

    private let controls: CameraControlling
    private let onApply: @Sendable (CameraControlState) -> Void
    private let onToggleBroadcast: @Sendable () -> Void
    private let onSwitchCamera: @Sendable () -> Void

    private let lock = NSLock()
    private var current = CameraControlState()

    init(controls: CameraControlling,
         initial: CameraControlState,
         onApply: @escaping @Sendable (CameraControlState) -> Void,
         onToggleBroadcast: @escaping @Sendable () -> Void,
         onSwitchCamera: @escaping @Sendable () -> Void) {
        self.controls = controls
        self.current = initial
        self.onApply = onApply
        self.onToggleBroadcast = onToggleBroadcast
        self.onSwitchCamera = onSwitchCamera
    }

    /// Push the latest on-device state so `/state` stays in sync.
    func update(_ s: CameraControlState) {
        lock.lock(); current = s; lock.unlock()
    }

    func start(urlHandler: @escaping @Sendable (String?) -> Void) {
        // Prefer the well-known port (stable dock URL); if it is stuck from a
        // previous run, fall back to an OS-assigned free port.
        bind(port: 8723, allowFallback: true, urlHandler: urlHandler)
    }

    private func bind(port: UInt16, allowFallback: Bool,
                      urlHandler: @escaping @Sendable (String?) -> Void) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            if port == 0 {
                listener = try NWListener(using: params)
            } else {
                listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            }
        } catch {
            if allowFallback { bind(port: 0, allowFallback: false, urlHandler: urlHandler) }
            else { urlHandler(nil) }
            return
        }

        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                if let p = listener?.port?.rawValue, p != 0 {
                    urlHandler(Self.localURL(port: p))
                }
            case .failed:
                listener?.cancel()
                if allowFallback {
                    self?.bind(port: 0, allowFallback: false, urlHandler: urlHandler)
                } else {
                    urlHandler(nil)
                }
            case .cancelled:
                break
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(conn, buffer: Data())
    }

    private func receiveRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }

            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if error != nil || isComplete { conn.cancel() }
                else { self.receiveRequest(conn, buffer: buffer) }
                return
            }

            let header = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            let lines = header.split(separator: "\r\n")
            guard let requestLine = lines.first else { conn.cancel(); return }
            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2 else { conn.cancel(); return }
            let method = String(parts[0]), path = String(parts[1])

            let contentLength = lines.first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            let bodySoFar = buffer[headerEnd.upperBound...]

            if bodySoFar.count < contentLength {
                self.receiveRequest(conn, buffer: buffer)
                return
            }
            let body = Data(bodySoFar.prefix(contentLength))
            self.respond(conn, method: method, path: path, body: body)
        }
    }

    private func respond(_ conn: NWConnection, method: String, path: String, body: Data) {
        switch (method, path) {
        case ("GET", "/"):
            send(conn, status: "200 OK", contentType: "text/html; charset=utf-8",
                 body: Data(Self.page.utf8))

        case ("GET", "/state"):
            lock.lock(); let snap = current; lock.unlock()
            let payload = StatePayload(state: snap, ranges: controls.cameraControlRanges)
            let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
            send(conn, status: "200 OK", contentType: "application/json", body: data)

        case ("POST", "/control"):
            if let s = try? JSONDecoder().decode(CameraControlState.self, from: body) {
                lock.lock(); current = s; lock.unlock()
                controls.applyCameraControls(s)
                onApply(s)
            }
            send(conn, status: "204 No Content", contentType: "text/plain", body: Data())

        case ("POST", "/broadcast"):
            onToggleBroadcast()
            send(conn, status: "204 No Content", contentType: "text/plain", body: Data())

        case ("POST", "/camera"):
            onSwitchCamera()
            send(conn, status: "204 No Content", contentType: "text/plain", body: Data())

        default:
            send(conn, status: "404 Not Found", contentType: "text/plain", body: Data("not found".utf8))
        }
    }

    private func send(_ conn: NWConnection, status: String, contentType: String, body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Helpers

    private struct StatePayload: Encodable {
        let state: CameraControlState
        let ranges: CameraControlRanges
    }

    private static func localURL(port: UInt16) -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & (IFF_UP | IFF_RUNNING) == (IFF_UP | IFF_RUNNING),
                  let sa = ptr.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if !ip.isEmpty && ip != "127.0.0.1" {
                address = ip
                if name == "en0" { break }
            }
        }
        return address.map { "http://\($0):\(port)" }
    }
}
