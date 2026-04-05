import Foundation
import Network

/// Minimal HTTP/1.1 server that serves a single file with byte-range support.
/// Used to serve transcoded audio to the Cast receiver over the local network.
final class LocalAudioServer {

    private var listener: NWListener?
    private var fileURL: URL?
    private var mimeType: String = "audio/mp4"
    private let queue = DispatchQueue(label: "com.dropplayer.audioserver", qos: .userInitiated)

    /// The port the server is listening on. Zero until the server is ready.
    private(set) var port: UInt16 = 0

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else { return }
        listener = l
        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.port = l.port?.rawValue ?? 0 }
        }
        l.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        l.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Replace the file to be served. In-flight requests continue reading the old file handle.
    func serve(fileAt url: URL, mimeType: String) {
        self.fileURL = url
        self.mimeType = mimeType
    }

    // MARK: - HTTP connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else { connection.cancel(); return }
            self.respond(to: String(data: data, encoding: .utf8) ?? "", on: connection)
        }
    }

    private func respond(to request: String, on connection: NWConnection) {
        guard let url = fileURL,
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > 0 else {
            let r = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: r.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        // Parse optional Range header
        var start = 0, end = size - 1, isRange = false
        for line in request.components(separatedBy: "\r\n") {
            guard line.lowercased().hasPrefix("range:") else { continue }
            let v = line.dropFirst(6).trimmingCharacters(in: .whitespaces).lowercased()
            guard v.hasPrefix("bytes=") else { continue }
            let parts = v.dropFirst(6).split(separator: "-")
            if let s = Int(parts[0]) { start = s; isRange = true }
            if parts.count > 1, let e = Int(parts[1]) { end = min(e, size - 1) }
        }

        let length = end - start + 1
        let status = isRange ? "HTTP/1.1 206 Partial Content" : "HTTP/1.1 200 OK"
        var hdr = "\(status)\r\nContent-Type: \(mimeType)\r\nContent-Length: \(length)\r\nAccept-Ranges: bytes\r\n"
        if isRange { hdr += "Content-Range: bytes \(start)-\(end)/\(size)\r\n" }
        hdr += "Connection: close\r\n\r\n"

        guard let fh = try? FileHandle(forReadingFrom: url) else { connection.cancel(); return }
        defer { try? fh.close() }
        try? fh.seek(toOffset: UInt64(start))
        let body = fh.readData(ofLength: length)

        var resp = hdr.data(using: .utf8)!
        resp.append(body)
        connection.send(content: resp, completion: .contentProcessed { _ in connection.cancel() })
    }
}
