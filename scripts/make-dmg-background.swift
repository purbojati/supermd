// Renders the DMG installer background: a soft neutral canvas with a thin
// arrow pointing from the app icon position to the Applications shortcut.
// Run as: swift scripts/make-dmg-background.swift <output.png> [@scale]
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: make-dmg-background.swift <out.png> [scale]\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[1]
let scale: CGFloat = args.count >= 3 ? CGFloat(Double(args[2]) ?? 1.0) : 1.0

let baseWidth: CGFloat = 540
let baseHeight: CGFloat = 380
let size = NSSize(width: baseWidth * scale, height: baseHeight * scale)

let image = NSImage(size: size)
image.lockFocus()

// Background — soft warm white.
NSColor(calibratedRed: 0.985, green: 0.982, blue: 0.978, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

// Icons in the DMG are placed by create-dmg in Finder's top-down coordinate
// system at y=200. AppKit's lockFocus is bottom-up, so flip it.
let iconFinderY: CGFloat = 200
let centerY = (baseHeight - iconFinderY) * scale
let arrowStartX = 215 * scale
let arrowEndX = 330 * scale

let arrowColor = NSColor(calibratedWhite: 0.62, alpha: 1)
arrowColor.setStroke()

let shaft = NSBezierPath()
shaft.lineWidth = 2.5 * scale
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: arrowStartX, y: centerY))
shaft.line(to: NSPoint(x: arrowEndX, y: centerY))
shaft.stroke()

let head = NSBezierPath()
head.lineWidth = 2.5 * scale
head.lineCapStyle = .round
head.lineJoinStyle = .round
let headSize: CGFloat = 12 * scale
head.move(to: NSPoint(x: arrowEndX - headSize, y: centerY + headSize * 0.7))
head.line(to: NSPoint(x: arrowEndX, y: centerY))
head.line(to: NSPoint(x: arrowEndX - headSize, y: centerY - headSize * 0.7))
head.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render png\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
