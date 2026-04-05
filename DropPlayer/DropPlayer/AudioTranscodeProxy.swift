import Foundation
import Network
import AVFoundation

// MARK: - AudioTranscodeProxy

/// One-shot HTTP/1.1 server.
/// When the Cast receiver connects it downloads the registered AIFF via URLSession streaming,
/// parses the COMM/SSND chunks on the fly, converts PCM → AAC-LC via AVAudioConverter,
/// wraps each output packet in a 7-byte ADTS header, and sends the result as
/// Transfer-Encoding: chunked so Cast starts playing within seconds.
final class AudioTranscodeProxy {

    // MARK: - Public

    private(set) var port: UInt16 = 0

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else { return }
        listener = l
        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.port = l.port?.rawValue ?? 0 }
        }
        l.newConnectionHandler = { [weak self] conn in
            DispatchQueue.main.async { self?.accept(conn) }
        }
        l.start(queue: serverQueue)
    }

    func stop() {
        activeTask?.cancel()
        listener?.cancel()
        listener = nil
    }

    /// Register the Dropbox URL to transcode for the next incoming connection.
    func serveTranscoded(from url: URL) {
        activeTask?.cancel()
        pendingURL = url
    }

    // MARK: - Private state

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.dropplayer.proxy", qos: .userInitiated)
    private var pendingURL: URL?
    private var activeTask: Task<Void, Never>?

    private func accept(_ connection: NWConnection) {
        guard let url = pendingURL else { connection.cancel(); return }
        connection.start(queue: serverQueue)
        // Drain the HTTP request before replying
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] _, _, _, _ in
            guard let self else { connection.cancel(); return }
            self.activeTask = Task { await self.transcode(from: url, into: connection) }
        }
    }

    // MARK: - Pipeline

    private func transcode(from url: URL, into conn: NWConnection) async {
        do {
            let (asyncBytes, _) = try await URLSession.shared.bytes(from: url)
            let reader = ByteReader(asyncBytes)

            // 1. Parse AIFF/AIFC header
            let info = try await parseAIFF(reader)

            // 2. Build AVAudioConverter: raw PCM → AAC-LC
            let srcFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: info.sampleRate,
                channels: AVAudioChannelCount(info.channels),
                interleaved: false
            )!
            // Cap output sample rate at 48 kHz (Chromecast max for AAC)
            let dstRate = info.sampleRate > 48_000 ? 48_000.0 : info.sampleRate
            guard let dstFormat = AVAudioFormat(settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: dstRate,
                AVNumberOfChannelsKey: info.channels,
                AVEncoderBitRateKey: 320_000
            ]), let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
                throw ProxyError.converterFailed
            }

            // 3. HTTP response headers — live stream, no Content-Length needed
            let hdr = "HTTP/1.1 200 OK\r\nContent-Type: audio/aac\r\nTransfer-Encoding: chunked\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
            try await sendData(hdr.data(using: .utf8)!, on: conn)

            // 4. Stream PCM → AAC in ~4096-sample chunks
            let bps   = (info.bitsPerSample + 7) / 8   // bytes per sample
            let chunkSamples = 4096
            let chunkBytes   = chunkSamples * info.channels * bps
            var buf = [UInt8]()
            buf.reserveCapacity(chunkBytes * 2)
            var eof = false

            while !eof {
                while buf.count < chunkBytes {
                    if let b = try await reader.nextByte() {
                        buf.append(b)
                    } else {
                        eof = true; break
                    }
                }
                let frames = buf.count / (bps * info.channels)
                guard frames > 0 else { break }
                let consume = frames * bps * info.channels
                let slice = Array(buf.prefix(consume))
                buf.removeFirst(consume)

                let adts = encodeToADTS(rawBytes: slice, frames: frames,
                                        info: info, converter: converter, dstFormat: dstFormat)
                if !adts.isEmpty {
                    let chunk = "\(String(adts.count, radix: 16))\r\n".data(using: .utf8)! +
                                adts +
                                "\r\n".data(using: .utf8)!
                    try await sendData(chunk, on: conn)
                }
            }
            // Terminate chunked body
            try await sendData("0\r\n\r\n".data(using: .utf8)!, on: conn)
        } catch {
            print("[AudioTranscodeProxy] \(error)")
        }
        conn.cancel()
    }

    // MARK: - AAC encoder

    private func encodeToADTS(rawBytes: [UInt8], frames: Int,
                               info: AIFFInfo, converter: AVAudioConverter,
                               dstFormat: AVAudioFormat) -> Data {
        let bps = (info.bitsPerSample + 7) / 8
        guard let pcm = AVAudioPCMBuffer(pcmFormat: converter.inputFormat,
                                         frameCapacity: AVAudioFrameCount(frames)) else { return Data() }
        pcm.frameLength = AVAudioFrameCount(frames)

        // Deinterleave raw bytes → planar Float32
        for ch in 0..<info.channels {
            let dst = pcm.floatChannelData![ch]
            for f in 0..<frames {
                let off = (f * info.channels + ch) * bps
                dst[f] = sampleAsFloat(rawBytes, at: off, bits: info.bitsPerSample, bigEndian: info.bigEndian)
            }
        }

        let maxPkt = max(converter.maximumOutputPacketSize, 4096)
        let out = AVAudioCompressedBuffer(format: dstFormat, packetCapacity: 16,
                                          maximumPacketSize: maxPkt)
        var inputGiven = false
        var err: NSError?
        _ = converter.convert(to: out, error: &err) { _, status in
            if inputGiven { status.pointee = .noDataNow; return nil }
            status.pointee = .haveData
            inputGiven = true
            return pcm
        }
        guard err == nil, out.packetCount > 0, let descs = out.packetDescriptions else { return Data() }

        let allBytes = Data(bytes: out.data, count: Int(out.byteLength))
        var result = Data()
        for i in 0..<Int(out.packetCount) {
            let start = Int(descs[i].mStartOffset)
            let len   = Int(descs[i].mDataByteSize)
            guard len > 0 else { continue }
            result += adtsHeader(frameSize: len + 7, sampleRate: dstFormat.sampleRate,
                                  channels: Int(dstFormat.channelCount))
            result += allBytes[start..<start + len]
        }
        return result
    }

    // MARK: - AIFF header parser

    struct AIFFInfo {
        let channels: Int
        let sampleRate: Double
        let bitsPerSample: Int
        let bigEndian: Bool
    }

    private func parseAIFF(_ reader: ByteReader) async throws -> AIFFInfo {
        guard try await reader.read(4) == [0x46, 0x4F, 0x52, 0x4D] else { throw ProxyError.notAIFF }
        _ = try await reader.read(4) // FORM size
        let typeID = try await reader.read(4)
        let isAIFC = typeID == [0x41, 0x49, 0x46, 0x43]  // "AIFC"
        guard isAIFC || typeID == [0x41, 0x49, 0x46, 0x46] else { throw ProxyError.notAIFF } // "AIFF"

        var channels = 2, bits = 16, bigEndian = true
        var sampleRate = 44_100.0
        var commFound = false

        while true {
            let id        = try await reader.read(4)
            let sizeBytes = try await reader.read(4)
            let size      = Int(be32(sizeBytes))
            let label     = String(bytes: id, encoding: .ascii) ?? ""

            if label == "COMM" {
                let d = try await reader.read(size)
                channels   = Int(be16(Array(d[0..<2])))
                bits       = Int(be16(Array(d[6..<8])))
                sampleRate = extended80(Array(d[8..<18]))
                if isAIFC, size >= 22 {
                    let ct = String(bytes: Array(d[18..<22]), encoding: .ascii) ?? ""
                    bigEndian = (ct != "sowt")      // "sowt" = little-endian AIFF-C
                }
                commFound = true
                if size % 2 == 1 { _ = try await reader.read(1) }
            } else if label == "SSND" {
                _ = try await reader.read(8)        // offset + blockSize fields
                guard commFound else { throw ProxyError.notAIFF }
                return AIFFInfo(channels: min(channels, 2), sampleRate: sampleRate,
                                bitsPerSample: bits, bigEndian: bigEndian)
            } else {
                let skip = size + (size % 2 == 1 ? 1 : 0)
                if skip > 0 { _ = try await reader.read(skip) }
            }
        }
    }

    // MARK: - PCM sample helpers

    private func sampleAsFloat(_ b: [UInt8], at i: Int, bits: Int, bigEndian: Bool) -> Float {
        switch bits {
        case 16:
            let v = bigEndian
                ? Int16(bitPattern: UInt16(b[i]) << 8 | UInt16(b[i+1]))
                : Int16(bitPattern: UInt16(b[i]) | UInt16(b[i+1]) << 8)
            return Float(v) / 32_768.0
        case 24:
            var s: Int32 = bigEndian
                ? (Int32(b[i]) << 16) | (Int32(b[i+1]) << 8) | Int32(b[i+2])
                : Int32(b[i]) | (Int32(b[i+1]) << 8) | (Int32(b[i+2]) << 16)
            if s >= (1 << 23) { s -= (1 << 24) }
            return Float(s) / Float(1 << 23)
        case 32:
            let s: Int32 = bigEndian
                ? (Int32(b[i]) << 24) | (Int32(b[i+1]) << 16) | (Int32(b[i+2]) << 8) | Int32(b[i+3])
                : Int32(b[i]) | (Int32(b[i+1]) << 8) | (Int32(b[i+2]) << 16) | (Int32(b[i+3]) << 24)
            return max(-1.0, Float(s) / Float(Int32.max))
        default:
            return 0
        }
    }

    // MARK: - ADTS framing

    private func adtsHeader(frameSize: Int, sampleRate: Double, channels: Int) -> Data {
        let freqs: [(Double, Int)] = [
            (96_000, 0), (88_200, 1), (64_000, 2), (48_000, 3), (44_100, 4),
            (32_000, 5), (24_000, 6), (22_050, 7), (16_000, 8), (12_000, 9),
            (11_025, 10), (8_000, 11), (7_350, 12)
        ]
        let fi = freqs.min(by: { abs($0.0 - sampleRate) < abs($1.0 - sampleRate) })?.1 ?? 4
        let ch = min(channels, 7)
        // profile-1 = 1 (AAC-LC)
        var h = [UInt8](repeating: 0, count: 7)
        h[0] = 0xFF
        h[1] = 0xF1   // MPEG-4, Layer 0, no CRC
        h[2] = UInt8((1 << 6) | (fi << 2) | (ch >> 2))
        h[3] = UInt8(((ch & 3) << 6) | ((frameSize >> 11) & 3))
        h[4] = UInt8((frameSize >> 3) & 0xFF)
        h[5] = UInt8(((frameSize & 7) << 5) | 0x1F)
        h[6] = 0xFC
        return Data(h)
    }

    // MARK: - Byte helpers

    private func be16(_ b: [UInt8]) -> UInt16 { UInt16(b[0]) << 8 | UInt16(b[1]) }
    private func be32(_ b: [UInt8]) -> UInt32 { UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]) }

    private func extended80(_ b: [UInt8]) -> Double {
        let exp = Int(UInt16(b[0] & 0x7F) << 8 | UInt16(b[1])) - 16383
        var m: UInt64 = 0
        for i in 2..<10 { m = m << 8 | UInt64(b[i]) }
        guard exp > -64 else { return 0 }
        return Double(m) * pow(2.0, Double(exp - 63))
    }

    // MARK: - NWConnection send helper

    private func sendData(_ data: Data, on conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    enum ProxyError: Error {
        case notAIFF, converterFailed, unexpectedEOF
    }
}

// MARK: - ByteReader

/// Reference wrapper around URLSession.AsyncBytes.AsyncIterator so helper async
/// functions can advance the stream without inout parameter gymnastics.
private final class ByteReader {
    private var iter: URLSession.AsyncBytes.AsyncIterator

    init(_ bytes: URLSession.AsyncBytes) {
        iter = bytes.makeAsyncIterator()
    }

    func nextByte() async throws -> UInt8? {
        try await iter.next()
    }

    func read(_ count: Int) async throws -> [UInt8] {
        var buf = [UInt8]()
        buf.reserveCapacity(count)
        for _ in 0..<count {
            guard let b = try await iter.next() else {
                throw AudioTranscodeProxy.ProxyError.unexpectedEOF
            }
            buf.append(b)
        }
        return buf
    }
}
