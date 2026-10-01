import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Geometry only: the icon does not embed artwork from a typeface.
guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift scripts/icon/render-mark.swift <mark.png>")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setAllowsAntialiasing(true)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setLineWidth(88)
context.setStrokeColor(CGColor(gray: 1, alpha: 0.60))
let rear = CGMutablePath()
rear.move(to: CGPoint(x: 545, y: 238))
rear.addLine(to: CGPoint(x: 545, y: 786))
rear.addLine(to: CGPoint(x: 658, y: 786))
rear.addCurve(to: CGPoint(x: 658, y: 488), control1: CGPoint(x: 850, y: 786), control2: CGPoint(x: 850, y: 488))
rear.addLine(to: CGPoint(x: 545, y: 488))
context.addPath(rear)
context.strokePath()
context.setStrokeColor(CGColor(gray: 1, alpha: 1))
context.setLineWidth(100)
let front = CGMutablePath()
front.move(to: CGPoint(x: 280, y: 238))
front.addLine(to: CGPoint(x: 280, y: 786))
front.addLine(to: CGPoint(x: 580, y: 786))
front.move(to: CGPoint(x: 280, y: 512))
front.addLine(to: CGPoint(x: 494, y: 512))
context.addPath(front)
context.strokePath()
let data = NSMutableData()
let writer = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(writer, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(writer))
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
let temporary = destination.deletingLastPathComponent().appendingPathComponent(".mark-\(UUID()).png")
defer { try? FileManager.default.removeItem(at: temporary) }
try (data as Data).write(to: temporary)
let handle = try FileHandle(forWritingTo: temporary)
try handle.synchronize()
try handle.close()
guard rename(temporary.path, destination.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
print("render-mark: \(destination.path)")
