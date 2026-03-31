import Foundation

@MainActor
final class MetadataExtractor {
    private let service: DropboxBrowserService
    
    private static let id3GenreCodes: [Int: String] = [
        0: "Blues", 1: "Classic Rock", 2: "Country", 3: "Dance", 4: "Disco",
        5: "Funk", 6: "Grunge", 7: "Hip-Hop", 8: "Jazz", 9: "Metal",
        10: "New Age", 11: "Oldies", 12: "Other", 13: "Pop", 14: "R&B",
        15: "Rap", 16: "Reggae", 17: "Rock", 18: "Techno", 19: "Industrial",
        20: "Alternative", 21: "Ska", 22: "Death Metal", 23: "Pranks", 24: "Soundtrack",
        25: "Euro-Techno", 26: "Ambient", 27: "Trip-Hop", 28: "Vocal", 29: "Jazz+Funk",
        30: "Fusion", 31: "Trance", 32: "Classical", 33: "Instrumental", 34: "Acid",
        35: "House", 36: "Game", 37: "Sound Clip", 38: "Gospel", 39: "Noise",
        40: "Alternative Rock", 41: "Bass", 42: "Soul", 43: "Punk", 44: "Space",
        45: "Meditative", 46: "Instrumental Pop", 47: "Instrumental Rock", 48: "Ethnic", 49: "Gothic",
        50: "Darkwave", 51: "Techno-Industrial", 52: "Electronic", 53: "Pop-Folk", 54: "Eurodance",
        55: "Dream", 56: "Southern Rock", 57: "Comedy", 58: "Cult", 59: "Gangsta",
        60: "Top 40", 61: "Christian Rap", 62: "Pop/Funk", 63: "Jungle", 64: "Native American",
        65: "Cabaret", 66: "New Wave", 67: "Psychedelic", 68: "Rave", 69: "Showtunes",
        70: "Trailer", 71: "Lo-Fi", 72: "Tribal", 73: "Acid Punk", 74: "Acid Jazz",
        75: "Polka", 76: "Retro", 77: "Musical", 78: "Rock & Roll", 79: "Hard Rock",
        80: "Folk", 81: "Folk-Rock", 82: "National Folk", 83: "Swing", 84: "Fast Fusion",
        85: "Bebop", 86: "Latin", 87: "Revival", 88: "Celtic", 89: "Bluegrass",
        90: "Avantgarde", 91: "Gothic Rock", 92: "Progressive Rock", 93: "Psychedelic Rock", 94: "Symphonic Rock",
        95: "Slow Rock", 96: "Big Band", 97: "Chorus", 98: "Easy Listening", 99: "Acoustic",
        100: "Humour", 101: "Speech", 102: "Chanson", 103: "Opera", 104: "Chamber Music",
        105: "Sonata", 106: "Symphony", 107: "Booty Brass", 108: "Primus", 109: "Porn Groove",
        110: "Satire", 111: "Slow Jam", 112: "Club", 113: "Tango", 114: "Samba",
        115: "Folklore", 116: "Ballad", 117: "Power Ballad", 118: "Rhythmic Soul", 119: "Freestyle",
        120: "Duet", 121: "Punk Rock", 122: "Drum Solo", 123: "A Cappella", 124: "Euro-House",
        125: "Dance Hall", 126: "Goa", 127: "Drum & Bass", 128: "Club-House", 129: "Hardcore Techno",
        130: "Terror", 131: "Indie", 132: "BritPop", 133: "Negerpunk", 134: "Polsk Punk",
        135: "Beat", 136: "Christian Gangsta Rap", 137: "Heavy Metal", 138: "Black Metal", 139: "Crossover",
        140: "Contemporary Christian", 141: "Christian Rock", 142: "Merengue", 143: "Salsa", 144: "Thrash Metal",
        145: "Anime", 146: "J-Pop", 147: "Synthpop", 148: "Abstract", 149: "Art Rock",
        150: "Baroque", 151: "Bhangra", 152: "Big Beat", 153: "Breakbeat", 154: "Chillout",
        155: "Downtempo", 156: "Dub", 157: "EBM", 158: "Eclectic", 159: "Electro",
        160: "Electroclash", 161: "Emo", 162: "Experimental", 163: "Garage", 164: "Global",
        165: "IDM", 166: "Illbient", 167: "Industro-Goth", 168: "Jam Band", 169: "Krautrock",
        170: "Leftfield", 171: "Lounge", 172: "Mathcore", 173: "Microhouse", 174: "Bac", 175: "Podcast",
        176: "Indie", 177: "Gebet", 178: "Symphonic Rock", 179: "Schlager", 180: "Darkwave",
        181: "Synthpop", 182: "Soft Rock", 183: "Ling", 184: "Hom", 185: "New Wave",
        186: "Neue Deutsche Welle", 187: "Neue Deutsche Härte", 188: "Indb", 189: "K-Pop", 190: "K-Rock",
        191: "Electronica", 192: "Punk", 193: "Drumstep", 194: "Dubstep", 195: "Uplifting Trance",
        196: "Hardstyle", 197: "Jumpstyle", 198: "Liquid", 199: "RnB/Soul", 200: "Jazztronica",
        201: "Nu Jazz", 202: "Vaporwave", 203: "Bassline", 204: "Grime", 205: "Wave",
        206: "Garage", 207: "Stomp & Hanna"
    ]
    
