import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
var chunks = Data()
func lengthData(_ length: Int) -> Data {
    var value = UInt32(length).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
for (points, scale, type) in [(16,1,"icp4"), (16,2,"ic11"), (32,1,"icp5"), (32,2,"ic12"), (128,1,"ic07"), (128,2,"ic13"), (256,1,"ic08"), (256,2,"ic14"), (512,1,"ic09"), (512,2,"ic10")] {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.58, blue: 0.97, alpha: 1), ending: NSColor(calibratedRed: 0.10, green: 0.32, blue: 0.77, alpha: 1))!.draw(in: background, angle: -75)
    for x: CGFloat in [184, 528] {
        NSColor.white.withAlphaComponent(0.97).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 236, width: 312, height: 552), xRadius: 36, yRadius: 36).fill()
        NSColor(calibratedRed: 0.77, green: 0.86, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: x + 28, y: 687, width: 256, height: 60), xRadius: 12, yRadius: 12).fill()
        for y: CGFloat in [598, 508, 418, 328] {
            NSColor(calibratedRed: 0.29, green: 0.57, blue: 0.91, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 30, y: y, width: 42, height: 34), xRadius: 6, yRadius: 6).fill()
            NSColor(calibratedRed: 0.73, green: 0.78, blue: 0.85, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 91, y: y + 10, width: 184, height: 14), xRadius: 7, yRadius: 7).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    chunks.append(Data(type.utf8)); chunks.append(lengthData(png.count + 8)); chunks.append(png)
}
var icon = Data("icns".utf8); icon.append(lengthData(chunks.count + 8)); icon.append(chunks)
try icon.write(to: destination)
