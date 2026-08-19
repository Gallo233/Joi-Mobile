#!/usr/bin/env swift
//
// Draws the Joi mark and writes the App Icon set.
//
// Drawn rather than resampled. An app icon is shown from 20pt to 1024pt, and a
// mark this geometric goes soft the moment it is scaled from a raster — the
// gap between the head and the outline above it is the first thing to blur.
// CoreGraphics redraws it at whatever size is asked for, so every size is as
// sharp as the largest.
//
// Full-bleed on purpose: iOS applies its own rounded-rectangle mask. Baking the
// corners in would round an already-rounded shape and leave pale corners.
//
//   swift Tools/make_app_icon.swift <output-directory>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - The mark

/// Everything about the drawing, in fractions of the icon's side. Named so the
/// proportions can be argued with rather than reverse-engineered from numbers.
struct Mark {
    var triangleRadius: CGFloat = 0.402      // corner distance from the triangle's own centre
    // The centre the three corners are placed around — *not* the centre of the
    // resulting shape. An equilateral triangle reaches `radius` above this point
    // and only half that below, so its bounding box sits a quarter of a radius
    // high and this has to compensate. Getting that wrong is what put the apex
    // through the top of the icon on the first attempt.
    var triangleY: CGFloat = -0.122
    var verticalStretch: CGFloat = 1.06      // the mark is a little wider than it is tall
    var cornerRadius: CGFloat = 0.170
    var bulge: CGFloat = 0.012               // how far each side bows outward
    var stroke: CGFloat = 0.0267
    var headY: CGFloat = 0.172               // above the icon's centre
    var headRadius: CGFloat = 0.108
    var bodyY: CGFloat = -0.112              // below it
    var bodyRadius: CGFloat = 0.162
    /// The hairline of background colour that keeps the head from merging into
    /// the outline it overlaps. Without it the apex reads as a blob.
    var headGap: CGFloat = 0.009
    /// The whole mark, about the icon's centre. iOS crops a little off every
    /// icon with its mask, and a mark drawn to the measured edges loses its
    /// margin on the home screen rather than on paper.
    var scale: CGFloat = 0.955
}

/// The rounded, outward-bowing triangle — an onigiri rather than a triangle
/// with filleted corners. The bow is what makes it read as one shape instead of
/// three lines meeting.
///
/// Built as one closed path and stroked once. Taking the outline of a stroked
/// skeleton, which is the obvious shortcut, produces two contours — an inside
/// and an outside — and stroking *that* draws the shape twice with spurs where
/// the contours meet.
func trianglePath(_ mark: Mark, side: CGFloat) -> CGPath {
    let centre = CGPoint(x: side / 2, y: side / 2 + mark.triangleY * side)
    let radius = mark.triangleRadius * side
    let corner = mark.cornerRadius * side
    let bulge = mark.bulge * side

    // Apex up, in CoreGraphics' own y-up space.
    let angles: [CGFloat] = [.pi / 2, .pi / 2 + 2 * .pi / 3, .pi / 2 + 4 * .pi / 3]
    // Inboard, so each arc's outermost point still lands on `radius`.
    let arcCentres = angles.map {
        CGPoint(x: centre.x + (radius - corner) * cos($0), y: centre.y + (radius - corner) * sin($0))
    }

    func point(_ index: Int, _ angle: CGFloat) -> CGPoint {
        CGPoint(x: arcCentres[index].x + corner * cos(angle), y: arcCentres[index].y + corner * sin(angle))
    }

    let path = CGMutablePath()
    path.move(to: point(0, angles[0] - .pi / 3))
    for index in 0..<3 {
        path.addArc(
            center: arcCentres[index],
            radius: corner,
            startAngle: angles[index] - .pi / 3,
            endAngle: angles[index] + .pi / 3,
            clockwise: false
        )
        let next = (index + 1) % 3
        let from = point(index, angles[index] + .pi / 3)
        let to = point(next, angles[next] - .pi / 3)
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let away = CGVector(dx: mid.x - centre.x, dy: mid.y - centre.y)
        let length = max(sqrt(away.dx * away.dx + away.dy * away.dy), 0.0001)
        path.addQuadCurve(
            to: to,
            control: CGPoint(x: mid.x + away.dx / length * bulge, y: mid.y + away.dy / length * bulge)
        )
    }
    path.closeSubpath()

    // Stretched about the triangle's own centre: the mark is a little wider than
    // it is tall, which an equilateral construction cannot be on its own.
    var stretch = CGAffineTransform(translationX: centre.x, y: centre.y)
        .scaledBy(x: 1, y: mark.verticalStretch)
        .translatedBy(x: -centre.x, y: -centre.y)
    return path.copy(using: &stretch) ?? path
}

