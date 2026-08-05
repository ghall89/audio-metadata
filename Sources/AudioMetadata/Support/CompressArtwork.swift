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
import ImageIO

public func compressArtwork(
	input: Data?,
	max maxDimension: CGFloat = 900,
	quality compressionQuality: CGFloat = 0.6,
) -> Data? {
	guard let artworkData = input,
		  let source = CGImageSourceCreateWithData(artworkData as CFData, nil),
		  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

	let originalWidth = CGFloat(cgImage.width)
	let originalHeight = CGFloat(cgImage.height)

	if originalWidth <= maxDimension, originalHeight <= maxDimension {
		return jpegData(from: cgImage, quality: compressionQuality)
	}

	let scale = min(maxDimension / originalWidth, maxDimension / originalHeight)
	let newSize = CGSize(
		width: floor(originalWidth * scale),
		height: floor(originalHeight * scale))

	guard let resized = resized(cgImage, to: newSize) else {
		return jpegData(from: cgImage, quality: compressionQuality)
	}

	return jpegData(from: resized, quality: compressionQuality)
}

private func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
	guard let context = CGContext(
		data: nil,
		width: Int(size.width),
		height: Int(size.height),
		bitsPerComponent: 8,
		bytesPerRow: 0,
		space: CGColorSpaceCreateDeviceRGB(),
		bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
	) else { return nil }

	context.interpolationQuality = .high
	context.draw(image, in: CGRect(origin: .zero, size: size))
	return context.makeImage()
}

private func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
	let bitmap = NSBitmapImageRep(cgImage: image)
	return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
}
#endif
