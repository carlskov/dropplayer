# AIFF Transcoding Infrastructure Specification

## Overview

The Cast default media receiver does not support AIFF audio. DropPlayer handles AIFF files transparently via two local HTTP servers: `AudioTranscodeProxy` for a live PCM → AAC-LC stream (Phase 1, immediate playback), and `LocalAudioServer` for a fully transcoded M4A file with byte-range seek support (Phase 2, buffered swap). Both servers bind to random local ports and are owned by `CastManager`.

This document covers the infrastructure layer. For the higher-level Cast session lifecycle and the two-phase loading strategy, see [chromecast.md](chromecast.md).

---

## AudioTranscodeProxy

### Role

Real-time AIFF → AAC-LC transcoder exposed as a single-connection HTTP/1.1 server using `Network.framework`'s `NWListener`.

### Server lifecycle

- `NWListener` is created with a random port (`.any`) at `CastManager` init time.
- `port: UInt16` becomes non-zero once the listener reaches `.ready` state and is used to build the Cast stream URL.
- Accepts one connection at a time; new connections replace any in-flight transcode.

### `serveTranscoded(from:startSample:)`

Registers the Dropbox temporary URL and an optional start sample offset for the **next** incoming connection. When the Cast receiver connects, the proxy starts streaming immediately.

### HTTP response

- Status: `200 OK`
- `Content-Type: audio/aac`
- `Transfer-Encoding: chunked`
- No `Content-Length` (length unknown until transcode completes)

### AIFF header parsing (`parseAIFF`)

Streams the `FORM/AIFF` container looking for two chunks:

| Chunk | Parsed fields |
|---|---|
| `COMM` | `channels`, `sampleFrames`, 80-bit IEEE 754 extended sample rate → `Double`, `bitsPerSample`, optional AIFF-C compression type (`sowt` = little-endian PCM) |
| `SSND` | `offset` and `blockSize` → computes `ssndDataOffset` (byte position of the first PCM sample in the file) |

Results are stored in `cachedInfo: AIFFInfo` for use by subsequent seek operations without re-downloading the header.

### `AIFFInfo` struct

| Field | Type |
|---|---|
| `channels` | `Int` |
| `sampleRate` | `Double` |
| `bitsPerSample` | `Int` |
| `bigEndian` | `Bool` |
| `ssndDataOffset` | `Int` |

### PCM → AAC-LC encoding pipeline

1. Reads PCM bytes from the Dropbox `URLSession` data stream (or from a byte-range request for seek; see below).
2. Converts raw bytes to `AVAudioPCMBuffer` (Float32 interleaved).
3. Passes buffer through `AVAudioConverter` configured for AAC-LC output at up to 48 kHz, 320 kbps.
4. Each output `AudioBufferList` packet is prefixed with a 7-byte **ADTS header**:
   - Sync word (12 bits `0xFFF`)
   - ID = 0 (MPEG-4)
   - Layer = 00
   - Protection absent = 1
   - Profile = 1 (AAC-LC, value = profile - 1)
   - Sampling frequency index (table lookup from output sample rate)
   - Private bit = 0
   - Channel configuration
   - Copy/home/originality bits = 0
   - AAC frame length (7 + packet bytes)
   - Buffer fullness = 0x7FF (VBR)
   - Number of AAC frames = 0 (one frame per ADTS packet)
5. ADTS-wrapped bytes are sent as chunked HTTP body data.

### Seek path

When `CastManager` requests a seek (e.g., user drags the seek bar while on Phase 1):

1. Converts target time to a PCM sample offset: `sampleOffset = Int(time × info.sampleRate)`.
2. Computes byte offset within the SSND data: `byteOffset = sampleOffset × channels × (bitsPerSample / 8)`.
3. Issues a new Dropbox HTTP request with `Range: bytes=<ssndDataOffset + byteOffset>-`.
4. Calls `serveTranscoded(from:startSample:sampleOffset)` so the next Cast connection picks up from the right point.
5. Appends `?t=<sampleOffset>` as a cache-busting query parameter to the proxy URL so the Cast receiver opens a new connection.

### Cached seek optimisation

Once `cachedInfo` is populated from the first AIFF header parse, subsequent seeks reuse it and skip re-downloading the header bytes.

---

## LocalAudioServer

### Role

Minimal HTTP/1.1 file server with byte-range support, used to serve the Phase 2 transcoded `.m4a` file to the Cast receiver.

### Server lifecycle

- `NWListener` on a random port, created at `CastManager` init.
- `port: UInt16` used to build the Phase 2 Cast stream URL.

### `serve(fileAt:mimeType:)`

Registers a local file path and MIME type for the next request. In-flight requests against the old file are allowed to complete before the handle is replaced.

### Request handling

1. Reads `Range: bytes=N-M` header if present.
2. Opens the file at `filePath`, seeks to `N`.
3. Responds:
   - `206 Partial Content` with `Content-Range: bytes N-M/total` if a range was requested.
   - `200 OK` with `Content-Length: total` for a full-file request.
4. Streams the file body as chunked data until the range (or EOF) is reached.
5. `Content-Type` is set to the registered MIME type (typically `audio/mp4`).

---

## Phase 2 Transcode Process

The background `Task` in `CastManager.castAIFF(...)`:

1. Downloads the full AIFF to a temp file via `URLSession`.
2. Creates an `AVURLAsset` from the temp file.
3. Runs `AVAssetExportSession` with preset `AVAssetExportPresetAppleM4A`, output URL in the temp directory (`track_<uuid>.m4a`).
4. On completion (`status == .completed`):
   - Calls `localServer.serve(fileAt: m4aURL, mimeType: "audio/mp4")`.
   - Calls `sendToReceiver(...)` with the local M4A URL and `streamType: .buffered`, passing the current `castCurrentTime` as the start position.
5. The Cast receiver discards the live AAC stream and opens the new M4A URL with full seek support.

### Temporary file cleanup

- The AIFF download temp file is deleted immediately after the export session completes.
- The M4A temp file is deleted when the next track loads or `CastManager` is deallocated.

---

## Local IP Address Resolution

Both servers need the device's local Wi-Fi IP to build URLs accessible by the Cast receiver. IP is resolved via `getifaddrs`, filtering for the `en0` interface (Wi-Fi). The resulting `http://<device-ip>:<port>/...` URL is passed to `GCKRemoteMediaClient`.

---

## Summary

| Server | Port | Protocol | Used for |
|---|---|---|---|
| `AudioTranscodeProxy` | Random (any available) | HTTP/1.1, chunked | AIFF Phase 1 live stream |
| `LocalAudioServer` | Random (any available) | HTTP/1.1, byte-range | AIFF Phase 2 buffered M4A |
