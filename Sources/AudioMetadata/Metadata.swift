import AVFoundation
import Foundation
import OSLog

public class Metadata {
	public init() {}

  public func parseMetadata(fileURL: URL, filePath: String) async -> ParsedAudioMetadata {
    let metadata = await MetadataActor(url: fileURL)
    let duration = await metadata.durationSeconds() ?? 0
    let rawGenreText =
      await metadata.metadataValue(for: [
        .iTunesMetadataUserGenre,
        .quickTimeMetadataGenre,
        .quickTimeUserDataGenre,
        .identifier3GPUserDataGenre,
      ]) ?? ""
    let rawGenreCode = await metadata.metadataValue(for: [.iTunesMetadataGenreID]) ?? ""
    let genre =
      nonEmptyString(rawGenreText) ?? GenreCodes.name(forRawMetadataValue: rawGenreCode) ?? ""

    let rawArtworkData = await metadata.metadataDataValue(for: [
      .commonIdentifierArtwork,
      .quickTimeMetadataArtwork,
    ])

    return await ParsedAudioMetadata(
      filePath: filePath,
      title: metadata.metadataValue(for: [
        .commonIdentifierTitle,
        .iTunesMetadataSongName,
        .quickTimeUserDataTrackName,
      ]) ?? "",
      artist: metadata.metadataValue(for: [
        .commonIdentifierArtist,
        .iTunesMetadataArtist,
        .quickTimeMetadataArtist,
      ]) ?? "",
      album: metadata.metadataValue(for: [
        .commonIdentifierAlbumName,
        .iTunesMetadataAlbum,
        .id3MetadataAlbumTitle,
        .quickTimeUserDataAlbum,
      ]) ?? "",
      albumArtist: metadata.metadataValue(for: [
        .iTunesMetadataAlbumArtist,
        .id3MetadataBand,
        .id3MetadataOriginalArtist,
        .commonIdentifierArtist,
      ]) ?? "",
      trackNumber: metadata.metadataIntValue(for: [
        .iTunesMetadataTrackNumber,
        .id3MetadataTrackNumber,
        .quickTimeUserDataTrack,
      ]),
      diskNumber: metadata.metadataIntValue(for: [
        .iTunesMetadataDiscNumber,
        .id3MetadataPartOfASet,
      ]),
      genre: genre,
      lyrics: metadata.metadataValue(for: [
        .iTunesMetadataLyrics,
        .id3MetadataSynchronizedLyric,
        .id3MetadataUnsynchronizedLyric,
      ]),
      duration: duration,
      year: metadata.metadataYearValue(for: [
        .commonIdentifierCreationDate,
        .quickTimeMetadataYear,
        .quickTimeMetadataCreationDate,
        .quickTimeUserDataCreationDate,
        .iTunesMetadataReleaseDate,
        .id3MetadataYear,
        .id3MetadataDate,
        .id3MetadataRecordingTime,
        .id3MetadataReleaseTime,
        .id3MetadataOriginalReleaseYear,
        .id3MetadataOriginalReleaseTime,
        .identifier3GPUserDataRecordingYear,
      ]),
      artwork: compressArtwork(input: rawArtworkData)
    )
  }

  private func nonEmptyString(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

extension Logger {
	static let subsystem = "com.ghalldev.AudioMetadata"

	static let audioMetadata = Logger(subsystem: subsystem, category: "audio-metadata")
}
