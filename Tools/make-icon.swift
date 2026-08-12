#!/usr/bin/env swift
//
// Renders Tools/AppIcon.icns — a dark rounded square with the Deltarune soul heart on it.
//
//     swift Tools/make-icon.swift
//
// Run only when the icon should change; the .icns is committed.

import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/Tools")

let background = NSColor(calibratedRed: 0.12, green: 0.11, blue: 0.16, alpha: 1)
let heartTop = NSColor(calibratedRed: 1.00, green: 0.32, blue: 0.45, alpha: 1)
let heartBottom = NSColor(calibratedRed: 0.86, green: 0.10, blue: 0.30, alpha: 1)

/// One square icon at the given pixel size.
func renderIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let side = CGFloat(size)
    let inset = side * 0.055
    let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)

    // macOS app icons are rounded squares; roughly 22% of the side.
    let plate = NSBezierPath(roundedRect: rect, xRadius: side * 0.22, yRadius: side * 0.22)
    background.setFill()
    plate.fill()

    // A subtle lighter top edge so the icon doesn't read as a flat black square.
    NSColor(calibratedWhite: 1, alpha: 0.07).setStroke()
    plate.lineWidth = max(1, side * 0.01)
    plate.stroke()

    drawHeart(in: rect, size: side)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// The soul heart, built from two arcs and a point.
func drawHeart(in rect: NSRect, size: CGFloat) {
    let width = rect.width * 0.56
    let height = width * 0.92
    let centreX = rect.midX
    let bottomY = rect.midY - height * 0.44

    let path = NSBezierPath()
    path.move(to: NSPoint(x: centreX, y: bottomY))

    // Left lobe.
    path.curve(
        to: NSPoint(x: centreX - width / 2, y: bottomY + height * 0.72),
        controlPoint1: NSPoint(x: centreX - width * 0.28, y: bottomY + height * 0.22),
        controlPoint2: NSPoint(x: centreX - width / 2, y: bottomY + height * 0.42)
    )
    path.curve(
        to: NSPoint(x: centreX, y: bottomY + height * 0.94),
        controlPoint1: NSPoint(x: centreX - width / 2, y: bottomY + height * 1.06),
        controlPoint2: NSPoint(x: centreX - width * 0.18, y: bottomY + height * 1.06)
    )
    // Right lobe, mirrored.
    path.curve(
        to: NSPoint(x: centreX + width / 2, y: bottomY + height * 0.72),
        controlPoint1: NSPoint(x: centreX + width * 0.18, y: bottomY + height * 1.06),
        controlPoint2: NSPoint(x: centreX + width / 2, y: bottomY + height * 1.06)
    )
    path.curve(
        to: NSPoint(x: centreX, y: bottomY),
        controlPoint1: NSPoint(x: centreX + width / 2, y: bottomY + height * 0.42),
        controlPoint2: NSPoint(x: centreX + width * 0.28, y: bottomY + height * 0.22)
    )
    path.close()

    NSGradient(starting: heartTop, ending: heartBottom)?.draw(in: path, angle: -90)
}

// MARK: - Write the iconset

let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// (base point size, scale) pairs iconutil expects.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]

for (base, scale) in variants {
    let pixels = base * scale
    let rep = renderIcon(size: pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(pixels)px icon")
    }
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try data.write(to: iconset.appendingPathComponent(name))
}

let icns = outputDirectory.appendingPathComponent("AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }

try? FileManager.default.removeItem(at: iconset)
print("Wrote \(icns.path)")
