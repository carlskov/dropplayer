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

    private let service = DropboxBrowserService.shared
    private var artworkCache: [String: UIImage] = [:]
    private let cacheKey = "CachedAlbums"
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
        isScanning = true
        scanError = nil
        albums = []

        do {
            var discovered: [Album] = []
            for path in paths {
                let results = try await scanFolder(path: path, depth: 0)
                discovered.append(contentsOf: results)
            }
            albums = discovered.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
            saveAlbums()
        } catch {
            scanError = error.localizedDescription
        }

        isScanning = false
    }

    func loadTrackMetadata(for track: Track) async -> (artist: String?, title: String?) {
        let metadata = await metadataExtractor.extractMetadata(from: track.dropboxPath)
        let artist = metadata["artist"].flatMap { $0.isEmpty ? nil : $0 }
        let title = metadata["title"].flatMap { $0.isEmpty ? nil : $0 }
        return (artist, title)
    }

    func loadArtwork(for album: Album) async -> UIImage? {
        guard let artPath = album.artworkDropboxPath else { return nil }
        if let cached = artworkCache[artPath] { return cached }
        guard let data = try? await service.downloadData(path: artPath),
              let image = UIImage(data: data) else { return nil }
        artworkCache[artPath] = image
        return image
    }

    // MARK: - Caching

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
            // This folder is an album
            let folderName = lastPathComponent(path)
            var album = Album(
                id: path,
                folderPath: path,
                folderName: folderName,
                title: "",
                artist: "",
                year: nil,
                tracks: [],
                artworkDropboxPath: preferredArtworkPath(from: imageFiles)
            )

            // Try to extract metadata from first audio file
            if let firstFile = audioFiles.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }).first {
                let metadata = await metadataExtractor.extractMetadata(from: firstFile.pathLower ?? firstFile.name)
                if let albumTitle = metadata["album"], !albumTitle.isEmpty { album.title = albumTitle }
                if let artist = metadata["albumArtist"] ?? metadata["artist"], !artist.isEmpty { album.artist = artist }
                if let year = metadata["year"], !year.isEmpty { album.year = year }
            }

            // Fall back to folder name parsing if needed
            if album.title.isEmpty || album.artist.isEmpty {
                parseAlbumMetadata(into: &album, folderName: folderName)
            }

            album.tracks = audioFiles
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { makeTrack(from: $0) }

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
        let nameWithoutExt = ((name as NSString).deletingPathExtension).lowercased()
        let ext = (name as NSString).pathExtension.lowercased()
        return artworkFileNames.contains(nameWithoutExt) && artworkExtensions.contains(ext)
    }

    private func preferredArtworkPath(from files: [Files.FileMetadata]) -> String? {
        // Prefer cover.jpg > folder.jpg > any other match
        let preferred = ["cover", "folder", "front", "album", "artwork", "albumart"]
        for name in preferred {
            for ext in ["jpg", "jpeg", "png", "webp"] {
                if let match = files.first(where: { $0.name.lowercased() == "\(name).\(ext)" }) {
                    return match.pathLower ?? match.name
                }
            }
        }
        return files.first.flatMap { $0.pathLower ?? $0.name }
    }

    private func makeTrack(from file: Files.FileMetadata) -> Track {
        let path = file.pathLower ?? file.name
        let name = file.name
        let nameWithoutExt = (name as NSString).deletingPathExtension

        // Simple parse: "01 - Track Title" or "01. Track Title" or "Track Title"
        var trackNumber: Int?
        var title = nameWithoutExt

        let patterns = [
            #"^(\d+)[.\- ]+(.+)$"#,
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: nameWithoutExt, range: NSRange(nameWithoutExt.startIndex..., in: nameWithoutExt)) {
                if let numRange = Range(match.range(at: 1), in: nameWithoutExt),
                   let titleRange = Range(match.range(at: 2), in: nameWithoutExt) {
                    trackNumber = Int(nameWithoutExt[numRange])
                    title = String(nameWithoutExt[titleRange])
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
            durationSeconds: nil
        )
    }

    /// Tries to infer album title and artist from a folder name like "Artist - Album (Year)".
    private func parseAlbumMetadata(into album: inout Album, folderName: String) {
        // Pattern: "Artist - Album Title (Year)"
        let pattern = #"^(.+?)\s+[-–]\s+(.+?)(?:\s+\((\d{4})\))?$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: folderName, range: NSRange(folderName.startIndex..., in: folderName)) {
            if let artistRange = Range(match.range(at: 1), in: folderName) {
                album.artist = String(folderName[artistRange])
            }
            if let titleRange = Range(match.range(at: 2), in: folderName) {
                album.title = String(folderName[titleRange])
            }
            if match.numberOfRanges > 3, let yearRange = Range(match.range(at: 3), in: folderName), !yearRange.isEmpty {
                album.year = String(folderName[yearRange])
            }
        } else {
            // No dash separator — use folder name as album title
            album.title = folderName
        }
    }

    private func lastPathComponent(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
