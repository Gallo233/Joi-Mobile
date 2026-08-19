#!/usr/bin/env swift
//
// Turns the supplied Joi artwork into the App Icon set.
//
// The artwork arrives as a presentation mock-up: the icon sits on a pale page
// with a drop shadow and its corners already rounded. An iOS icon has to be the
// opposite of that — full-bleed, square, no shadow — because the system applies
// its own mask, and a pre-rounded icon gets rounded twice and shows pale corners
// on the home screen.
//
// So this finds the icon inside the mock-up, squares it off, paints the rounded
// corners back to the artwork's own background, and writes the three
// appearances iOS asks for.
//
//   swift Tools/make_app_icon.swift Tools/AppIconSource.png <output-directory>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - Reading

/// The source, as straight sRGB bytes we can look at pixel by pixel.
struct Bitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]  // RGBA, 4 bytes each

    subscript(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        let index = (y * width + x) * 4
        return (
            Double(pixels[index]) / 255,
            Double(pixels[index + 1]) / 255,
            Double(pixels[index + 2]) / 255
        )
    }
}

func load(_ url: URL) throws -> Bitmap {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw Failure("could not read \(url.lastPathComponent)") }

    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw Failure("could not read \(url.lastPathComponent) as sRGB") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return Bitmap(width: width, height: height, pixels: pixels)
}

// MARK: - Finding the icon in the mock-up

/// The artwork's cream is warm — red runs well ahead of blue — while the page it
/// sits on is a neutral grey and the shadow under it is darker still. That one
/// difference separates the icon from its presentation without needing to know
/// where anyone put it.
/// Measured rather than guessed: in the supplied artwork the page reads
/// (0.980, 0.973, 0.965) — red only 0.015 ahead of blue — while the icon reads
/// (0.988, 0.965, 0.925), a gap of 0.063. Anything past 0.045 is the icon.
func isCream(_ pixel: (r: Double, g: Double, b: Double)) -> Bool {
    pixel.r > 0.93 && (pixel.r - pixel.b) > 0.045
}

/// The square the icon occupies, as a rect in the source.
func iconBounds(_ bitmap: Bitmap) throws -> CGRect {
    var minX = bitmap.width, minY = bitmap.height, maxX = -1, maxY = -1
    for y in 0..<bitmap.height {
        for x in 0..<bitmap.width where isCream(bitmap[x, y]) {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX > minX, maxY > minY else { throw Failure("found no icon in the artwork") }

    // The icon is square, and the drop shadow beneath it is warm enough to pass
    // for cream — in the supplied artwork it stretches the run 830 wide by 846
    // tall. Taking the *smaller* side and anchoring at the top-left therefore
    // lands on the icon and not on its shadow. Taking the larger one, which is
    // the obvious reading of "square it off", pushed the crop past the left and
    // right edges and left two pale strips down the sides.
    let width = Double(maxX - minX + 1)
    let height = Double(maxY - minY + 1)
    let side = min(width, height)
    return CGRect(x: Double(minX), y: Double(minY), width: side, height: side)
}

/// The artwork's own background colour, sampled rather than assumed, so the
/// corners we paint back match the icon exactly.
func backgroundColour(_ bitmap: Bitmap, in bounds: CGRect) -> CGColor {
    // Just inside the top edge at the centre, where the artwork is flat cream.
    let x = Int(bounds.minX + bounds.width * 0.5)
    let y = Int(bounds.minY + bounds.height * 0.06)
    let pixel = bitmap[x, y]
    return CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        components: [pixel.r, pixel.g, pixel.b, 1]
    )!
}

// MARK: - Writing

func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { throw Failure("could not open \(url.lastPathComponent)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw Failure("could not write \(url.lastPathComponent)")
    }
}

func context(side: Int) throws -> CGContext {
    guard let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw Failure("could not create a \(side)px context") }
    context.interpolationQuality = .high
    return context
}

