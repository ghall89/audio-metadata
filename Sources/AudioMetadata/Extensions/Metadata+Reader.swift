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
        if let stringValue = try? await getMetaDataValue(for: identifier) as? String {
          return stringValue
        }
        if let intValue = try? await getMetaDataValue(for: identifier) as? Int {
          return String(intValue)
        }
      }
      return await rawStringValue(forKeys: fallbackKeys)
    }

		func metadataBoolValue(for identifiers: [AVMetadataIdentifier], fallbackKeys: [String] = []) async -> Bool {
			for identifier in identifiers {
				if let boolValue = try? await getMetaDataValue(for: identifier) as? Bool {
					return boolValue
				}
			}
			return await rawBoolValue(forKeys: fallbackKeys)
		}

    /// Returns the first resolved integer value for the given metadata identifiers.
    ///
    /// Track and disc numbers are stored inconsistently across audio formats:
    /// - MP4/iTunes files encode them as binary atoms, which `getMetaDataValue` decodes to `Int`
    /// - ID3 tags (MP3) may store them as fraction strings like `"3/12"` (track 3 of 12)
    /// - Some formats use plain numeric strings like `"3"`
    ///
    /// This method normalises all three cases, returning the track/disc number as an `Int`
    /// regardless of the underlying format.
    func metadataIntValue(for identifiers: [AVMetadataIdentifier], fallbackKeys: [String] = []) async -> Int? {
      for identifier in identifiers {
        if let intValue = try? await getMetaDataValue(for: identifier) as? Int {
          return intValue
        }
        // Fall back to string parsing for "3" or "3/12" style values
        if let stringValue = try? await getMetaDataValue(for: identifier) as? String {
          let parts = stringValue.split(separator: "/").map {
            $0.trimmingCharacters(in: .whitespaces)
          }
          if let first = parts.first, let number = Int(first) {
            return number
          }
        }
      }
      return await rawIntValue(forKeys: fallbackKeys)
    }

    func metadataDataValue(for identifiers: [AVMetadataIdentifier]) async -> Data? {
      for identifier in identifiers {
        if let dataValue = try? await getMetaDataValue(for: identifier) as? Data {
          return dataValue
        }
      }
      return nil
    }

    func metadataYearValue(for identifiers: [AVMetadataIdentifier], fallbackKeys: [String] = []) async -> String? {
      for identifier in identifiers {
        guard let rawValue = try? await getMetaDataValue(for: identifier) else {
          continue
        }
        if let year = extractYear(from: rawValue) {
          return year
        }
      }
      return await rawYearValue(forKeys: fallbackKeys)
    }

    func durationSeconds() async -> Double? {
      do {
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        return seconds.isFinite ? seconds : nil
      } catch {
        return nil
      }
    }

    // AVFoundation exposes FLAC Vorbis Comments under key space "vorb" with no named constant
    private static let vorbisKeySpace = AVMetadataKeySpace(rawValue: "vorb")

    private func rawStringValue(forKeys keys: [String]) async -> String? {
      for key in keys {
        let items = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: Self.vorbisKeySpace)
        if let item = items.first, let value = try? await item.load(.value) as? String {
          return value
        }
      }
      return nil
    }

    private func rawIntValue(forKeys keys: [String]) async -> Int? {
      for key in keys {
        let items = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: Self.vorbisKeySpace)
        guard let item = items.first, let loaded = try? await item.load(.value) else { continue }
        if let num = loaded as? NSNumber {
          return num.intValue
        }
        if let string = loaded as? String {
          let parts = string.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
          if let first = parts.first, let number = Int(first) {
            return number
          }
        }
      }
      return nil
    }

    private func rawYearValue(forKeys keys: [String]) async -> String? {
      for key in keys {
        let items = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: Self.vorbisKeySpace)
        if let item = items.first, let rawValue = try? await item.load(.value) {
          if let year = extractYear(from: rawValue) {
            return year
          }
        }
      }
      return nil
    }

    private func rawBoolValue(forKeys keys: [String]) async -> Bool {
      for key in keys {
        let items = AVMetadataItem.metadataItems(from: metadata, withKey: key, keySpace: Self.vorbisKeySpace)
        if let item = items.first, let value = try? await item.load(.value) as? String {
          return value == "1"
        }
      }
      return false
    }

    private func getMetaDataValue(
      for identifier: AVMetadataIdentifier,
    ) async throws -> Any? {
      guard
        let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier)
          .first
      else {
        return nil
      }

      let loaded = try await item.load(.value)

      // Special-case iTunes track/disc identifiers which are often stored as binary atoms
      if identifier == .iTunesMetadataTrackNumber || identifier == .iTunesMetadataDiscNumber {
        // 1) If the loader returned Data, try to parse the bytes (common MP4/iTunes format)
        if let data = loaded as? Data {
          let bytes: [UInt8] = .init(data)
          // Typical payload is >= 6 or 8 bytes; bytes[2..3] = number, bytes[4..5] = total (big-endian)
          if bytes.count >= 6 {
            let number = (Int(bytes[2]) << 8) | Int(bytes[3])
            if number != 0 {
              return number
            }
            let lowByteOnly: Int = .init(bytes[3])
            if lowByteOnly != 0 {
              return lowByteOnly
            }
          }
        }

        // 2) If the loader returned a string like "3/12", parse it
        if let stringValue = loaded as? String {
          let parts = stringValue.split(separator: "/").map {
            $0.trimmingCharacters(in: .whitespaces)
          }
          if let first = parts.first, let number = Int(first) {
            return number
          }
        }

        // 3) If the loader returned a numeric type, convert
        if let num = loaded as? NSNumber {
          return num.intValue
        }

        return nil
      }

      if let stringValue = loaded as? String {
        return stringValue
      }
      if let dataValue = loaded as? Data {
        return dataValue
      }
      if let num = loaded as? NSNumber {
        return num.intValue
      }
      return loaded
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
