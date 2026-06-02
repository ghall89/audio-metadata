import AVFoundation
import Foundation
import OSLog

public class Metadata {
	public init() {}

  public func parseMetadata(fileURL: URL, filePath: String) async -> ParsedAudioMetadata {
    let metadata = await MetadataActor(url: fileURL)
    let duration = await metadata.durationSeconds() ?? 0
    let rawGenreText = await metadata.metadataValue(
      for: [
        .iTunesMetadataUserGenre,
        .quickTimeMetadataGenre,
        .quickTimeUserDataGenre,
        .identifier3GPUserDataGenre,
        .id3MetadataContentType,
      ],
      fallbackKeys: ["GENRE", "genre"]
    ) ?? ""

    let rawGenreCode = await metadata.metadataValue(for: [.iTunesMetadataGenreID]) ?? ""
    let genre =
      nonEmptyString(rawGenreText) ?? GenreCodes.name(forRawMetadataValue: rawGenreCode) ?? ""

    let rawArtworkData = await metadata.metadataDataValue(for: [
      .commonIdentifierArtwork,
      .quickTimeMetadataArtwork,
      .id3MetadataAttachedPicture,
    ])

    return await ParsedAudioMetadata(
      filePath: filePath,
      title: metadata.metadataValue(
        for: [
          .commonIdentifierTitle,
          .iTunesMetadataSongName,
          .quickTimeUserDataTrackName,
          .id3MetadataTitleDescription,
        ],
        fallbackKeys: ["TITLE", "title"]
      ) ?? "",
      artist: metadata.metadataValue(
        for: [
          .commonIdentifierArtist,
          .iTunesMetadataArtist,
          .quickTimeMetadataArtist,
          .id3MetadataLeadPerformer,
        ],
        fallbackKeys: ["ARTIST", "artist"]
      ) ?? "",
      album: metadata.metadataValue(
        for: [
          .commonIdentifierAlbumName,
          .iTunesMetadataAlbum,
          .id3MetadataAlbumTitle,
          .quickTimeUserDataAlbum,
        ],
        fallbackKeys: ["ALBUM", "album"]
      ) ?? "",
      albumArtist: metadata.metadataValue(
        for: [
          .iTunesMetadataAlbumArtist,
          .id3MetadataBand,
          .id3MetadataOriginalArtist,
        ],
        fallbackKeys: ["ALBUMARTIST", "albumartist", "ALBUM ARTIST"]
      ) ?? "",
      trackNumber: metadata.metadataIntValue(
        for: [
          .iTunesMetadataTrackNumber,
          .id3MetadataTrackNumber,
          .quickTimeUserDataTrack,
        ],
        fallbackKeys: ["TRACKNUMBER", "tracknumber"]
      ),
      diskNumber: metadata.metadataIntValue(
        for: [
          .iTunesMetadataDiscNumber,
          .id3MetadataPartOfASet,
        ],
        fallbackKeys: ["DISCNUMBER", "discnumber"]
      ),
      genre: genre,
      lyrics: metadata.metadataValue(
        for: [
          .iTunesMetadataLyrics,
          .id3MetadataSynchronizedLyric,
          .id3MetadataUnsynchronizedLyric,
        ],
        fallbackKeys: ["LYRICS", "lyrics", "UNSYNCEDLYRICS"]
      ),
      duration: duration,
      year: metadata.metadataYearValue(
        for: [
          .quickTimeMetadataYear,
          .quickTimeMetadataCreationDate,
          .iTunesMetadataReleaseDate,
          .id3MetadataYear,
          .id3MetadataDate,
          .id3MetadataRecordingTime,
          .id3MetadataReleaseTime,
          .id3MetadataOriginalReleaseYear,
          .id3MetadataOriginalReleaseTime,
          .identifier3GPUserDataRecordingYear,
        ],
        fallbackKeys: ["DATE", "date", "YEAR", "year"]
      ),
      artwork: compressArtwork(input: rawArtworkData),
			composer: metadata.metadataValue(
				for: [
					.id3MetadataComposer,
					.iTunesMetadataComposer,
					.quickTimeMetadataComposer,
					.quickTimeUserDataComposer,
				],
				fallbackKeys: ["COMPOSER", "composer"]
			),
			copyrightInfo: metadata.metadataValue(
				for: [
					.id3MetadataCopyright,
					.commonIdentifierCopyrights,
					.isoUserDataCopyright,
					.iTunesMetadataCopyright,
					.quickTimeMetadataCopyright,
					.id3MetadataCopyrightInformation,
				],
				fallbackKeys: ["COPYRIGHT", "copyright"]
			),
			publisher: metadata.metadataValue(
				for: [
					.id3MetadataPublisher,
					.commonIdentifierPublisher,
					.iTunesMetadataPublisher,
					.quickTimeMetadataPublisher,
					.quickTimeUserDataPublisher,
				],
				fallbackKeys: ["ORGANIZATION", "organization", "PUBLISHER", "publisher", "LABEL", "label"]
			),
			compilation: metadata.metadataBoolValue(
				for: [.iTunesMetadataDiscCompilation],
				fallbackKeys: ["COMPILATION", "compilation"]
			),
			bpm: metadata.metadataIntValue(
				for: [
					.id3MetadataBeatsPerMinute,
					.iTunesMetadataBeatsPerMin,
				],
				fallbackKeys: ["BPM", "bpm"]
			),
			tempo: metadata.metadataIntValue(for: [.id3MetadataSynchronizedTempoCodes]),
			conductor: metadata.metadataValue(
				for: [.id3MetadataConductor],
				fallbackKeys: ["CONDUCTOR", "conductor"]
			),
			producer: metadata.metadataValue(
				for: [
					.iTunesMetadataProducer,
					.id3MetadataProducedNotice,
					.quickTimeMetadataProducer,
					.quickTimeUserDataProduct,
					.quickTimeUserDataProducer,
				],
				fallbackKeys: ["PRODUCER", "producer"]
			),
			contentRating: metadata.metadataValue(for: [.iTunesMetadataContentRating]),
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
