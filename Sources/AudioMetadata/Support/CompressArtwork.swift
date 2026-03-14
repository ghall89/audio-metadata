#if canImport(UIKit)
import UIKit

public func compressArtwork(
	input: Data?,
	max maxDimension: CGFloat = 900,
	quality compressionQuality: CGFloat = 0.6,
) -> Data? {
	guard let artworkData = input,
		  let image = UIImage(data: artworkData) else { return nil }

	let originalSize = image.size

	if originalSize.width <= maxDimension, originalSize.height <= maxDimension {
		return image.jpegData(compressionQuality: compressionQuality)
	}

	let scale = min(maxDimension / originalSize.width, maxDimension / originalSize.height)
	let newSize = CGSize(
		width: floor(originalSize.width * scale),
		height: floor(originalSize.height * scale))

	let format: UIGraphicsImageRendererFormat = .default()
	format.scale = 1.0
	return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
		image.draw(in: CGRect(origin: .zero, size: newSize))
	}.jpegData(compressionQuality: compressionQuality)
}

#elseif canImport(AppKit)
import AppKit

public func compressArtwork(
	input: Data?,
	max maxDimension: CGFloat = 900,
	quality compressionQuality: CGFloat = 0.6,
) -> Data? {
	guard let artworkData = input,
		  let image = NSImage(data: artworkData) else { return nil }

	let originalSize = image.size

	if originalSize.width <= maxDimension, originalSize.height <= maxDimension {
		return jpegData(from: image, quality: compressionQuality)
	}

	let scale = min(maxDimension / originalSize.width, maxDimension / originalSize.height)
	let newSize = CGSize(
		width: floor(originalSize.width * scale),
		height: floor(originalSize.height * scale))

	let resized = NSImage(size: newSize)
	resized.lockFocus()
	image.draw(in: CGRect(origin: .zero, size: newSize))
	resized.unlockFocus()

	return jpegData(from: resized, quality: compressionQuality)
}

private func jpegData(from image: NSImage, quality: CGFloat) -> Data? {
	guard let tiff = image.tiffRepresentation,
		  let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
	return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
}
#endif
