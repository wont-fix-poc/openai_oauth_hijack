import Foundation
import Network

final class LocalHTTPServer {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private(set) var port: UInt16 = 0
    private(set) var isRunning = false

    var onPortAssigned: ((UInt16) -> Void)?
    var onError: ((Error) -> Void)?

    func start(redirectURL: String) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = listener.port {
                    self?.port = port.rawValue
                    self?.isRunning = true
                    print("NWListener ready on port \(port.rawValue)")
                    DispatchQueue.main.async {
                        self?.onPortAssigned?(port.rawValue)
                    }
                }
            case .failed(let error):
                self?.isRunning = false
                print("NWListener failed: \(error)")
                DispatchQueue.main.async {
                    self?.onError?(error)
                }
            case .cancelled:
                self?.isRunning = false
                print("NWListener cancelled")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn: conn, redirectURL: redirectURL)
        }

        listener.start(queue: .global(qos: .userInitiated))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
        port = 0
    }

    private func handle(conn: NWConnection, redirectURL: String) {
        connections.append(conn)
        conn.start(queue: .global(qos: .userInitiated))

        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let data, let request = String(data: data, encoding: .utf8) else {
                conn.cancel()
                return
            }

            let path = self?.extractPath(from: request) ?? "/"

            var response: String
            if path == "/health" {
                let body = "ok"
                response = "HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n\(body)"
            } else {
                response = "HTTP/1.1 302 Found\r\nLocation: \(redirectURL)\r\nConnection: close\r\n\r\n"
            }

            conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }

    private func extractPath(from request: String) -> String {
        guard let firstLine = request.components(separatedBy: "\r\n").first,
              let path = firstLine.components(separatedBy: " ").dropFirst().first else {
            return "/"
        }
        return path
    }
}
