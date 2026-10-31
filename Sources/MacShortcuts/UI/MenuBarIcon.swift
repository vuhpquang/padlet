// UI/MenuBarIcon.swift
// The menu bar glyph: a small trackpad with its two edge strips and a fingertip — the
// same motif as the app icon. Drawn as a template image so macOS tints it for light,
// dark and highlighted menu bars. When everything is off, a slash is cut through it.

import AppKit

enum MenuBarIcon {

    static func image(enabled: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Trackpad outline
            let pad = NSRect(x: 1.5, y: 2, width: 17, height: 12)
            let outline = NSBezierPath(roundedRect: pad, xRadius: 3, yRadius: 3)
            outline.lineWidth = 1.5
            outline.stroke()

            // Edge strips (brightness / volume)
            for x in [pad.minX + 2.6, pad.maxX - 4.2] {
                NSBezierPath(roundedRect: NSRect(x: x, y: pad.minY + 2.7, width: 1.6, height: pad.height - 5.4),
                             xRadius: 0.8, yRadius: 0.8).fill()
            }

            // Fingertip
            NSBezierPath(ovalIn: NSRect(x: pad.midX - 2, y: pad.midY - 2, width: 4, height: 4)).fill()

            if !enabled {
                // Cut a clear gap, then draw the slash inside it.
                let from = NSPoint(x: 2.5, y: 15), to = NSPoint(x: 17.5, y: 1)
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                let gap = NSBezierPath()
                gap.move(to: from); gap.line(to: to)
                gap.lineWidth = 4
                gap.lineCapStyle = .round
                gap.stroke()
                ctx.restoreGState()

                let slash = NSBezierPath()
                slash.move(to: from); slash.line(to: to)
                slash.lineWidth = 1.5
                slash.lineCapStyle = .round
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = enabled ? "Mac Shortcuts" : "Mac Shortcuts (off)"
        return image
    }
}
