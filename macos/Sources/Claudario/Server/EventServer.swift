import Foundation
import Network

final class EventServer {
    private let router: EventRouter
    private let queue = DispatchQueue(label: "claudario.server")
    private var listener: NWListener?

    init(router: EventRouter) {
        self.router = router
    }

    func start(preferredPort: UInt16, onReady: @escaping (UInt16) -> Void) {
        let make: (UInt16?) -> NWListener? = { port in
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            params.allowLocalEndpointReuse = true
            do {
                if let p = port, let nw = NWEndpoint.Port(rawValue: p) {
                    return try NWListener(using: params, on: nw)
                } else {
                    return try NWListener(using: params)
                }
            } catch {
                NSLog("Claudario: NWListener init failed for port \(port ?? 0): \(error)")
                return nil
            }
        }

        let lis = make(preferredPort) ?? make(nil)
        guard let listener = lis else {
            NSLog("Claudario: failed to bind any port")
            return
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let port = listener.port?.rawValue ?? preferredPort
                DispatchQueue.main.async { onReady(port) }
            case .failed(let err):
                NSLog("Claudario: listener failed: \(err)")
            default: break
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(on: conn, buffer: Data())
    }

    private func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buf = buffer
            if let d = data { buf.append(d) }
            if error != nil {
                conn.cancel()
                return
            }
            if let body = self.tryParseRequest(buf) {
                self.respond(conn, body: body)
            } else if isComplete {
                conn.cancel()
            } else if buf.count > 256 * 1024 {
                conn.cancel()
            } else {
                self.receive(on: conn, buffer: buf)
            }
        }
    }

    private func tryParseRequest(_ buf: Data) -> Data? {
        let separator = Data("\r\n\r\n".utf8)
        guard let sepRange = buf.range(of: separator) else { return nil }
        let headerData = buf.subdata(in: 0..<sepRange.lowerBound)
        let header = String(data: headerData, encoding: .utf8) ?? ""
        var contentLength = 0
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].lowercased().trimmingCharacters(in: .whitespaces) == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = sepRange.upperBound
        let available = buf.count - bodyStart
        if available < contentLength { return nil }
        return buf.subdata(in: bodyStart..<(bodyStart + contentLength))
    }

    private func respond(_ conn: NWConnection, body: Data) {
        if !body.isEmpty {
            router.handle(body)
        }
        let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
