import Foundation
import SwiftyDropbox
import UIKit
import Combine


@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var albums: [Album] = []
    @Published var isScanning = false
    @Published var scanError: String?
    @Published var scanProgress: String = ""
    @Published var isTagScanning = false
    @Published var tagScanProgress: String = ""
    @Published var scanningAlbumId: String?

    private var tagScanTask: Task<Void, Never>?

    private let service = DropboxBrowserService.shared
    private var artworkCache: [String: UIImage] = [:]
    private let cacheKey = "CachedAlbums"

    private let artworkDiskCacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("AlbumArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private let metadataExtractor = MetadataExtractor(service: DropboxBrowserService.shared)

    private let audioExtensions: Set<String> = ["mp3", "flac", "aac", "m4a", "ogg", "wav", "aiff", "aif", "alac", "opus"]
    private let artworkFileNames: Set<String> = ["cover", "folder", "front", "albumart", "album", "artwork"]
    private let artworkExtensions: Set<String> = ["jpg", "jpeg", "png", "webp"]

    init() {
        loadCachedAlbums()
    }

    // MARK: - Public API

    func scanLibrary(at paths: [String]) async {
        await rescanLibrary(at: paths)
    }

    func rescanLibrary(at paths: [String]) async {
        tagScanTask?.cancel()
        tagScanTask = nil
        isTagScanning = false

        isScanning = true
        scanError = nil
        albums = []

        do {
            var discovered: [Album] = []
            for path in paths {
                let results = try await scanFolder(path: path, depth: 0)
                discovered.append(contentsOf: results)
            }
            
            // Quick metadata scan for multi-disc detection
            await quickScanForMerge(&discovered)
            
            let merged = mergeMultiDiscAlbums(discovered)
            albums = merged.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            saveAlbums()
        } catch {
            scanError = error.localizedDescription
        }

        isScanning = false

        if !albums.isEmpty {
            startTagScan()
        }
    }

    func loadTrackMetadata(for track: Track) async -> (artist: String?, title: String?) {
        let metadata = await metadataExtractor.extractMetadata(from: track.dropboxPath)
        let artist = metadata["artist"].flatMap { $0.isEmpty ? nil : $0 }
        let title = metadata["title"].flatMap { $0.isEmpty ? nil : $0 }
        return (artist, title)
    }

    func loadArtwork(for album: Album) async -> UIImage? {
        if let artPath = album.artworkDropboxPath {
            let fileCacheKey = "file:\(artPath)"
            if let cached = artworkCache[fileCacheKey] { return cached }
            if let diskImage = loadArtworkFromDisk(key: fileCacheKey) {
                artworkCache[fileCacheKey] = diskImage
                return diskImage
            }
            if let data = try? await service.downloadData(path: artPath),
               let image = UIImage(data: data) {
                artworkCache[fileCacheKey] = image
                saveArtworkToDisk(key: fileCacheKey, image: image)
                return image
            }
        }
        let embeddedCacheKey = "embedded:\(album.id)"
        if let cached = artworkCache[embeddedCacheKey] { return cached }
        if let diskImage = loadArtworkFromDisk(key: embeddedCacheKey) {
            artworkCache[embeddedCacheKey] = diskImage
            return diskImage
        }
        if let firstTrack = album.tracks.first,
           let artworkData = await metadataExtractor.extractArtwork(from: firstTrack.dropboxPath),
           let image = UIImage(data: artworkData) {
            artworkCache[embeddedCacheKey] = image
            saveArtworkToDisk(key: embeddedCacheKey, image: image)
            return image
        }
        return nil
    }

    // MARK: - Caching

    private func artworkDiskCacheFileName(for key: String) -> String {
        // Base64-encode the key so the filename is stable across launches.
        // (Swift's Hasher uses a random per-process seed and cannot be used here.)
        let encoded = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "\(encoded).jpg"
    }

    private func loadArtworkFromDisk(key: String) -> UIImage? {
        let url = artworkDiskCacheDirectory.appendingPathComponent(artworkDiskCacheFileName(for: key))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func saveArtworkToDisk(key: String, image: UIImage) {
        let url = artworkDiskCacheDirectory.appendingPathComponent(artworkDiskCacheFileName(for: key))
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func removeArtworkFromDisk(key: String) {
        let url = artworkDiskCacheDirectory.appendingPathComponent(artworkDiskCacheFileName(for: key))
        try? FileManager.default.removeItem(at: url)
    }

    private func loadCachedAlbums() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode([Album].self, from: data) else { return }
        albums = cached
    }

    private func saveAlbums() {
        guard let data = try? JSONEncoder().encode(albums) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    // MARK: - Scanning

    /// Recursively scans ``path``. Returns one Album per sub-folder containing audio.
    private func scanFolder(path: String, depth: Int) async throws -> [Album] {
        let entries = try await service.listFolder(path: path)

        var albums: [Album] = []

        // Separate into audio files, image files, and sub-folders
        let audioFiles = entries.compactMap { $0 as? Files.FileMetadata }
            .filter { isAudioFile($0.name) }
        let imageFiles = entries.compactMap { $0 as? Files.FileMetadata }
            .filter { isArtworkFile($0.name) }
        let subFolders = entries.compactMap { $0 as? Files.FolderMetadata }

        if !audioFiles.isEmpty {
            let folderName = lastPathComponent(path)
            var directArtwork = preferredArtworkPath(from: imageFiles)
            if directArtwork == nil,
               let coversFolder = subFolders.first(where: { $0.name.lowercased() == "covers" }),
               let coversEntries = try? await service.listFolder(path: coversFolder.pathLower ?? "\(path)/Covers") {
                let coversImages = coversEntries.compactMap { $0 as? Files.FileMetadata }
                    .filter { isArtworkFile($0.name) }
                directArtwork = preferredArtworkPath(from: coversImages)
            }
            
            // For potential multi-disc albums, also check parent folder for artwork
            if directArtwork == nil && depth > 0 {
                let parentFolder = (path as NSString).deletingLastPathComponent
                directArtwork = await findArtworkInFolder(path: parentFolder)
            }
            
            var album = Album(
                id: path,
                folderPath: path,
                folderName: folderName,
                title: "",
                artist: "",
                year: nil,
                tracks: [],
                artworkDropboxPath: directArtwork
            )

            parseAlbumMetadata(into: &album, folderName: folderName)

            album.tracks = audioFiles
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { makeTrack(from: $0, albumArtist: album.artist) }

            await MainActor.run {
                scanProgress = "Found: \(album.displayTitle)"
            }
            albums.append(album)
        }

        // Recurse into sub-folders (limit depth to 5 to avoid infinite loops in huge trees)
        if depth < 5 {
            for folder in subFolders {
                let sub = try await scanFolder(path: folder.pathLower ?? folder.name, depth: depth + 1)
                albums.append(contentsOf: sub)
            }
        }

        return albums
    }

    // MARK: - Helpers

    private func isAudioFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return audioExtensions.contains(ext)
    }

    private func isArtworkFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return artworkExtensions.contains(ext)
    }

    private func preferredArtworkPath(from files: [Files.FileMetadata]) -> String? {
        let preferred = ["cover", "folder", "front", "album", "artwork", "albumart"]
        for name in preferred {
            for ext in ["jpg", "jpeg", "png", "webp"] {
                if let match = files.first(where: { $0.name.lowercased() == "\(name).\(ext)" }) {
                    return match.pathLower ?? match.name
                }
            }
        }
        
        // Fallback: look for files ending with "front" (optionally prefixed with - or _)
        // Pattern: front.jpg, -front.png, _front.webp, album-front.jpeg, cover_front.jpg, 00-VA_-_Tribal_Science-front.jpg
        let frontPattern = #"[^\\/]*[-_]front\.(jpg|jpeg|png|webp)$"#
        if let frontMatch = files.first(where: { 
            $0.name.range(of: frontPattern, options: [.regularExpression, .caseInsensitive]) != nil 
        }) {
            return frontMatch.pathLower ?? frontMatch.name
        }
        
        return files.first.flatMap { $0.pathLower ?? $0.name }
    }

    private func rescanFolderContents(for album: inout Album) async {
        // Build a mapping from parent folder → disc number using existing tracks.
        // For merged multi-disc albums each disc lives in a different subfolder.
        var folderToDisc: [String: Int] = [:]
        for track in album.tracks {
            let parentFolder = (track.dropboxPath as NSString).deletingLastPathComponent
            if folderToDisc[parentFolder] == nil {
                folderToDisc[parentFolder] = track.discNumber ?? 1
            }
        }
        if folderToDisc.isEmpty {
            folderToDisc[album.folderPath] = 1
        }

        let sortedDiscFolders = folderToDisc.sorted { $0.value < $1.value }
        let isMultiDisc = sortedDiscFolders.count > 1
        let existingTracks = Dictionary(uniqueKeysWithValues: album.tracks.map { ($0.id, $0) })
        var allNewTracks: [Track] = []

        for (folderPath, discNum) in sortedDiscFolders {
            do {
                let entries = try await service.listFolder(path: folderPath)
                let audioFiles = entries.compactMap { $0 as? Files.FileMetadata }
                    .filter { isAudioFile($0.name) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                for file in audioFiles {
                    let path = file.pathLower ?? file.name
                    var track = existingTracks[path] ?? makeTrack(from: file, albumArtist: album.artist)
                    if isMultiDisc {
                        track.discNumber = discNum
                    }
                    allNewTracks.append(track)
                }
            } catch {
                // Keep existing tracks for this disc folder on error
                let existingForDisc = album.tracks.filter {
                    ($0.dropboxPath as NSString).deletingLastPathComponent == folderPath
                }
                allNewTracks.append(contentsOf: existingForDisc)
            }
        }

        if !allNewTracks.isEmpty {
            album.tracks = allNewTracks
        }
    }

    private func findArtworkInFolder(path: String) async -> String? {
        do {
            let entries = try await service.listFolder(path: path)
            let imageFiles = entries.compactMap { $0 as? Files.FileMetadata }
                .filter { isArtworkFile($0.name) }
            if let found = preferredArtworkPath(from: imageFiles) {
                return found
            }
            // Check "Covers" subfolder
            if let coversFolder = entries.compactMap({ $0 as? Files.FolderMetadata })
                .first(where: { $0.name.lowercased() == "covers" }) {
                let coversPath = coversFolder.pathLower ?? "\(path)/Covers"
                let coversEntries = try await service.listFolder(path: coversPath)
                let coversImages = coversEntries.compactMap { $0 as? Files.FileMetadata }
                    .filter { isArtworkFile($0.name) }
                if let found = preferredArtworkPath(from: coversImages) {
                    return found
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    private func makeTrack(from file: Files.FileMetadata, albumArtist: String?) -> Track {
        let path = file.pathLower ?? file.name
        let name = file.name
        let nameWithoutExt = (name as NSString).deletingPathExtension

        var trackNumber: Int?
        var title = nameWithoutExt
        var artist = albumArtist

        // Patterns: "(01) Artist - Title", "01. Artist - Title", "01 - Artist - Title", "Artist - Title"
        let patterns = [
            #"^\((\d+)\)[.\- ]*(\S.*?)\s+[-–]\s+(.+)$"#,
            #"^(\d+)[.\- ]+(\S.*?)\s+[-–]\s+(.+)$"#,
            #"^(\d+)[.\- ]+(.+)$"#,
            #"^(\S.*?)\s+[-–]\s+(.+)$"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: nameWithoutExt, range: NSRange(nameWithoutExt.startIndex..., in: nameWithoutExt)) {
                if match.numberOfRanges == 4 {
                    if let artistRange = Range(match.range(at: 2), in: nameWithoutExt) {
                        artist = String(nameWithoutExt[artistRange])
                    }
                    if let titleRange = Range(match.range(at: 3), in: nameWithoutExt) {
                        title = String(nameWithoutExt[titleRange])
                    }
                } else if match.numberOfRanges == 3 {
                    let group1 = Range(match.range(at: 1), in: nameWithoutExt).map({ String(nameWithoutExt[$0]) })
                    if let numStr = group1, Int(numStr) != nil {
                        if let numRange = Range(match.range(at: 1), in: nameWithoutExt),
                           let titleRange = Range(match.range(at: 2), in: nameWithoutExt) {
                            trackNumber = Int(nameWithoutExt[numRange])
                            title = String(nameWithoutExt[titleRange])
                        }
                    } else if let artistRange = Range(match.range(at: 1), in: nameWithoutExt),
                              let titleRange = Range(match.range(at: 2), in: nameWithoutExt) {
                        artist = String(nameWithoutExt[artistRange])
                        title = String(nameWithoutExt[titleRange])
                    }
                }
                break
            }
        }

        return Track(
            id: path,
            dropboxPath: path,
            fileName: name,
            title: title,
            trackNumber: trackNumber,
            discNumber: nil,
            durationSeconds: nil,
            artist: artist?.isEmpty == true ? nil : artist
        )
    }

    /// Tries to infer album title and artist from a folder name like "Artist - Album (Year)".
    private func parseAlbumMetadata(into album: inout Album, folderName: String) {
        // Try multiple patterns for folder names
        let patterns = [
            #"^(.+?)\s+[-–—]\s+(.+?)(?:\s+\((\d{4})\))?$"#,  // "Artist - Album (Year)"
            #"^(.+?)\s+[-–—]\s+(.+)$"#,                       // "Artist - Album"
            #"^(.+?)\s+[-–—]\s+(.+?)(?:\s+\[.+\])?$"#,      // "Artist - Album [genre]"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: folderName, range: NSRange(folderName.startIndex..., in: folderName)) {
                if let artistRange = Range(match.range(at: 1), in: folderName) {
                    album.artist = String(folderName[artistRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let titleRange = Range(match.range(at: 2), in: folderName) {
                    album.title = String(folderName[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if match.numberOfRanges > 3, let yearRange = Range(match.range(at: 3), in: folderName), !yearRange.isEmpty {
                    album.year = String(folderName[yearRange])
                }
                return
            }
        }

        // No pattern matched — try to infer artist from first track filename
        if let firstTrack = album.tracks.first, let trackArtist = inferArtistFromFilename(firstTrack.fileName) {
            album.artist = trackArtist
            album.title = folderName
        } else {
            album.title = folderName
        }
    }

    private func inferArtistFromFilename(_ filename: String) -> String? {
        let nameWithoutExt = (filename as NSString).deletingPathExtension
        let patterns = [
            #"^(\S.*?)\s+[-–—]\s+.+$"#,  // "Artist - Title"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: nameWithoutExt, range: NSRange(nameWithoutExt.startIndex..., in: nameWithoutExt)),
               let artistRange = Range(match.range(at: 1), in: nameWithoutExt) {
                return String(nameWithoutExt[artistRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func extractBaseAlbumName(_ folderName: String) -> (baseName: String, discNumber: Int?) {
        // Patterns for multi-disc folders
        let discPatterns = [
            #"(?i)\s*\(\s*cd\s*(\d+)\s*\)\s*$"#,     // "(CD1)", "(CD 1)"
            #"(?i)\s*[-–—]\s*cd\s*(\d+)\s*$"#,     // "- CD1", "- CD 1"
            #"(?i)\s*\[?\s*disc\s*(\d+)\s*\]?\s*$"#, // "[Disc 1]", "Disc 1"
            #"(?i)\s*part\s*(\d+)\s*$"#,            // "Part 1"
            #"(?i)\s*vol\.?\s*(\d+)\s*$"#,          // "Vol. 1", "Vol 1"
            #"\s+(\d+)\s*$"#,                        // " 1" (trailing number)
        ]

        for pattern in discPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: folderName, range: NSRange(folderName.startIndex..., in: folderName)) {
                let baseName = String(folderName[..<folderName.index(folderName.startIndex, offsetBy: match.range.location)]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let discRange = Range(match.range(at: 1), in: folderName),
                   let discNum = Int(folderName[discRange]) {
                    return (baseName, discNum)
                }
            }
        }

        return (folderName, nil)
    }

    private func quickScanForMerge(_ albums: inout [Album]) async {
        for i in albums.indices {
            guard let firstTrack = albums[i].tracks.first else { continue }
            let metadata = await metadataExtractor.extractMetadata(from: firstTrack.dropboxPath)
            
            // Extract album title from tags
            if let albumTitle = metadata["album"], !albumTitle.isEmpty {
                albums[i].title = albumTitle
            }
            
            // Extract disc info from tags (e.g., "1/2" or just "1")
            if let diskStr = metadata["disk"] ?? metadata["part"], !diskStr.isEmpty {
                let parts = diskStr.components(separatedBy: "/")
                if let firstPart = parts.first, let discNum = Int(firstPart) {
                    albums[i].discNumber = discNum
                }
            }
        }
    }

    private func mergeMultiDiscAlbums(_ albums: [Album]) -> [Album] {
        var albumGroups: [String: [Album]] = [:]

        for album in albums {
            // Use tag-derived title if available, otherwise folder name
            let albumName = album.title.isEmpty ? album.folderName : album.title
            let (baseName, _) = extractBaseAlbumName(albumName)
            albumGroups[baseName, default: []].append(album)
        }

        var mergedAlbums: [Album] = []

        for (_, group) in albumGroups {
            if group.count > 1 {
                // Sort by disc number
                let sorted = group.sorted { a, b in
                    let (_, discA) = extractBaseAlbumName(a.folderName)
                    let (_, discB) = extractBaseAlbumName(b.folderName)
                    return (discA ?? 0) < (discB ?? 0)
                }

                // Merge into first album
                var mainAlbum = sorted[0]
                for i in 1..<sorted.count {
                    for track in sorted[i].tracks {
                        var mergedTrack = track
                        mergedTrack.discNumber = i + 1
                        mainAlbum.tracks.append(mergedTrack)
                    }
                    // Keep artwork from first disc if available
                    if mainAlbum.artworkDropboxPath == nil && sorted[i].artworkDropboxPath != nil {
                        mainAlbum.artworkDropboxPath = sorted[i].artworkDropboxPath
                    }
                }

                // Sort tracks by disc number then track number
                mainAlbum.tracks.sort { a, b in
                    let d0 = a.discNumber ?? 1
                    let d1 = b.discNumber ?? 1
                    if d0 != d1 { return d0 < d1 }
                    return (a.trackNumber ?? Int.max) < (b.trackNumber ?? Int.max)
                }

                mergedAlbums.append(mainAlbum)
            } else {
                mergedAlbums.append(group[0])
            }
        }

        return mergedAlbums
    }

    private func lastPathComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    // MARK: - Background Tag Scan

    func startTagScan() {
        tagScanTask?.cancel()
        isTagScanning = true
        tagScanProgress = ""

        tagScanTask = Task { [weak self] in
            guard let self else { return }

            let albumIds = self.albums.map { $0.id }

            for albumId in albumIds {
                guard !Task.isCancelled else { break }
                await self.scanTagsForAlbum(withId: albumId)
            }

            guard !Task.isCancelled else { return }
            self.albums.sort {
                $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            self.saveAlbums()
            self.isTagScanning = false
            self.tagScanProgress = ""
        }
    }

    func rescanTagsForAlbum(_ album: Album) async {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }

        isTagScanning = true
        tagScanProgress = "Rescanning \(album.displayTitle)"
        scanningAlbumId = album.id

        var updatedAlbum = albums[index]
        updatedAlbum.tagsLoaded = false

        // Clear artwork cache for this album
        let artPath = updatedAlbum.artworkDropboxPath ?? "embedded:\(updatedAlbum.id)"
        artworkCache.removeValue(forKey: "file:\(artPath)")
        artworkCache.removeValue(forKey: "embedded:\(updatedAlbum.id)")
        removeArtworkFromDisk(key: "file:\(artPath)")
        removeArtworkFromDisk(key: "embedded:\(updatedAlbum.id)")

        // Re-scan folder for audio files
        await rescanFolderContents(for: &updatedAlbum)

        // Scan for artwork files in folder (and Covers subfolder)
        // For multi-disc albums, also check the top-level containing folder
        var foundArtworkPath = await findArtworkInFolder(path: updatedAlbum.folderPath)
        if foundArtworkPath == nil {
            let discFolders = Set(updatedAlbum.tracks.map { ($0.dropboxPath as NSString).deletingLastPathComponent })
            let isMultiDisc = discFolders.count > 1 || discFolders.first.map({ $0 != updatedAlbum.folderPath }) == true
            if isMultiDisc {
                let parentFolder = (updatedAlbum.folderPath as NSString).deletingLastPathComponent
                foundArtworkPath = await findArtworkInFolder(path: parentFolder)
            }
        }
        if let artworkPath = foundArtworkPath {
            updatedAlbum.artworkDropboxPath = artworkPath
            let fileCacheKey = "file:\(artworkPath)"
            if let data = try? await service.downloadData(path: artworkPath),
               let image = UIImage(data: data) {
                artworkCache[fileCacheKey] = image
                saveArtworkToDisk(key: fileCacheKey, image: image)
            }
        }

        // Scan for embedded artwork from first track
        if let firstTrack = updatedAlbum.tracks.first,
           let artworkData = await metadataExtractor.extractArtwork(from: firstTrack.dropboxPath),
           let image = UIImage(data: artworkData) {
            artworkCache["embedded:\(updatedAlbum.id)"] = image
            saveArtworkToDisk(key: "embedded:\(updatedAlbum.id)", image: image)
        }

        await scanTagsForAlbum(album: &updatedAlbum)
        updatedAlbum.tagsLoaded = true
        
        if let currentIndex = albums.firstIndex(where: { $0.id == updatedAlbum.id }) {
            albums[currentIndex] = updatedAlbum
        }
        saveAlbums()

        isTagScanning = false
        tagScanProgress = ""
        scanningAlbumId = nil
    }

    private func scanTagsForAlbum(withId albumId: String) async {
        guard let albumIndex = albums.firstIndex(where: { $0.id == albumId }) else { return }

        var album = albums[albumIndex]
        tagScanProgress = album.displayTitle

        await scanTagsForAlbum(album: &album)

        if let idx = albums.firstIndex(where: { $0.id == albumId }) {
            albums[idx] = album
        }

        saveAlbums()
    }

    private func scanTagsForAlbum(album: inout Album) async {
        tagScanProgress = album.displayTitle

        var albumMetadataApplied = false

        for i in album.tracks.indices {
            guard !Task.isCancelled else { return }

            let metadata = await metadataExtractor.extractMetadata(from: album.tracks[i].dropboxPath)
            guard !metadata.isEmpty else { continue }

            if let title = metadata["title"], !title.isEmpty {
                album.tracks[i].title = title
            }
            if let trackStr = metadata["track"],
               let num = Int(trackStr.components(separatedBy: "/").first ?? trackStr) {
                album.tracks[i].trackNumber = num
            }
            if let artist = metadata["artist"], !artist.isEmpty {
                album.tracks[i].artist = artist
            }

            if !albumMetadataApplied {
                if let albumTitle = metadata["album"], !albumTitle.isEmpty {
                    album.title = albumTitle
                }
                if let albumArtist = metadata["albumArtist"] ?? metadata["artist"], !albumArtist.isEmpty {
                    album.artist = albumArtist
                }
                if let year = metadata["year"], !year.isEmpty {
                    album.year = year
                }
                if let copyright = metadata["copyright"], !copyright.isEmpty {
                    album.copyright = copyright
                }
                if let label = metadata["label"], !label.isEmpty {
                    album.label = label
                }
                if let genre = metadata["genre"], !genre.isEmpty {
                    album.genre = genre
                }
                albumMetadataApplied = true
            }
        }

        album.tagsLoaded = true

        if album.tracks.contains(where: { $0.trackNumber != nil }) {
            album.tracks.sort { ($0.trackNumber ?? Int.max) < ($1.trackNumber ?? Int.max) }
        }
    }
}
