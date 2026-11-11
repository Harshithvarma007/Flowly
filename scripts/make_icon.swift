import AppKit
let size = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let r = NSRect(x: 80, y: 80, width: 864, height: 864)
let path = NSBezierPath(roundedRect: r, xRadius: 195, yRadius: 195)
NSGradient(colors: [NSColor(red: 0.36, green: 0.30, blue: 0.95, alpha: 1), NSColor(red: 0.93, green: 0.30, blue: 0.62, alpha: 1)])!.draw(in: path, angle: -50)
NSColor.white.setFill()
let heights: [CGFloat] = [160, 330, 520, 330, 160]
for (i, h) in heights.enumerated() {
    let x = 512 - 2 * 110 + CGFloat(i) * 110 - 30
    NSBezierPath(roundedRect: NSRect(x: x, y: 512 - h / 2, width: 60, height: h), xRadius: 30, yRadius: 30).fill()
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
