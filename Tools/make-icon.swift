// Renders the app icon. Run: swift Tools/make-icon.swift
// An anchor — the plan's own image for hope (Heb 6:19) — in the design
// system's accent violet on paper cream.
import AppKit

let s = 1024.0
let image = NSImage(size: NSSize(width: s, height: s))
image.lockFocus()

let violet = NSColor(srgbRed: 0x5B/255, green: 0x3D/255, blue: 0xF5/255, alpha: 1)
let cream  = NSColor(srgbRed: 0xF4/255, green: 0xF1/255, blue: 0xEC/255, alpha: 1)

violet.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s)).fill()
cream.setStroke()

let line = s * 0.058
let cx = s / 2

// Eye
let eyeR = s * 0.072
let eye = NSBezierPath(ovalIn: NSRect(x: cx - eyeR, y: s * 0.845 - eyeR,
                                      width: eyeR * 2, height: eyeR * 2))
eye.lineWidth = line
eye.stroke()

// Shank
let shank = NSBezierPath()
shank.move(to: NSPoint(x: cx, y: s * 0.775))
shank.line(to: NSPoint(x: cx, y: s * 0.235))
shank.lineWidth = line
shank.lineCapStyle = .round
shank.stroke()

// Stock
let stock = NSBezierPath()
stock.move(to: NSPoint(x: s * 0.30, y: s * 0.695))
stock.line(to: NSPoint(x: s * 0.70, y: s * 0.695))
stock.lineWidth = line
stock.lineCapStyle = .round
stock.stroke()

// Flukes — a U with upturned tips
let flukes = NSBezierPath()
flukes.move(to: NSPoint(x: s * 0.225, y: s * 0.415))
flukes.curve(to: NSPoint(x: cx, y: s * 0.175),
             controlPoint1: NSPoint(x: s * 0.225, y: s * 0.235),
             controlPoint2: NSPoint(x: s * 0.355, y: s * 0.175))
flukes.curve(to: NSPoint(x: s * 0.775, y: s * 0.415),
             controlPoint1: NSPoint(x: s * 0.645, y: s * 0.175),
             controlPoint2: NSPoint(x: s * 0.775, y: s * 0.235))
flukes.lineWidth = line
flukes.lineCapStyle = .round
flukes.lineJoinStyle = .round
flukes.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("render failed")
}
try! png.write(to: URL(fileURLWithPath: "Dwell/Assets.xcassets/AppIcon.appiconset/icon-1024.png"))
print("wrote icon")