func draw(_ mark: Mark, side: CGFloat, background: CGColor?, ink: CGColor, context: CGContext) {
    if let background {
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }

    let centreX = side / 2
    let stroke = mark.stroke * side

    context.saveGState()
    context.translateBy(x: side / 2, y: side / 2)
    context.scaleBy(x: mark.scale, y: mark.scale)
    context.translateBy(x: -side / 2, y: -side / 2)
    defer { context.restoreGState() }

    context.setLineWidth(stroke)
    context.setStrokeColor(ink)
    context.setLineJoin(.round)
    context.setLineCap(.round)

    context.addPath(trianglePath(mark, side: side))
    context.strokePath()

    func circle(y: CGFloat, radius: CGFloat, grow: CGFloat = 0) -> CGRect {
        let r = radius * side + grow
        return CGRect(x: centreX - r, y: side / 2 + y * side - r, width: r * 2, height: r * 2)
    }

    // The body is stroked first and the head laid over it, so the head reads as
    // being in front — the one place the mark has depth.
    context.strokeEllipse(in: circle(y: mark.bodyY, radius: mark.bodyRadius))

    // The head overlaps the outline at the apex. A hairline of the background
    // keeps the two shapes legible as two; on a variant with no background of
    // its own there is nothing to cut with, so the head simply merges — which is
    // what iOS's own tinted rendering does to every mark anyway.
    if let background {
        context.setStrokeColor(background)
        context.setLineWidth(mark.headGap * side)
        context.strokeEllipse(in: circle(y: mark.headY, radius: mark.headRadius, grow: mark.headGap * side / 2))
    }

    context.setFillColor(ink)
    context.fillEllipse(in: circle(y: mark.headY, radius: mark.headRadius))
}

// MARK: - Writing

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func render(side: Int, background: CGColor?, ink: CGColor, to url: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw Failure("could not create a \(side)px context") }

    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    draw(Mark(), side: CGFloat(side), background: background, ink: ink, context: context)

    guard let image = context.makeImage() else { throw Failure("could not make the image") }
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { throw Failure("could not open \(url.lastPathComponent)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure("could not write \(url.lastPathComponent)") }
}

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
}

// The cream the mark sits on, and the near-black it is drawn in.
let cream = srgb(0.988, 0.961, 0.918)
let ink = srgb(0.086, 0.086, 0.086)
// Dark and tinted variants are composited by iOS onto its own backdrop, so they
// carry no background of their own.
let lightInk = srgb(0.965, 0.945, 0.914)

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift Tools/make_app_icon.swift <output-directory>\n".data(using: .utf8)!)
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

try render(side: 1024, background: cream, ink: ink, to: directory.appendingPathComponent("AppIcon-1024.png"))
try render(side: 1024, background: nil, ink: lightInk, to: directory.appendingPathComponent("AppIcon-1024-dark.png"))
try render(side: 1024, background: nil, ink: lightInk, to: directory.appendingPathComponent("AppIcon-1024-tinted.png"))
print("wrote 3 icons to \(directory.path)")