let side = 1024
/// Clipped well wide of the artwork's own corner radius, so neither the pale
/// page behind it nor the shadow under it can survive as a fringe. Being
/// generous costs nothing: what gets clipped away is painted back underneath in
/// the artwork's own background colour, and iOS masks every icon at roughly
/// 22% anyway — so any corner treatment beyond that is invisible on a device.
let cornerRadius = CGFloat(side) * 0.30

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(
        "usage: swift Tools/make_app_icon.swift <artwork.png> <output-directory>\n".data(using: .utf8)!
    )
    exit(2)
}
let artwork = URL(fileURLWithPath: arguments[1])
let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

let bitmap = try load(artwork)
let bounds = try iconBounds(bitmap)
let background = backgroundColour(bitmap, in: bounds)

guard let source = CGImageSourceCreateWithURL(artwork as CFURL, nil),
      let full = CGImageSourceCreateImageAtIndex(source, 0, nil),
      // The bitmap was read with y running down; CGImage cropping uses the same
      // orientation, so the rect needs no flip here.
      let cropped = full.cropping(to: bounds)
else { throw Failure("could not crop the artwork") }

// MARK: Light — the artwork as supplied, squared off and full-bleed.

let light = try context(side: side)
light.setFillColor(background)
light.fill(CGRect(x: 0, y: 0, width: side, height: side))
light.saveGState()
light.addPath(CGPath(
    roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
    cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
))
light.clip()
light.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
light.restoreGState()
guard let lightImage = light.makeImage() else { throw Failure("could not render the light icon") }
try write(lightImage, to: directory.appendingPathComponent("AppIcon-1024.png"))

// MARK: Dark and tinted — the mark alone, on nothing.

/// The mark lifted off its background as an alpha mask.
///
/// iOS composites these two appearances onto backdrops of its own, so an icon
/// that brought its own cream would sit in a pale tile on a dark home screen.
/// Taken from luminance rather than by keying on a colour, which keeps every
/// antialiased edge — including the hairline that separates the head from the
/// outline it overlaps.
func markAlpha(_ bitmap: Bitmap, bounds: CGRect, side: Int) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let scale = bounds.width / Double(side)
    // The two ends of the artwork's range: its background, and its ink.
    let backgroundLuminance = 0.95
    let inkLuminance = 0.12

    for y in 0..<side {
        for x in 0..<side {
            let sourceX = Int(bounds.minX + Double(x) * scale)
            let sourceY = Int(bounds.minY + Double(y) * scale)
            guard sourceX >= 0, sourceX < bitmap.width, sourceY >= 0, sourceY < bitmap.height else { continue }
            let pixel = bitmap[sourceX, sourceY]
            let luminance = 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b
            let alpha = min(max((backgroundLuminance - luminance) / (backgroundLuminance - inkLuminance), 0), 1)
            let index = (y * side + x) * 4
            // Premultiplied: a near-white mark at the alpha we just derived.
            let ink = 0.96 * alpha
            pixels[index] = UInt8(ink * 255)
            pixels[index + 1] = UInt8(ink * 255)
            pixels[index + 2] = UInt8(ink * 255)
            pixels[index + 3] = UInt8(alpha * 255)
        }
    }

    guard let context = CGContext(
        data: &pixels, width: side, height: side, bitsPerComponent: 8,
        bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    return context.makeImage()
}

guard let mark = markAlpha(bitmap, bounds: bounds, side: side) else {
    throw Failure("could not lift the mark off its background")
}

for name in ["AppIcon-1024-dark.png", "AppIcon-1024-tinted.png"] {
    let variant = try context(side: side)
    variant.saveGState()
    variant.addPath(CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
        cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
    ))
    variant.clip()
    variant.draw(mark, in: CGRect(x: 0, y: 0, width: side, height: side))
    variant.restoreGState()
    guard let image = variant.makeImage() else { throw Failure("could not render \(name)") }
    try write(image, to: directory.appendingPathComponent(name))
}

print("icon bounds in the artwork: \(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))px square")
print("wrote 3 icons to \(directory.path)")
