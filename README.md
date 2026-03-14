# AudioMetadata

A Swift library for parsing metadata from various audio formats using AVFoundation.

## Requirements

- iOS 16+ / iPadOS 16+
- macOS 13+
- watchOS 9+
- visionOS 1+
- Swift 6.2+

## Installation

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ghall89/audio-metadata.git", from: "<version>")
]
```

Then add `AudioMetadata` to your target's dependencies.

### Xcode

1. Go to **File → Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/ghall89/audio-metadata`
3. Select your desired version rule and click **Add Package**
4. Add `AudioMetadata` to your target

## Usage

```swift
import AudioMetadata

let parser = Metadata()
let fileURL = URL(fileURLWithPath: "/path/to/track.mp3")

let metadata = await parser.parseMetadata(fileURL: fileURL, filePath: fileURL.path)

print(metadata.title)    // "Song Title"
print(metadata.artist)   // "Artist Name"
print(metadata.album)    // "Album Name"
print(metadata.duration) // Duration in seconds
```

## Parsed Fields

`parseMetadata` returns a `ParsedAudioMetadata` struct with the following fields:

| Field         | Type      | Description                                 |
| ------------- | --------- | ------------------------------------------- |
| `filePath`    | `String`  | Path to the source file                     |
| `title`       | `String`  | Track title                                 |
| `artist`      | `String`  | Track artist                                |
| `album`       | `String`  | Album name                                  |
| `albumArtist` | `String`  | Album artist (may differ from track artist) |
| `trackNumber` | `Int?`    | Track number                                |
| `diskNumber`  | `Int?`    | Disc number                                 |
| `genre`       | `String`  | Genre                                       |
| `lyrics`      | `String?` | Lyrics                                      |
| `duration`    | `Double`  | Duration in seconds                         |
| `year`        | `String?` | Release year                                |
| `artwork`     | `Data?`   | Cover art image data                        |

## Supported Formats

- MP3
- MP4 / M4A / AAC
- FLAC
