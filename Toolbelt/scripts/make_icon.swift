// Renders Toolbelt's app icon (1024×1024 PNG) with CoreGraphics. Usage: swift scripts/make_icon.swift out.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let s: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func rounded(_ r: CGRect, _ c: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: c, cornerHeight: c, transform: nil) }

// Background: rounded square, warm leather gradient.
let bg = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: rgb(0, 0, 0, 0.35))
ctx.addPath(rounded(bg, 185)); ctx.setFillColor(rgb(0.45, 0.27, 0.15)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(rounded(bg, 185)); ctx.clip()
let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                   colors: [rgb(0.20, 0.24, 0.32), rgb(0.10, 0.12, 0.17)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: bg.maxY), end: CGPoint(x: 0, y: bg.minY), options: [])
ctx.restoreGState()

// Tools standing in the belt: screwdriver, wrench, pencil-like tool.
func tool(_ x: CGFloat, width w: CGFloat, top: CGFloat, color: CGColor, tip: CGColor) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(rounded(CGRect(x: x - w / 2, y: 470, width: w, height: top - 470), w / 2))
    ctx.setFillColor(color); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(rounded(CGRect(x: x - w * 0.28, y: top - 20, width: w * 0.56, height: 70), w * 0.2))
    ctx.setFillColor(tip); ctx.fillPath()
}
tool(360, width: 78, top: 760, color: rgb(1.0, 0.36, 0.30), tip: rgb(0.85, 0.87, 0.90))
tool(512, width: 92, top: 810, color: rgb(1.0, 0.78, 0.25), tip: rgb(0.85, 0.87, 0.90))
tool(664, width: 78, top: 740, color: rgb(0.30, 0.62, 1.0), tip: rgb(0.85, 0.87, 0.90))

// The belt: a band with pouch stitching and a buckle.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0, 0, 0, 0.45))
ctx.addPath(rounded(CGRect(x: 170, y: 300, width: 684, height: 220), 46))
ctx.setFillColor(rgb(0.62, 0.38, 0.20)); ctx.fillPath()
ctx.restoreGState()
ctx.setStrokeColor(rgb(1, 0.88, 0.70, 0.75)); ctx.setLineWidth(6); ctx.setLineDash(phase: 0, lengths: [20, 14])
ctx.addPath(rounded(CGRect(x: 196, y: 326, width: 632, height: 168), 30)); ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
let buckle = CGRect(x: 432, y: 342, width: 160, height: 136)
ctx.addPath(rounded(buckle, 22)); ctx.setFillColor(rgb(0.93, 0.80, 0.42)); ctx.fillPath()
ctx.addPath(rounded(buckle.insetBy(dx: 28, dy: 28), 10)); ctx.setFillColor(rgb(0.62, 0.38, 0.20)); ctx.fillPath()

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
