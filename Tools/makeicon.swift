// Draws the jtalk2 app icon and writes an .iconset directory.
//
//   swiftc -o makeicon Tools/makeicon.swift && ./makeicon path/to/jtalk2.iconset
//
// A speech bubble with a text caret in it: what the app is, in one shape that
// survives being scaled down to 16 points.

import AppKit

let deepBlue = CGColor(srgbRed: 0.13, green: 0.24, blue: 0.62, alpha: 1)
let paleBlue = CGColor(srgbRed: 0.40, green: 0.56, blue: 0.98, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

func draw(size s: CGFloat, into ctx: CGContext) {
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // The rounded plate, at roughly the proportions macOS expects.
    let inset = s * 0.098
    let side = s - inset * 2
    let plate = CGRect(x: inset, y: inset, width: side, height: side)
    let platePath = CGPath(roundedRect: plate, cornerWidth: side * 0.2245,
                           cornerHeight: side * 0.2245, transform: nil)
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [paleBlue, deepBlue] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Speech bubble, with its tail merged into the same filled path.
    let bubble = CGRect(x: s * 0.215, y: s * 0.365, width: s * 0.57, height: s * 0.40)
    let bubblePath = CGMutablePath()
    bubblePath.addRoundedRect(in: bubble, cornerWidth: s * 0.095, cornerHeight: s * 0.095)
    bubblePath.move(to: CGPoint(x: s * 0.325, y: bubble.minY + s * 0.03))
    bubblePath.addLine(to: CGPoint(x: s * 0.275, y: s * 0.215))
    bubblePath.addLine(to: CGPoint(x: s * 0.475, y: bubble.minY + s * 0.03))
    bubblePath.closeSubpath()
    ctx.setFillColor(white)
    ctx.addPath(bubblePath)
    ctx.fillPath()

    // Two lines of text with the caret sitting at the end of the second, so the
    // bubble reads as a message being typed rather than as punctuation.
    ctx.setFillColor(deepBlue)
    func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let rect = CGRect(x: s * x, y: s * y, width: s * width, height: s * height)
        let radius = min(rect.width, rect.height) / 2
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius,
                           cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }
    bar(x: 0.295, y: 0.585, width: 0.41, height: 0.058)
    bar(x: 0.295, y: 0.465, width: 0.225, height: 0.058)
    bar(x: 0.558, y: 0.439, width: 0.050, height: 0.110)
}

func render(pixels: Int, to url: URL) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not make a \(pixels)px bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    draw(size: CGFloat(pixels), into: context.cgContext)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(pixels)px png")
    }
    try! png.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "jtalk2.iconset")
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    render(pixels: points, to: out.appendingPathComponent("icon_\(points)x\(points).png"))
    render(pixels: points * 2, to: out.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
print("wrote \(out.path)")
