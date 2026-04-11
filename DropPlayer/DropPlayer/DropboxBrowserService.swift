import Foundation
import SwiftyDropbox

/// Wraps all Dropbox API calls: folder listing, metadata and temporary link fetching.
actor DropboxBrowserService {
    static let shared = DropboxBrowserService()
    private init() {}

    private var client: DropboxClient? {
        DropboxClientsManager.authorizedClient
    }

    // MARK: - Temporary link cache

    private struct CachedLink {
        let url: URL
        let expiry: Date
    }
    private var linkCache: [String: CachedLink] = [:]
    private let linkTTL: TimeInterval = 3600 // Dropbox links are valid for 4 hours; cache for 1h

    // MARK: - Folder listing

    /// Returns all immediate child entries (files & folders) at ``path``.
    func listFolder(path: String) async throws -> [Files.Metadata] {
        guard let client else { throw DropboxError.notAuthenticated }

        return try await withCheckedThrowingContinuation { continuation in
            client.files.listFolder(path: path == "/" ? "" : path).response { result, error in
                if let error {
                    continuation.resume(throwing: DropboxError.api(error.description))
                    return
                }
                guard let result else {
                    continuation.resume(throwing: DropboxError.emptyResponse)
                    return
                }
                // Handle pagination by collecting all pages
                let entries = result.entries
                if result.hasMore {
                    Task {
                        do {
                            let more = try await self.continueListFolder(cursor: result.cursor)
                            continuation.resume(returning: entries + more)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    continuation.resume(returning: entries)
                }
            }
        }
    }

    private func continueListFolder(cursor: String) async throws -> [Files.Metadata] {
        guard let client else { throw DropboxError.notAuthenticated }
        var allEntries: [Files.Metadata] = []

        return try await withCheckedThrowingContinuation { continuation in
            client.files.listFolderContinue(cursor: cursor).response { result, error in
                if let error {
                    continuation.resume(throwing: DropboxError.api(error.description))
                    return
                }
                guard let result else {
                    continuation.resume(throwing: DropboxError.emptyResponse)
                    return
                }
                allEntries += result.entries
                if result.hasMore {
                    Task {
                        do {
                            let more = try await self.continueListFolder(cursor: result.cursor)
                            continuation.resume(returning: allEntries + more)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    continuation.resume(returning: allEntries)
                }
            }
        }
    }

    // MARK: - Temporary streaming link

    /// Returns a short-lived HTTPS URL that can be used to stream a file.
    /// Results are cached for 1 hour to avoid redundant API calls within the same session.
    func temporaryLink(for path: String) async throws -> URL {
        if let cached = linkCache[path], cached.expiry > Date() {
            return cached.url
        }
        guard let client else { throw DropboxError.notAuthenticated }

        let url = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            client.files.getTemporaryLink(path: path).response { result, error in
                if let error {
                    continuation.resume(throwing: DropboxError.api(error.description))
                    return
                }
                guard let urlString = result?.link, let url = URL(string: urlString) else {
                    continuation.resume(throwing: DropboxError.emptyResponse)
                    return
                }
                continuation.resume(returning: url)
            }
        }
        linkCache[path] = CachedLink(url: url, expiry: Date().addingTimeInterval(linkTTL))
        return url
    }

    /// Invalidates the cached temporary link for a path (e.g. after a 401/403 error).
    func invalidateCachedLink(for path: String) {
        linkCache.removeValue(forKey: path)
    }

    // MARK: - Album art download

    /// Downloads the raw bytes of a file (used for cover art images, keep small).
    func downloadData(path: String) async throws -> Data {
        guard let client else { throw DropboxError.notAuthenticated }

        return try await withCheckedThrowingContinuation { continuation in
            client.files.download(path: path).response { result, error in
                if let error {
                    continuation.resume(throwing: DropboxError.api(error.description))
                    return
                }
                guard let data = result?.1 else {
                    continuation.resume(throwing: DropboxError.emptyResponse)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    /// Downloads a range of bytes from a file (for reading audio metadata headers).
    func downloadData(path: String, range: ClosedRange<Int>) async throws -> Data {
        let url = try await temporaryLink(for: path)
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 206 || httpResponse.statusCode == 200 else {
            throw DropboxError.api("Failed to download range")
        }
        
        return data
    }
}

enum DropboxError: LocalizedError {
    case notAuthenticated
    case emptyResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in to Dropbox."
        case .emptyResponse: return "Received an empty response from Dropbox."
        case .api(let msg): return msg
        }
    }
}
