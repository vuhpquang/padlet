#!/usr/bin/env swift
// scripts/make-icon.swift
// Draws the Padlet app icon (1024×1024 PNG) with AppKit — no design tools needed.
//
//   swift scripts/make-icon.swift <out.png>
//
// Motif: a glass trackpad on an indigo squircle, a pointing hand on it, and the two
// edge strips the app turns into controls (warm = brightness, cool = volume).
// build.sh turns the PNG into AppIcon.icns.

import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let gctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no context") }
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// ── Body: macOS icon grid (824pt squircle centred in 1024, soft shadow) ──
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: NSColor(white: 0, alpha: 0.35).cgColor)
rgb(0x2A2780).setFill()
bodyPath.fill()
ctx.restoreGState()

ctx.saveGState()
bodyPath.addClip()
NSGradient(colors: [rgb(0x6C6BFF), rgb(0x3B37C9), rgb(0x1C1A5E)],
           atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
    .draw(in: body, angle: -90)
// Top sheen
NSGradient(starting: NSColor(white: 1, alpha: 0.22), ending: NSColor(white: 1, alpha: 0))!
    .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
ctx.restoreGState()

// ── Trackpad (glass) ──
let pad = NSRect(x: 214, y: 268, width: 596, height: 452)
let padPath = NSBezierPath(roundedRect: pad, xRadius: 56, yRadius: 56)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor(white: 0, alpha: 0.30).cgColor)
NSColor(white: 1, alpha: 0.16).setFill()
padPath.fill()
ctx.restoreGState()
NSColor(white: 1, alpha: 0.45).setStroke()
padPath.lineWidth = 6
padPath.stroke()

// ── Edge strips: left = brightness (warm), right = volume (cool) ──
func strip(x: CGFloat, colors: [NSColor]) {
    let r = NSRect(x: x, y: pad.minY + 70, width: 30, height: pad.height - 140)
    let p = NSBezierPath(roundedRect: r, xRadius: 15, yRadius: 15)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 26, color: colors[0].withAlphaComponent(0.9).cgColor)
    p.addClip()
    NSGradient(colors: colors)!.draw(in: r, angle: 90)
    ctx.restoreGState()
}
strip(x: pad.minX + 34, colors: [rgb(0xFF9F0A), rgb(0xFFD60A)])
strip(x: pad.maxX - 64, colors: [rgb(0x30D5FF), rgb(0x64F0C8)])

// ── Pointing hand ──
let config = NSImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let hand = NSImage(systemSymbolName: "hand.point.up.left.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = hand.size
    let rect = NSRect(x: pad.midX - s.width / 2 + 10, y: pad.midY - s.height / 2 - 6,
                      width: s.width, height: s.height)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: NSColor(white: 0, alpha: 0.35).cgColor)
    hand.draw(in: rect)
    ctx.restoreGState()
}

NSGraphicsContext.current = nil
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode") }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
