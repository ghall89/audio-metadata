import AudioMetadata
import Foundation
import UniformTypeIdentifiers

let args = CommandLine.arguments

guard args.count == 2 else {
	print("Usage: audiometa <path-to-audio-file>")
	exit(1)
}

let path = args[1]
let url = URL(fileURLWithPath: path)

guard FileManager.default.fileExists(atPath: path) else {
	print("Error: File not found: \(path)")
	exit(1)
}

guard
	let fileType = UTType(filenameExtension: url.pathExtension),
	fileType.conforms(to: .audio)
else {
	print("Error: Not a valid audio file: \(path)")
	exit(1)
}

let parser = Metadata()
let metadata = await parser.parseMetadata(fileURL: url, filePath: path)

guard metadata.duration > 0 else {
	print("Error: Could not read audio data from: \(path)")
	exit(1)
}

func formatDuration(_ seconds: Double) -> String {
	let m = Int(seconds) / 60
	let s = Int(seconds) % 60
	return String(format: "%d:%02d", m, s)
}

func field(_ label: String, _ value: String) {
	print(String(format: "%-14@ %@", (label + ":") as NSString, value))
}

field("Title", metadata.title.isEmpty ? "(unknown)" : metadata.title)
field("Artist", metadata.artist.isEmpty ? "(unknown)" : metadata.artist)
field("Album", metadata.album.isEmpty ? "(unknown)" : metadata.album)
field("Album Artist", metadata.albumArtist.isEmpty ? "(unknown)" : metadata.albumArtist)

if let track = metadata.trackNumber {
	field("Track", String(track))
}
if let disk = metadata.diskNumber {
	field("Disk", String(disk))
}
if !metadata.genre.isEmpty {
	field("Genre", metadata.genre)
}
if let year = metadata.year {
	field("Year", year)
}

field("Duration", formatDuration(metadata.duration))

if let artwork = metadata.artwork {
	field("Artwork", "\(artwork.count) bytes")
} else {
	field("Artwork", "none")
}

if let lyrics = metadata.lyrics, !lyrics.isEmpty {
	field("Lyrics", "(embedded)")
}
