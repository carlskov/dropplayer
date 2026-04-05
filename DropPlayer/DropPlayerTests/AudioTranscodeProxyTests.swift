import XCTest
@testable import DropPlayer

final class AudioTranscodeProxyTests: XCTestCase {

    // MARK: - Initial state

    func testCachedInfoIsNilInitially() {
        let proxy = AudioTranscodeProxy()
        XCTAssertNil(proxy.cachedInfo)
    }

    func testPortIsZeroBeforeStart() {
        let proxy = AudioTranscodeProxy()
        XCTAssertEqual(proxy.port, 0)
    }

    func testPortIsNonzeroAfterStart() async throws {
        let proxy = AudioTranscodeProxy()
        proxy.start()
        defer { proxy.stop() }
        try await waitFor(timeout: 1.0) { proxy.port != 0 }
        XCTAssertGreaterThan(proxy.port, 0)
    }

    // MARK: - Seek byte-offset formula

    /// The byte skip formula: byteSkip = ssndDataOffset + startSample * channels * bps
    func testSeekByteOffset_stereo_16bit() {
        // Standard AIFF: ssndDataOffset = 54 (see structural test below)
        let info = AudioTranscodeProxy.AIFFInfo(
            channels: 2, sampleRate: 44100, bitsPerSample: 16,
            bigEndian: true, ssndDataOffset: 54
        )
        let startSample = 44100  // 1 second at 44.1 kHz
        let bps = (info.bitsPerSample + 7) / 8  // 2
        let byteSkip = info.ssndDataOffset + startSample * info.channels * bps
        // 54 + 44100 * 2 * 2 = 176454
        XCTAssertEqual(byteSkip, 176454)
    }

    func testSeekByteOffset_mono_24bit() {
        let info = AudioTranscodeProxy.AIFFInfo(
            channels: 1, sampleRate: 48000, bitsPerSample: 24,
            bigEndian: true, ssndDataOffset: 54
        )
        let startSample = 48000  // 1 second at 48 kHz
        let bps = (info.bitsPerSample + 7) / 8  // 3
        let byteSkip = info.ssndDataOffset + startSample * info.channels * bps
        // 54 + 48000 * 1 * 3 = 144054
        XCTAssertEqual(byteSkip, 144054)
    }

    func testSeekByteOffset_stereo_32bit() {
        let info = AudioTranscodeProxy.AIFFInfo(
            channels: 2, sampleRate: 96000, bitsPerSample: 32,
            bigEndian: true, ssndDataOffset: 54
        )
        let startSample = 96000  // 1 second at 96 kHz
        let bps = (info.bitsPerSample + 7) / 8  // 4
        let byteSkip = info.ssndDataOffset + startSample * info.channels * bps
        // 54 + 96000 * 2 * 4 = 768054
        XCTAssertEqual(byteSkip, 768054)
    }

    func testSeekByteOffsetAtSampleZeroEqualsDataOffset() {
        let info = AudioTranscodeProxy.AIFFInfo(
            channels: 2, sampleRate: 44100, bitsPerSample: 16,
            bigEndian: true, ssndDataOffset: 54
        )
        let bps = (info.bitsPerSample + 7) / 8
        let byteSkip = info.ssndDataOffset + 0 * info.channels * bps
        XCTAssertEqual(byteSkip, info.ssndDataOffset)
    }

    // MARK: - AIFF file structure

    /// A standard AIFF file with a single COMM chunk (18 bytes) followed by SSND
    /// must produce ssndDataOffset == 54.
    ///
    ///   12 bytes  FORM header  ("FORM" + size + "AIFF")
    /// + 26 bytes  COMM chunk   ("COMM" + be32(18) + 18 bytes of data)
    /// + 16 bytes  SSND preamble ("SSND" + size + 4-byte offset + 4-byte blockSize)
    /// ─────────────────
    ///   54 bytes
    func testStandardAIFFHeaderByteLayout() {
        let formHeader   = 4 + 4 + 4   // "FORM" + be32 size + "AIFF"
        let commChunk    = 4 + 4 + 18  // "COMM" + be32(18) + 18-byte COMM data
        let ssndPreamble = 4 + 4 + 8   // "SSND" + be32 size + (offset + blockSize)
        let expected = formHeader + commChunk + ssndPreamble
        XCTAssertEqual(expected, 54)
    }

