import AVFoundation
import Foundation
import OSLog

extension Metadata {
  actor MetadataActor {
    var asset: AVURLAsset
    var metadata: [AVMetadataItem] = []

    init(url: URL) async {
      asset = AVURLAsset(url: url)
      do {
        metadata = try await asset.load(.metadata)
      } catch {
        Logger.audioMetadata.error("Unable to parse metadata: \(error.localizedDescription)")
      }
    }

    func metadataValue(for identifiers: [AVMetadataIdentifier], fallbackKeys: [String] = []) async -> String? {
      for identifier in identifiers {
        for loaded in await rawValues(for: identifier) {
          if let text = stringRepresentation(of: loaded), !text.isEmpty {
            return text
          }
        }
      }
      return await rawStringValue(forKeys: fallbackKeys)
    }

    func metadataBoolValue(for identifiers: [AVMetadataIdentifier], fallbackKeys: [String] = []) async -> Bool {
      for identifier in identifiers {
        for loaded in await rawValues(for: identifier) {
          if let boolValue = boolRepresentation(of: loaded) {
            return boolValue
          }
        }
      }
      return await rawBoolValue(forKeys: fallbackKeys)
    }

    /// Returns the first resolved integer value for the given metadata identifiers.
    ///
    /// Track and disc numbers are stored inconsistently across audio formats:
    /// - MP4/iTunes files encode them as binary atoms, which may be as short as 4 bytes
    ///   when the encoder omits the trailing "total count" field
    /// - ID3 tags (MP3) may store them as fraction strings like `"3/12"` (track 3 of 12)
    /// - Some formats use plain numeric strings like `"3"`
    ///
    /// This method normalises all three cases, returning the track/disc number as an `Int`
    /// regardless of the underlying format.
    func metadataIntValue(for identifiers: [AVMetadataIdentifier], fallbackKeys: [String] = []) async -> Int? {
      for identifier in identifiers {
        for loaded in await rawValues(for: identifier) {
          if let intValue = intRepresentation(of: loaded, identifier: identifier) {
            return intValue
          }
        }
      }
      return await rawIntValue(forKeys: fallbackKeys)
    }

    func metadataDataValue(for identifiers: [AVMetadataIdentifier]) async -> Data? {
      for identifier in identifiers {
        for loaded in await rawValues(for: identifier) {
          if let data = loaded as? Data, !data.isEmpty {
            return data
          }
        }
      }
      return nil
    }

    func metadataYearValue(for identifiers: [AVMetadataIdentifier], fallbackKeys: [String] = []) async -> String? {
      for identifier in identifiers {
        for loaded in await rawValues(for: identifier) {
          if let year = extractYear(from: loaded) {
            return year
          }
        }
      }
      return await rawYearValue(forKeys: fallbackKeys)
    }

    /// Reads the classic iTunes numeric genre atom (`gnre`, keyspace `itsk`), which
    /// encodes the ID3v1 genre index **plus one** as a big-endian 16-bit integer.
    /// AVFoundation has no `AVMetadataIdentifier` for this atom — `.iTunesMetadataGenreID`
    /// actually maps to the unrelated, essentially-unused `geID` atom — so it has to be
    /// looked up by its raw key, the same way FLAC Vorbis comments are below.
    func iTunesRawGenreCode() async -> Int? {
      let items = AVMetadataItem.metadataItems(from: metadata, withKey: Self.gnreKey, keySpace: Self.iTunesKeySpace)
      for item in items {
        guard let value = try? await item.load(.value), let data = value as? Data else { continue }
        if let code = beEncodedShort(from: data, at: 0), code != 0 {
          return code
        }
      }
      return nil
    }

    func durationSeconds() async -> Double? {
      do {
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        return seconds.isFinite ? seconds : nil
      } catch {
        Logger.audioMetadata.debug("Unable to load duration: \(error.localizedDescription)")
        return nil
      }
    }

    // AVFoundation exposes FLAC Vorbis Comments under key space "vorb" with no named constant
    private static let vorbisKeySpace = AVMetadataKeySpace(rawValue: "vorb")

    private static let iTunesKeySpace = AVMetadataKeySpace(rawValue: "itsk")
    private static let gnreKey: NSNumber = {
      var code: UInt32 = 0
      for byte in "gnre".utf8 {
        code = (code << 8) | UInt32(byte)
      }
      return NSNumber(value: code)
    }()

    private func rawStringValue(forKeys keys: [String]) async -> String? {
      for key in keys {
        let items = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: Self.vorbisKeySpace)
        for item in items {
          if let value = try? await item.load(.value) as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
              return trimmed
            }
          }
        }
      }
      return nil
    }

    private func rawIntValue(forKeys keys: [String]) async -> Int? {
      for key in keys {
        let items = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: Self.vorbisKeySpace)
        for item in items {
          guard let loaded = try? await item.load(.value) else { continue }
          if let num = loaded as? NSNumber {
            return num.intValue
          }
          if let string = loaded as? String, let number = firstIntComponent(of: string) {
            return number
          }
        }
      }
      return nil
    }

    private func rawYearValue(forKeys keys: [String]) async -> String? {
      for key in keys {
        let items = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: Self.vorbisKeySpace)
        for item in items {
          if let rawValue = try? await item.load(.value), let year = extractYear(from: rawValue) {
            return year
          }
        }
      }
      return nil
    }

    private func rawBoolValue(forKeys keys: [String]) async -> Bool {
      for key in keys {
        let items = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: Self.vorbisKeySpace)
        for item in items {
          guard let value = try? await item.load(.value) as? String else { continue }
          switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
          case "1", "true", "yes":
            return true
          case "0", "false", "no":
            return false
          default:
            continue
          }
        }
      }
      return false
    }

    private func rawValues(for identifier: AVMetadataIdentifier) async -> [Any] {
      let items = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier)
      var values: [Any] = []
      values.reserveCapacity(items.count)
      for item in items {
        do {
          let value: Any = try await item.load(.value) as Any
          values.append(value)
        } catch {
          Logger.audioMetadata.debug("Failed to load metadata item for \(String(describing: identifier), privacy: .public): \(error.localizedDescription)")
        }
      }
      return values
    }

    private func stringRepresentation(of value: Any) -> String? {
      if let string = value as? String {
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      if let number = value as? NSNumber {
        return number.stringValue
      }
      if let data = value as? Data {
        return decodeTextData(data)
      }
      return nil
    }

    private func boolRepresentation(of value: Any) -> Bool? {
      if let bool = value as? Bool {
        return bool
      }
      if let number = value as? NSNumber {
        return number.boolValue
      }
      if let string = value as? String {
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
          return true
        case "0", "false", "no":
          return false
        default:
          return nil
        }
      }
      return nil
    }

    /// MP4/iTunes atoms where the encoder always creates the atom but uses `0` as a
    /// "not actually set" sentinel rather than omitting the atom entirely.
    private static let zeroMeansUnsetIdentifiers: [AVMetadataIdentifier] = [
      .iTunesMetadataTrackNumber,
      .iTunesMetadataDiscNumber,
      .iTunesMetadataBeatsPerMin,
    ]

    private func intRepresentation(of value: Any, identifier: AVMetadataIdentifier) -> Int? {
      let resolved: Int?
      if identifier == .iTunesMetadataTrackNumber || identifier == .iTunesMetadataDiscNumber,
        let data = value as? Data
      {
        resolved = beEncodedShort(from: data, at: 2)
      } else if let number = value as? NSNumber {
        resolved = number.intValue
      } else if let string = value as? String {
        resolved = firstIntComponent(of: string)
      } else if let data = value as? Data, let text = decodeTextData(data) {
        resolved = firstIntComponent(of: text)
      } else {
        resolved = nil
      }

      if resolved == 0, Self.zeroMeansUnsetIdentifiers.contains(identifier) {
        return nil
      }
      return resolved
    }

    /// Reads a big-endian 16-bit integer starting at `byteOffset` from a binary MP4 atom
    /// payload. Used for `trkn`/`disk` (number at offset 2, after 2 reserved bytes) and
    /// `gnre` (number at offset 0, the raw ID3v1 index + 1).
    private func beEncodedShort(from data: Data, at byteOffset: Int) -> Int? {
      let bytes = [UInt8](data)
      guard bytes.count >= byteOffset + 2 else { return nil }
      return (Int(bytes[byteOffset]) << 8) | Int(bytes[byteOffset + 1])
    }

    private func firstIntComponent(of string: String) -> Int? {
      let parts = string.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
      guard let first = parts.first else { return nil }
      return Int(first)
    }

    private func decodeTextData(_ data: Data) -> String? {
      guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
        return nil
      }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
      return trimmed.isEmpty ? nil : trimmed
    }

    private func extractYear(from rawValue: Any) -> String? {
      if let number = rawValue as? Int {
        return normalizedYear(number)
      }

      if let number = rawValue as? NSNumber {
        return normalizedYear(number.intValue)
      }

      if let date = rawValue as? Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let year = calendar.component(.year, from: date)
        return normalizedYear(year)
      }

      if let data = rawValue as? Data, let utf8String = String(data: data, encoding: .utf8) {
        return extractYear(from: utf8String)
      }

      if let stringValue = rawValue as? String {
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(trimmed), let normalized = normalizedYear(number) {
          return normalized
        }
        if trimmed.count >= 4, let year = Int(trimmed.prefix(4)), let normalized = normalizedYear(year) {
          return normalized
        }
        if trimmed.count >= 4, let year = Int(trimmed.suffix(4)), let normalized = normalizedYear(year) {
          return normalized
        }
        if let range = trimmed.range(of: #"\b(1[0-9]{3}|2[0-9]{3})\b"#, options: .regularExpression) {
          return String(trimmed[range])
        }
      }

      return nil
    }

    private func normalizedYear(_ year: Int) -> String? {
      guard (1000...2999).contains(year) else {
        return nil
      }
      return String(year)
    }
  }
}
