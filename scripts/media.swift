import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1])
func save(_ image: CGImage, _ relative: String) {
    let url = root.appendingPathComponent(relative)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    precondition(CGImageDestinationFinalize(dest))
}
func poster(_ id: String, _ time: Double) throws {
    let asset = AVURLAsset(url: root.appendingPathComponent("originals/\(id).mp4"))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.maximumSize = CGSize(width: 1920, height: 1080)
    let frame = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
    save(frame, "posters/\(id).jpg")
    print("poster \(id): \(frame.width)×\(frame.height)")
}
func convertGIF(_ id: String) throws {
    let source = CGImageSourceCreateWithURL(root.appendingPathComponent("originals/\(id).gif") as CFURL, nil)!
    let count = CGImageSourceGetCount(source)
    let first = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let w = first.width, h = first.height
    let output = root.appendingPathComponent("media/\(id).mp4")
    if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5500000, AVVideoMaxKeyFrameIntervalKey: 25]])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
    writer.add(input); precondition(writer.startWriting()); writer.startSession(atSourceTime: .zero)
    var elapsed = 0.0
    for i in 0..<count {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.003) }
        autoreleasepool {
            let image = CGImageSourceCreateImageAtIndex(source, i, nil)!
            var pb: CVPixelBuffer?
            precondition(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb) == kCVReturnSuccess)
            CVPixelBufferLockBaseAddress(pb!, [])
            let c = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: w, height: h, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
            c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            CVPixelBufferUnlockBaseAddress(pb!, [])
            precondition(adaptor.append(pb!, withPresentationTime: CMTime(seconds: elapsed, preferredTimescale: 600)))
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            elapsed += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.08
            if i == Int(Double(count) * 0.7) { save(image, "posters/\(id).jpg") }
        }
    }
    writer.endSession(atSourceTime: CMTime(seconds: elapsed, preferredTimescale: 600)); input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }; done.wait()
    guard writer.status == .completed else { throw writer.error! }
    print("converted \(id): \(count) frames / \(elapsed) seconds")
}
try poster("line-reveal", 5.5)
try poster("wind", 5.5)
try poster("still", 5.5)
try convertGIF("white-wind")
try convertGIF("white-still")