    private func normalizeGenre(_ genre: String) -> String {
        var working = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let code = Int(working), let mappedGenre = Self.id3GenreCodes[code] {
            return mappedGenre
        }
        
        while let openParen = working.firstIndex(of: "("),
              let closeParen = working[openParen...].firstIndex(of: ")") {
            let codeRange = working.index(after: openParen)..<closeParen
            let codeString = String(working[codeRange])
            
            if let code = Int(codeString), let mappedGenre = Self.id3GenreCodes[code] {
                working = mappedGenre + " " + working[..<openParen].trimmingCharacters(in: .whitespaces)
                working = working.trimmingCharacters(in: .whitespaces)
                break
            } else {
                break
            }
        }
        
        return working
    }
    
    init(service: DropboxBrowserService) {
        self.service = service
    }
    
    func extractMetadata(from path: String) async -> [String: String] {
        do {
            let data = try await service.downloadData(path: path, range: 0...1048575)
            guard !data.isEmpty else { return [:] }
            return parseMetadata(bytes: [UInt8](data), path: path)
        } catch {
            return [:]
        }
    }

    func extractArtwork(from path: String) async -> Data? {
        do {
            let data = try await service.downloadData(path: path, range: 0...1048575)
            guard !data.isEmpty else { return nil }
            return extractArtworkFromBytes(bytes: [UInt8](data), path: path)
        } catch {
            return nil
        }
    }

