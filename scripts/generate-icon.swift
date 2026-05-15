#!/usr/bin/env swift
// Generates light + dark AppIcon iconsets and (via iconutil at the end)
// the two .icns files the bundle ships:
//
//   Resources/AppIcon.icns       (light)
//   Resources/AppIcon-Dark.icns  (dark)
//
// The light icon is used by Finder and as the default. At runtime the app
// observes NSApp.effectiveAppearance and swaps NSApp.applicationIconImage
// to the dark variant when the system is in Dark Mode, so the Dock and
// About panel always match the current appearance.

import AppKit
import CoreGraphics
import Foundation

enum IconVariant: String { case light, dark }

let fm = FileManager.default

struct Palette {
    let top: NSColor
    let bottom: NSColor
    let text: NSColor
    let highlightAlpha: CGFloat
    let edgeAlpha: CGFloat
}

let lightPalette = Palette(
    top:    NSColor(srgbRed: 244/255, green: 142/255, blue: 188/255, alpha: 1),
    bottom: NSColor(srgbRed: 168/255, green:  24/255, blue:  78/255, alpha: 1),
    text:   NSColor(srgbRed: 1.0,     green: 0.984,    blue: 0.992,   alpha: 1),
    highlightAlpha: 0.22,
    edgeAlpha: 0.14
)

let darkPalette = Palette(
    top:    NSColor(srgbRed:  46/255, green:  22/255, blue:  32/255, alpha: 1),
    bottom: NSColor(srgbRed:  18/255, green:   9/255, blue:  14/255, alpha: 1),
    text:   NSColor(srgbRed: 240/255, green: 106/255, blue: 170/255, alpha: 1),
    highlightAlpha: 0.10,
    edgeAlpha: 0.08
)

func drawIcon(pixels: CGFloat, variant: IconVariant) -> Data {
    let palette = variant == .light ? lightPalette : darkPalette
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixels), pixelsHigh: Int(pixels),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("Failed to allocate bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Squircle background with diagonal gradient
    let cornerRadius = pixels * 0.2237
    let bgPath = CGPath(
        roundedRect: rect,
        cornerWidth: cornerRadius, cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [palette.top.cgColor, palette.bottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: pixels),
        end:   CGPoint(x: pixels, y: 0),
        options: []
    )

    let highlight = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor.white.withAlphaComponent(palette.highlightAlpha).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        highlight,
        start: CGPoint(x: 0, y: pixels),
        end:   CGPoint(x: 0, y: pixels * 0.48),
        options: []
    )

    let fontSize = pixels * 0.56
    var fontDescriptor = NSFontDescriptor(name: "New York", size: fontSize)
    if let bold = fontDescriptor.withSymbolicTraits(.bold) as NSFontDescriptor? {
        fontDescriptor = bold
    }
    let font = NSFont(descriptor: fontDescriptor, size: fontSize)
        ?? NSFont(name: "Georgia-Bold", size: fontSize)
        ?? NSFont.boldSystemFont(ofSize: fontSize)

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let textAttrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: palette.text,
        .kern: -pixels * 0.012,
        .paragraphStyle: paragraph
    ]
    let text = NSAttributedString(string: "md", attributes: textAttrs)
    let textSize = text.size()
    let textRect = CGRect(
        x: (pixels - textSize.width) / 2,
        y: (pixels - textSize.height) / 2 - pixels * 0.045,
        width:  textSize.width,
        height: textSize.height
    )

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -pixels * 0.005),
        blur: pixels * 0.012,
        color: NSColor.black.withAlphaComponent(0.22).cgColor
    )
    text.draw(in: textRect)
    ctx.restoreGState()

    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(CGPath(
        roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
        cornerWidth: cornerRadius, cornerHeight: cornerRadius,
        transform: nil
    ))
    ctx.setLineWidth(max(1, pixels * 0.0015))
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(palette.edgeAlpha).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to export PNG")
    }
    return png
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024)
]

for variant in [IconVariant.light, .dark] {
    let suffix = variant == .light ? "" : "-Dark"
    let iconsetDir = "Resources/AppIcon\(suffix).iconset"
    try? fm.removeItem(atPath: iconsetDir)
    try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

    print("== \(variant.rawValue.uppercased()) ==")
    for (name, pixels) in sizes {
        let data = drawIcon(pixels: pixels, variant: variant)
        try data.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
        print("  ✓ \(iconsetDir)/\(name)  (\(Int(pixels))×\(Int(pixels)))")
    }
}

print("\nNext: iconutil compiles both iconsets to .icns:")
print("  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns")
print("  iconutil -c icns Resources/AppIcon-Dark.iconset -o Resources/AppIcon-Dark.icns")