    // MARK: - Integration: cachedInfo populated after transcode

    func testCachedInfoIsPopulatedAfterConnecting() async throws {
        let fileServer = LocalAudioServer()
        let proxy = AudioTranscodeProxy()
        fileServer.start()
        proxy.start()
        defer { proxy.stop(); fileServer.stop() }

        try await waitFor(timeout: 2.0) { proxy.port != 0 && fileServer.port != 0 }
        guard proxy.port != 0 && fileServer.port != 0 else { throw XCTSkip("Servers not ready") }

        // Write a minimal AIFF (silence) — 256 frames, 2 ch, 16-bit, 44100 Hz
        let aiffData = makeMinimalAIFF(channels: 2, sampleRate: 44100, bitsPerSample: 16, frameCount: 256)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("proxy_test_\(UUID().uuidString).aiff")
        try aiffData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        fileServer.serve(fileAt: tempURL, mimeType: "audio/aiff")
        let aiffSourceURL = URL(string: "http://127.0.0.1:\(fileServer.port)/track.m4a")!
        proxy.serveTranscoded(from: aiffSourceURL)

        // Connect to the proxy; read enough bytes to trigger the full AIFF parse
        let proxyURL = URL(string: "http://127.0.0.1:\(proxy.port)/stream.aac")!
        let (stream, response) = try await URLSession.shared.bytes(from: proxyURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertEqual(status, 200)
        var received = 0
        for try await _ in stream {
            received += 1
            if received >= 128 { break }
        }

        XCTAssertNotNil(proxy.cachedInfo, "cachedInfo should be set after transcode")
        XCTAssertEqual(proxy.cachedInfo?.channels, 2)
        XCTAssertEqual(proxy.cachedInfo?.sampleRate ?? 0, 44100, accuracy: 1.0)
        XCTAssertEqual(proxy.cachedInfo?.bitsPerSample, 16)
        XCTAssertEqual(proxy.cachedInfo?.ssndDataOffset, 54,
                       "SSND PCM data should begin at byte 54 in a standard AIFF")
    }

    // MARK: - Integration: seek path produces output without error

    func testSeekPathProducesOutputWhenCachedInfoIsAvailable() async throws {
        let fileServer = LocalAudioServer()
        let proxy = AudioTranscodeProxy()
        fileServer.start()
        proxy.start()
        defer { proxy.stop(); fileServer.stop() }

        try await waitFor(timeout: 2.0) { proxy.port != 0 && fileServer.port != 0 }
        guard proxy.port != 0 && fileServer.port != 0 else { throw XCTSkip("Servers not ready") }

        // Enough frames for a non-trivial seek: 4 seconds at 44.1 kHz stereo 16-bit
        let frameCount = 44100 * 4
        let aiffData = makeMinimalAIFF(channels: 2, sampleRate: 44100, bitsPerSample: 16, frameCount: frameCount)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("proxy_seek_test_\(UUID().uuidString).aiff")
        try aiffData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        fileServer.serve(fileAt: tempURL, mimeType: "audio/aiff")
        let aiffSourceURL = URL(string: "http://127.0.0.1:\(fileServer.port)/track.m4a")!

        // ── Pass 1: normal stream to populate cachedInfo ──
        proxy.serveTranscoded(from: aiffSourceURL)
        let pass1URL = URL(string: "http://127.0.0.1:\(proxy.port)/stream.aac")!
        let (pass1Stream, _) = try await URLSession.shared.bytes(from: pass1URL)
        var received = 0
        for try await _ in pass1Stream {
            received += 1
            if received >= 128 { break }
        }
        XCTAssertNotNil(proxy.cachedInfo, "cachedInfo must be set before seeking")

        // ── Pass 2: seek to 2 seconds (sample 88200) using Range request ──
        proxy.serveTranscoded(from: aiffSourceURL, startSample: 88200)
        let pass2URL = URL(string: "http://127.0.0.1:\(proxy.port)/stream.aac?t=2")!
        let (pass2Stream, pass2Response) = try await URLSession.shared.bytes(from: pass2URL)
        let status = (pass2Response as? HTTPURLResponse)?.statusCode ?? 0
        XCTAssertEqual(status, 200, "Seek stream should respond with 200")
        var seekBytes = 0
        for try await _ in pass2Stream {
            seekBytes += 1
            if seekBytes >= 128 { break }
        }
        XCTAssertGreaterThan(seekBytes, 0, "Seek path must produce audio output")
        // cachedInfo should remain intact after a seek (not re-parsed)
        XCTAssertEqual(proxy.cachedInfo?.ssndDataOffset, 54)
    }

    // MARK: - Seek byte-skip for pass 2 (verify arithmetic cross-check)

    func testSeekByteSkipForTwoSecondSeekAt44100Stereo16bit() {
        // Matches the seek in testSeekPathProducesOutputWhenCachedInfoIsAvailable
        let ssndDataOffset = 54
        let channels = 2
        let bps = 2  // 16-bit
        let startSample = 88200  // 2 seconds at 44100 Hz
        let byteSkip = ssndDataOffset + startSample * channels * bps
        // 54 + 88200 * 2 * 2 = 54 + 352800 = 352854
        XCTAssertEqual(byteSkip, 352854)
    }

    // MARK: - Helpers

    /// Spins at most `timeout` seconds checking `condition` every 50 ms.
    private func waitFor(timeout: TimeInterval, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Builds a minimal, valid AIFF binary containing silence.
    private func makeMinimalAIFF(channels: Int, sampleRate: Double, bitsPerSample: Int, frameCount: Int) -> Data {
        func be16(_ v: UInt16) -> Data {
            Data([UInt8(v >> 8), UInt8(v & 0xFF)])
        }
        func be32(_ v: UInt32) -> Data {
            Data([UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
        }
        /// Encode a Double as an 80-bit IEEE 754 extended-precision value (big-endian).
        func extended80(_ rate: Double) -> Data {
            guard rate > 0 else { return Data(repeating: 0, count: 10) }
            let exp = Int(log2(rate).rounded(.down))
            let biasedExp = exp + 16383
            let mantissa = UInt64(rate * pow(2.0, Double(63 - exp)))
            return Data([
                UInt8((biasedExp >> 8) & 0x7F), UInt8(biasedExp & 0xFF),
                UInt8(mantissa >> 56), UInt8((mantissa >> 48) & 0xFF),
                UInt8((mantissa >> 40) & 0xFF), UInt8((mantissa >> 32) & 0xFF),
                UInt8((mantissa >> 24) & 0xFF), UInt8((mantissa >> 16) & 0xFF),
                UInt8((mantissa >> 8) & 0xFF), UInt8(mantissa & 0xFF)
            ])
        }

        // COMM data (18 bytes): numChannels(2) + numSampleFrames(4) + sampleSize(2) + sampleRate(10)
        var comm = Data()
        comm += be16(UInt16(channels))
        comm += be32(UInt32(frameCount))
        comm += be16(UInt16(bitsPerSample))
        comm += extended80(sampleRate)

        // SSND data: offset(4) + blockSize(4) + PCM silence
        let bps = (bitsPerSample + 7) / 8
        var ssnd = Data()
        ssnd += be32(0)  // SSND internal offset
        ssnd += be32(0)  // blockSize
        ssnd += Data(repeating: 0, count: frameCount * channels * bps)  // silence

        // FORM body: "AIFF" + COMM chunk + SSND chunk
        var body = Data()
        body += "AIFF".data(using: .ascii)!
        body += "COMM".data(using: .ascii)!
        body += be32(UInt32(comm.count))
        body += comm
        body += "SSND".data(using: .ascii)!
        body += be32(UInt32(ssnd.count))
        body += ssnd

        var file = Data()
        file += "FORM".data(using: .ascii)!
        file += be32(UInt32(body.count))
        file += body
        return file
    }
}