    private func extractArtworkFromBytes(bytes: [UInt8], path: String) -> Data? {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "mp3":
            return extractID3Artwork(bytes: bytes)
        case "m4a", "aac", "alac":
            return extractM4AArtwork(bytes: bytes)
        case "flac":
            return extractFLACArtwork(bytes: bytes)
        default:
            return nil
        }
    }

    // MARK: - Artwork Extraction

    private func extractID3Artwork(bytes: [UInt8]) -> Data? {
        guard bytes.count >= 10,
              bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else { return nil }

        let version = bytes[3]
        guard version == 4 || version == 3 || version == 2 else { return nil }

        let tagSize: Int
        if version >= 3 {
            tagSize = (Int(bytes[6]) << 21) | (Int(bytes[7]) << 14) | (Int(bytes[8]) << 7) | Int(bytes[9])
        } else {
            tagSize = (Int(bytes[6]) << 21) | (Int(bytes[7]) << 14) | (Int(bytes[8]) << 7) | Int(bytes[9])
        }
        guard tagSize > 0, bytes.count >= 10 + tagSize else { return nil }

        let headerSize = version >= 3 ? 10 : 6
        var offset = 10
        let endOffset = min(10 + tagSize, bytes.count)

        var frontCover: Data?
        var firstImage: Data?

        while offset + headerSize <= endOffset {
            guard bytes[offset] != 0 else {
                offset += 1
                continue
            }

            let frameID: String
            let frameHeaderSize: Int
            if version >= 3 {
                frameID = String(bytes: [bytes[offset], bytes[offset+1], bytes[offset+2], bytes[offset+3]], encoding: .ascii) ?? ""
                frameHeaderSize = 10
            } else {
                frameID = String(bytes: [bytes[offset], bytes[offset+1], bytes[offset+2]], encoding: .ascii) ?? ""
                frameHeaderSize = 6
            }
            guard !frameID.isEmpty else {
                offset += 1
                continue
            }

            let frameSize: Int
            if version == 4 {
                frameSize = (Int(bytes[offset+4]) << 21) | (Int(bytes[offset+5]) << 14) | (Int(bytes[offset+6]) << 7) | Int(bytes[offset+7])
            } else if version == 3 {
                frameSize = (Int(bytes[offset+4]) << 24) | (Int(bytes[offset+5]) << 16) | (Int(bytes[offset+6]) << 8) | Int(bytes[offset+7])
            } else {
                frameSize = (Int(bytes[offset+3]) << 16) | (Int(bytes[offset+4]) << 8) | Int(bytes[offset+5])
            }

            guard frameSize > 0, offset + frameHeaderSize + frameSize <= bytes.count else { break }

            if frameID == "APIC" || frameID == "PIC" {
                let contentStart = offset + frameHeaderSize
                let contentEnd = contentStart + frameSize
                let content = Array(bytes[contentStart..<contentEnd])
                if let (pictureType, imageData) = extractAPICData(bytes: content) {
                    if pictureType == 0x03 && frontCover == nil {
                        frontCover = imageData
                    } else if firstImage == nil {
                        firstImage = imageData
                    }
                }
            }

            offset += frameHeaderSize + frameSize
        }

        return frontCover ?? firstImage
    }

    private func extractAPICData(bytes: [UInt8]) -> (UInt8, Data)? {
        guard bytes.count >= 4 else { return nil }
        var offset = 0

        offset = 1  // skip encoding byte

        // Check if MIME type is 3-byte format (ID3v2.2 PIC) or null-terminated string
        if offset + 3 < bytes.count && bytes[offset + 3] == 0 {
            // Null-terminated MIME type
            while offset < bytes.count && bytes[offset] != 0 {
                offset += 1
            }
            if offset < bytes.count { offset += 1 }
        } else {
            // 3-byte format code (e.g., "JPG", "PNG")
            offset += 3
        }

        guard offset < bytes.count else { return nil }
        let pictureType = bytes[offset]
        offset += 1

        // Skip description (null-terminated)
        while offset < bytes.count && bytes[offset] != 0 {
            offset += 1
        }
        if offset < bytes.count { offset += 1 }

        guard offset < bytes.count else { return nil }
        return (pictureType, Data(bytes[offset...]))
    }

    private func extractM4AArtwork(bytes: [UInt8]) -> Data? {
        return extractM4AArtworkRecursive(bytes: bytes, depth: 0)
    }

    private func extractM4AArtworkRecursive(bytes: [UInt8], depth: Int) -> Data? {
        guard depth < 10, bytes.count >= 8 else { return nil }
        var offset = 0

        while offset + 8 <= bytes.count {
            let boxSize = (Int(bytes[offset]) << 24) | (Int(bytes[offset+1]) << 16) | (Int(bytes[offset+2]) << 8) | Int(bytes[offset+3])
            guard boxSize >= 8, offset + boxSize <= bytes.count else { break }

            let boxType = String(bytes: [bytes[offset+4], bytes[offset+5], bytes[offset+6], bytes[offset+7]], encoding: .isoLatin1) ?? ""

            if boxType == "covr" {
                let contentStart = offset + 8
                let contentEnd = offset + boxSize
                if contentStart < contentEnd {
                    return Data(bytes[contentStart..<contentEnd])
                }
            } else if boxType == "moov" || boxType == "meta" || boxType == "ilst" {
                let contentStart = offset + 8
                let contentEnd = offset + boxSize
                var content = Array(bytes[contentStart..<contentEnd])
                if boxType == "meta" && content.count > 4 {
                    content = Array(content.dropFirst(4))
                }
                if let artwork = extractM4AArtworkRecursive(bytes: content, depth: depth + 1) {
                    return artwork
                }
            }

            offset += boxSize
        }
        return nil
    }

    private func extractFLACArtwork(bytes: [UInt8]) -> Data? {
        guard bytes.count >= 4,
              bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 else { return nil }

        var offset = 4

        while offset + 4 < bytes.count {
            let blockHeader = bytes[offset]
            let blockType = blockHeader & 0x7F
            let isLast = (blockHeader & 0x80) != 0

            let blockSize = (Int(bytes[offset+1]) << 16) | (Int(bytes[offset+2]) << 8) | Int(bytes[offset+3])
            guard blockSize > 0, offset + 4 + blockSize <= bytes.count else { break }

            if blockType == 6 {
                return extractFLACPictureData(bytes: Array(bytes[(offset + 4)..<(offset + 4 + blockSize)]))
            }

            offset += 4 + blockSize
            if isLast { break }
        }
        return nil
    }

    private func extractFLACPictureData(bytes: [UInt8]) -> Data? {
        guard bytes.count >= 32 else { return nil }
        var offset = 0
        let pictureType = (Int(bytes[0]) << 24) | (Int(bytes[1]) << 16) | (Int(bytes[2]) << 8) | Int(bytes[3])
        offset = 4
        let mimeLen = (Int(bytes[offset]) << 24) | (Int(bytes[offset+1]) << 16) | (Int(bytes[offset+2]) << 8) | Int(bytes[offset+3])
        offset = 4 + mimeLen + 4
        let descLen = (Int(bytes[offset]) << 24) | (Int(bytes[offset+1]) << 16) | (Int(bytes[offset+2]) << 8) | Int(bytes[offset+3])
        offset = 4 + mimeLen + 4 + 4 + descLen + 16
        guard offset + 4 <= bytes.count else { return nil }
        let imageLen = (Int(bytes[offset]) << 24) | (Int(bytes[offset+1]) << 16) | (Int(bytes[offset+2]) << 8) | Int(bytes[offset+3])
        offset += 4
        guard offset + imageLen <= bytes.count else { return nil }
        return Data(bytes[offset..<(offset + imageLen)])
    }

    private func parseMetadata(bytes: [UInt8], path: String) -> [String: String] {
        let ext = (path as NSString).pathExtension.lowercased()
        
        switch ext {
        case "mp3":
            return parseID3v2(bytes: bytes)
        case "m4a", "aac", "alac":
            return parseM4A(bytes: bytes)
        case "flac":
            return parseFLAC(bytes: bytes)
        case "ogg", "opus":
            return parseVorbis(bytes: bytes)
        case "wav":
            return parseWAV(bytes: bytes)
        case "aiff", "aif":
            return parseAIFF(bytes: bytes)
        default:
            return [:]
        }
    }

    // MARK: - ID3v2 (MP3)

    private func parseID3v2(bytes: [UInt8]) -> [String: String] {
        var result: [String: String] = [:]
        guard bytes.count >= 10 else { return result }

        guard bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else { return result }
        guard bytes[3] == 4 || bytes[3] == 3 else { return result }

        let size = (Int(bytes[6]) << 21) | (Int(bytes[7]) << 14) | (Int(bytes[8]) << 7) | Int(bytes[9])
        guard size > 0, bytes.count >= 10 + size else { return result }

        var offset = 10
        let endOffset = min(10 + size, bytes.count)

        while offset + 14 <= endOffset && offset + 14 <= bytes.count {
            guard bytes[offset] != 0 else { break }
            
            let frameID = String(bytes: [bytes[offset], bytes[offset+1], bytes[offset+2], bytes[offset+3]], encoding: .ascii) ?? ""
            guard !frameID.isEmpty else { break }

            let frameSize: Int
            if bytes[3] == 4 {
                frameSize = (Int(bytes[offset+4]) << 21) | (Int(bytes[offset+5]) << 14) | (Int(bytes[offset+6]) << 7) | Int(bytes[offset+7])
            } else {
                frameSize = (Int(bytes[offset+4]) << 24) | (Int(bytes[offset+5]) << 16) | (Int(bytes[offset+6]) << 8) | Int(bytes[offset+7])
            }

            guard frameSize > 0, offset + 10 + frameSize <= bytes.count else { break }

            let textBytes = Array(bytes[(offset + 10)..<(offset + 10 + frameSize)])
            if let value = extractID3String(bytes: textBytes) {
                switch frameID {
                case "TALB": result["album"] = value
                case "TPE2": result["albumArtist"] = value
                case "TPE1": if result["artist"] == nil { result["artist"] = value }
                case "TDRC", "TYER", "TYE": result["year"] = String(value.prefix(4))
                case "TIT2": result["title"] = value
                case "TRCK": result["track"] = value
                case "TPOS": result["disk"] = value
                case "TCOP": result["copyright"] = value
                case "TPUB": result["label"] = value
                case "TCON": result["genre"] = normalizeGenre(value)
                default: break
                }
            }

            offset += 10 + frameSize
        }

        return result
    }

    private func extractID3String(bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty else { return nil }
        let encoding = bytes[0]
        let textBytes = Array(bytes.dropFirst())
        
        switch encoding {
        case 0x03:
            return String(bytes: textBytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        case 0x01:
            return String(bytes: textBytes, encoding: .utf16)?.trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return String(bytes: textBytes, encoding: .isoLatin1)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - M4A/AAC

    private func parseM4A(bytes: [UInt8]) -> [String: String] {
        var result: [String: String] = [:]
        parseMP4Box(bytes: bytes, into: &result, depth: 0)
        return result
    }

    private func parseMP4Box(bytes: [UInt8], into result: inout [String: String], depth: Int) {
        guard depth < 10 else { return }
        guard bytes.count >= 8 else { return }

        var offset = 0
        
        while offset + 8 <= bytes.count {
            let boxSize = (Int(bytes[offset]) << 24) | (Int(bytes[offset+1]) << 16) | (Int(bytes[offset+2]) << 8) | Int(bytes[offset+3])
            guard boxSize >= 8, offset + boxSize <= bytes.count else { break }
            
            let boxType = String(bytes: [bytes[offset+4], bytes[offset+5], bytes[offset+6], bytes[offset+7]], encoding: .isoLatin1) ?? ""
            
            let contentStart = offset + 8
            let contentEnd = offset + boxSize
            
            if contentStart < contentEnd {
                let content = Array(bytes[contentStart..<contentEnd])
                
                switch boxType {
                case "ilst":
                    parseMP4Metadata(bytes: content, into: &result)
                case "moov", "udta":
                    parseMP4Box(bytes: content, into: &result, depth: depth + 1)
                case "meta":
                    // meta is a FullBox: version(1) + flags(3) = 4 bytes before children
                    if content.count > 4 {
                        parseMP4Box(bytes: Array(content.dropFirst(4)), into: &result, depth: depth + 1)
                    }
                default:
                    break
                }
            }
            
            offset += boxSize
        }
    }

    private func parseMP4Metadata(bytes: [UInt8], into result: inout [String: String]) {
        var offset = 0
        
        while offset + 8 <= bytes.count {
            let boxSize = (Int(bytes[offset]) << 24) | (Int(bytes[offset+1]) << 16) | (Int(bytes[offset+2]) << 8) | Int(bytes[offset+3])
            guard boxSize >= 8, offset + boxSize <= bytes.count else { break }
            
            let boxType = String(bytes: [bytes[offset+4], bytes[offset+5], bytes[offset+6], bytes[offset+7]], encoding: .isoLatin1) ?? ""
            
            if let key = mp4KeyToName(boxType) {
                let contentStart = offset + 8
                let contentEnd = offset + boxSize
                if contentStart < contentEnd {
                    let content = Array(bytes[contentStart..<contentEnd])
                    
                    // gnre box stores genre as 16-bit integer, ©gen stores text
                    if boxType == "gnre" {
                        if let genreCode = extractM4AGenreValue(bytes: content),
                           let genreName = Self.id3GenreCodes[genreCode] {
                            result["genre"] = genreName
                        }
                    } else if key == "genre" {
                        if let value = extractM4AMetaValue(bytes: content) {
                            result[key] = normalizeGenre(value)
                        }
                    } else {
                        if let value = extractM4AMetaValue(bytes: content) {
                            result[key] = value
                        }
                    }
                }
            }
            
            offset += boxSize
        }
    }

    private func mp4KeyToName(_ key: String) -> String? {
        switch key {
        case "©alb": return "album"
        case "aART": return "albumArtist"
        case "©ART": return "artist"
        case "©nam": return "title"
        case "©day": return "year"
        case "©trk": return "track"
        case "disk": return "disk"
        case "©crg": return "disk"
        case "cprt": return "copyright"
        case "©lab": return "label"
        case "©prd": return "label"
        case "©pub": return "label"
        case "lab": return "label"
        case "ldes": return "label"
        case "aSOl": return "labelSort"
        case "©gen": return "genre"
        case "gnre": return "genre"
        default: return nil
        }
    }

    private func extractM4AMetaValue(bytes: [UInt8]) -> String? {
        // Content is nested boxes - look for 'data' box
        var offset = 0
        
        while offset + 8 <= bytes.count {
            let innerBoxSize = (Int(bytes[offset]) << 24) | (Int(bytes[offset+1]) << 16) | (Int(bytes[offset+2]) << 8) | Int(bytes[offset+3])
            guard innerBoxSize >= 8, offset + innerBoxSize <= bytes.count else { break }
            
            let innerBoxType = String(bytes: [bytes[offset+4], bytes[offset+5], bytes[offset+6], bytes[offset+7]], encoding: .isoLatin1) ?? ""
            
            if innerBoxType == "data" {
                // data box: size(4) + "data"(4) + type_indicator(4) + locale(4) + value
                guard innerBoxSize >= 16 else { return nil }
                let valueStart = offset + 16
                guard valueStart < bytes.count else { return nil }
                let valueBytes = Array(bytes[valueStart..<(offset + innerBoxSize)])
                return String(bytes: valueBytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            offset += innerBoxSize
        }
        
        return nil
    }

    private func extractM4AGenreValue(bytes: [UInt8]) -> Int? {
        var offset = 0
        
        while offset + 8 <= bytes.count {
            let innerBoxSize = (Int(bytes[offset]) << 24) | (Int(bytes[offset+1]) << 16) | (Int(bytes[offset+2]) << 8) | Int(bytes[offset+3])
            guard innerBoxSize >= 8, offset + innerBoxSize <= bytes.count else { break }
            
            let innerBoxType = String(bytes: [bytes[offset+4], bytes[offset+5], bytes[offset+6], bytes[offset+7]], encoding: .isoLatin1) ?? ""
            
            if innerBoxType == "data" {
                guard innerBoxSize >= 16 else { return nil }
                let valueStart = offset + 16
                guard valueStart + 1 < bytes.count else { return nil }
                // Parse 16-bit big-endian integer
                let genreCode = (Int(bytes[valueStart]) << 8) | Int(bytes[valueStart + 1])
                return genreCode - 1 // ID3 genres are 0-indexed, M4A stores 1-indexed
            }
            
            offset += innerBoxSize
        }
        
        return nil
    }

    // MARK: - FLAC

    private func parseFLAC(bytes: [UInt8]) -> [String: String] {
        var result: [String: String] = [:]
        guard bytes.count >= 4 else { return result }

        guard bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 else { return result }

        var offset = 4

        while offset + 4 < bytes.count {
            let blockHeader = bytes[offset]
            let blockType = blockHeader & 0x7F

            let blockSize = (Int(bytes[offset+1]) << 16) | (Int(bytes[offset+2]) << 8) | Int(bytes[offset+3])

            guard blockSize > 0, offset + 4 + blockSize <= bytes.count else { break }

            if blockType == 4 {
                let commentBytes = Array(bytes[(offset + 4)..<(offset + 4 + blockSize)])
                parseVorbisComments(bytes: commentBytes, into: &result)
            }

            offset += 4 + blockSize
        }

        return result
    }

    // MARK: - Vorbis (OGG)

    private func parseVorbis(bytes: [UInt8]) -> [String: String] {
        var result: [String: String] = [:]
        
        var offset = 0
        while offset < bytes.count - 27 {
            if bytes[offset] == 0x4F && bytes[offset+1] == 0x67 && bytes[offset+2] == 0x67 && bytes[offset+3] == 0x53 {
                offset += 27
                if offset < bytes.count && bytes[offset] == 0x03 {
                    let endOffset = min(offset + 1025, bytes.count)
                    if offset + 1 < endOffset {
                        let commentBytes = Array(bytes[(offset + 1)..<endOffset])
                        parseVorbisComments(bytes: commentBytes, into: &result)
                    }
                    break
                }
            } else {
                offset += 1
            }
        }
        
        return result
    }

    private func parseVorbisComments(bytes: [UInt8], into result: inout [String: String]) {
        guard bytes.count >= 4 else { return }
        
        var offset = 0
        let vendorLength = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
        offset = 4 + vendorLength
        
        guard offset + 4 <= bytes.count else { return }
        let commentCount = min(Int(bytes[offset]) | Int(bytes[offset+1]) << 8 | Int(bytes[offset+2]) << 16 | Int(bytes[offset+3]) << 24, 100)
        offset += 4
        
        for _ in 0..<commentCount {
            guard offset + 4 <= bytes.count else { break }
            let commentLength = Int(bytes[offset]) | Int(bytes[offset+1]) << 8 | Int(bytes[offset+2]) << 16 | Int(bytes[offset+3]) << 24
            offset += 4
            
            guard commentLength > 0, commentLength < 10000, offset + commentLength <= bytes.count else { break }
            
            let commentBytes = Array(bytes[offset..<(offset + commentLength)])
            offset += commentLength
            
            if let comment = String(bytes: commentBytes, encoding: .utf8),
               let equalIndex = comment.firstIndex(of: "=") {
                let key = String(comment[..<equalIndex]).uppercased()
                let value = String(comment[comment.index(after: equalIndex)...])
                
                switch key {
                case "ALBUM": result["album"] = value
                case "ALBUMARTIST", "BAND", "ALBUM ARTIST":
                    if result["albumArtist"] == nil { result["albumArtist"] = value }
                case "ARTIST": if result["artist"] == nil { result["artist"] = value }
                case "TITLE": result["title"] = value
                case "DATE", "YEAR": result["year"] = String(value.prefix(4))
                case "TRACKNUMBER", "TRACK": result["track"] = value
                case "DISCNUMBER", "DISC", "PARTNUMBER", "PART": result["disk"] = value
                case "COPYRIGHT": result["copyright"] = value
                case "ORGANIZATION", "LABEL", "PUBLISHER": result["label"] = value
                case "GENRE": result["genre"] = normalizeGenre(value)
                default: break
                }
            }
        }
    }

    // MARK: - WAV

    private func parseWAV(bytes: [UInt8]) -> [String: String] {
        var result: [String: String] = [:]
        guard bytes.count >= 44 else { return result }
        
        // Check RIFF header
        guard bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46 else { return result }
        
        // Look for LIST INFO chunk
        var offset = 12
        while offset + 8 < bytes.count {
            let chunkID = String(bytes: [bytes[offset], bytes[offset+1], bytes[offset+2], bytes[offset+3]], encoding: .ascii) ?? ""
            let chunkSize = Int(bytes[offset+4]) | Int(bytes[offset+5]) << 8 | Int(bytes[offset+6]) << 16 | Int(bytes[offset+7]) << 24
            
            if chunkID == "LIST" && offset + 12 + chunkSize <= bytes.count {
                let listType = String(bytes: [bytes[offset+8], bytes[offset+9], bytes[offset+10], bytes[offset+11]], encoding: .ascii) ?? ""
                if listType == "INFO" {
                    var infoOffset = offset + 12
                    let infoEnd = offset + 8 + chunkSize
                    
                    while infoOffset + 8 < infoEnd && infoOffset + 8 < bytes.count {
                        let infoID = String(bytes: [bytes[infoOffset], bytes[infoOffset+1], bytes[infoOffset+2], bytes[infoOffset+3]], encoding: .ascii) ?? ""
                        let infoSize = Int(bytes[infoOffset+4]) | Int(bytes[infoOffset+5]) << 8 | Int(bytes[infoOffset+6]) << 16 | Int(bytes[infoOffset+7]) << 24
                        
                        guard infoSize > 0, infoOffset + 8 + infoSize <= bytes.count else { break }
                        
                        let textBytes = Array(bytes[(infoOffset + 8)..<(infoOffset + 8 + infoSize)])
                        if let text = parseRIFFString(bytes: textBytes) {
                            switch infoID {
                            case "INAM": result["title"] = text
                            case "IART": result["artist"] = text
                            case "IPRD": result["album"] = text
                            case "ICRD": result["year"] = String(text.prefix(4))
                            case "ITRK": result["track"] = text
                            case "ICOP": result["copyright"] = text
                            case "IPUB": result["label"] = text
                            default: break
                            }
                        }
                        
                        infoOffset += 8 + infoSize
                    }
                }
            }
            
            offset += 8 + chunkSize
        }
        
        return result
    }

    private func parseRIFFString(bytes: [UInt8]) -> String? {
        // WAV strings are null-terminated
        var endIndex = bytes.count
        for (index, byte) in bytes.enumerated() {
            if byte == 0 {
                endIndex = index
                break
            }
        }
        let textBytes = Array(bytes[0..<endIndex])
        return String(bytes: textBytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - AIFF

    private func parseAIFF(bytes: [UInt8]) -> [String: String] {
        var result: [String: String] = [:]
        guard bytes.count >= 12 else { return result }
        
        // Check FORM header
        guard bytes[0] == 0x46, bytes[1] == 0x4F, bytes[2] == 0x52, bytes[3] == 0x4D else { return result }
        // Check AIFF format
        guard bytes[8] == 0x41, bytes[9] == 0x49, bytes[10] == 0x46, bytes[11] == 0x46 else { return result }
        
        // Look for ID3 chunk (some AIFF files embed ID3)
        var offset = 12
        while offset + 8 < bytes.count {
            let chunkID = String(bytes: [bytes[offset], bytes[offset+1], bytes[offset+2], bytes[offset+3]], encoding: .ascii) ?? ""
            let chunkSize = Int(bytes[offset+4]) << 24 | Int(bytes[offset+5]) << 16 | Int(bytes[offset+6]) << 8 | Int(bytes[offset+7])
            
            if chunkID == "ID3 " && offset + 8 + chunkSize <= bytes.count {
                let id3Bytes = Array(bytes[(offset + 8)..<(offset + 8 + chunkSize)])
                let id3Result = parseID3v2(bytes: id3Bytes)
                for (key, value) in id3Result {
                    result[key] = value
                }
            }
            
            offset += 8 + chunkSize
            // Chunk sizes in AIFF are odd-padded
            if chunkSize % 2 == 1 && offset + 1 < bytes.count {
                offset += 1
            }
        }
        
        return result
    }
}
