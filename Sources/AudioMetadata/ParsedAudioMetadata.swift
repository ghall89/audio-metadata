import Foundation

public struct ParsedAudioMetadata: Sendable {
	public var filePath: String
	public var title: String
	public var artist: String
	public var album: String
	public var albumArtist: String
	public var trackNumber: Int?
	public var diskNumber: Int?
	public var genre: String
	public var lyrics: String?
	public var duration: Double
	public var year: String?
	public var artwork: Data?
}
