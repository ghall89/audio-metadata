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

    func metadataValue(for identifiers: [AVMetadataIdentifier]) async -> String? {
      for identifier in identifiers {
        if let stringValue = try? await getMetaDataValue(for: identifier) as? String {
          return stringValue
        }
        // If underlying is Int (numeric metadata normalized by getMetaDataValue), convert to String
        if let intValue = try? await getMetaDataValue(for: identifier) as? Int {
          return String(intValue)
        }
      }
      return nil
    }
		
		func metadataBoolValue(for identifiers: [AVMetadataIdentifier]) async -> Bool {
			for identifier in identifiers {
				if let boolValue = try? await getMetaDataValue(for: identifier) as? Bool {
					return boolValue
				}
			}
			
			// if no value, just set to false
			return false
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
    func metadataIntValue(for identifiers: [AVMetadataIdentifier]) async -> Int? {
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
      return nil
    }

    func metadataDataValue(for identifiers: [AVMetadataIdentifier]) async -> Data? {
      for identifier in identifiers {
        if let dataValue = try? await getMetaDataValue(for: identifier) as? Data {
          return dataValue
        }
      }
      return nil
    }

    func metadataYearValue(for identifiers: [AVMetadataIdentifier]) async -> String? {
      for identifier in identifiers {
        guard let rawValue = try? await getMetaDataValue(for: identifier) else {
          continue
        }
				
				print(identifier)
				
        if let year = extractYear(from: rawValue) {
          return year
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
        return nil
      }
    }

    private func getMetaDataValue(
      for identifier: AVMetadataIdentifier,
    ) async throws -> Any? {
      // Find the first metadata item matching the identifier
      guard
        let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier)
          .first
      else {
        return nil
      }

      // Load the underlying value
      let loaded = try await item.load(.value)

      // Special-case iTunes track/disc identifiers which are often stored as binary atoms
      if identifier == .iTunesMetadataTrackNumber || identifier == .iTunesMetadataDiscNumber {
        // 1) If the loader returned Data, try to parse the bytes (common MP4/iTunes format)
        if let data = loaded as? Data {
          let bytes: [UInt8] = .init(data)
          // Typical payload is >= 6 or 8 bytes; bytes[2..3] = number, bytes[4..5] = total (big-endian)
          if bytes.count >= 6 {
            let number = (Int(bytes[2]) << 8) | Int(bytes[3])
            // If number is 0 but bytes[3] was nonzero, fallback to low byte only
            if number != 0 {
              return number
            }
            let lowByteOnly: Int = .init(bytes[3])
            if lowByteOnly != 0 {
              return lowByteOnly
            }
            // else continue to other fallbacks
          }
          // If parsing fails, fall through to other cases
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

        // Otherwise, no usable value
        return nil
      }

      // Default behavior for other identifiers:
      // return Data, String, NSNumber, etc. as loaded
      if let stringValue = loaded as? String {
        return stringValue
      }
      if let dataValue = loaded as? Data {
        return dataValue
      }
      if let num = loaded as? NSNumber {
        return num.intValue
      }  // normalize to Int when appropriate
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
        // Try first 4 characters (YYYY-DD-MM, YYYY-MM-DD, etc.)
        if trimmed.count >= 4, let year = Int(trimmed.prefix(4)), let normalized = normalizedYear(year) {
          return normalized
        }
        // Try last 4 characters (DD-MM-YYYY, MM-DD-YYYY, etc.)
        if trimmed.count >= 4, let year = Int(trimmed.suffix(4)), let normalized = normalizedYear(year) {
          return normalized
        }
        // Fallback: find any valid 4-digit year
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
