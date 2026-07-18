import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let scale: CGFloat = 2
let canvasW = side
let canvasH = side
let cornerRadius: CGFloat = 180

let darkNavy = CGColor(red: 15/255, green: 25/255, blue: 45/255, alpha: 1)
let teal = CGColor(red: 13/255, green: 115/255, blue: 119/255, alpha: 1)
let cyan = CGColor(red: 0/255, green: 180/255, blue: 216/255, alpha: 1)
let white: CGColor = .init(red: 1, green: 1, blue: 1, alpha: 1)

guard let context = CGContext(
    data: nil,
    width: canvasW,
    height: canvasH,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
) else { fputs("error: failed to create CGContext\n", stderr); exit(1) }

context.setShouldAntialias(true)
context.setAllowsAntialiasing(true)
let rect = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)
let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
context.addPath(path)
context.clip()

let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [darkNavy, teal, cyan] as CFArray,
    locations: [0, 0.6, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: canvasW, y: canvasH),
    options: []
)

let cx = CGFloat(canvasW) / 2
let cy = CGFloat(canvasH) / 2

context.setAlpha(0.20)
context.setStrokeColor(white)
context.setLineWidth(6)
let outerRingRadius: CGFloat = 280
context.addArc(center: CGPoint(x: cx, y: cy), radius: outerRingRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.strokePath()

let innerRingRadius: CGFloat = 220
context.setLineWidth(4)
context.setAlpha(0.35)
context.addArc(center: CGPoint(x: cx, y: cy), radius: innerRingRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.strokePath()

let tickCount = 60
for i in 0..<tickCount {
    let angle = (CGFloat(i) / CGFloat(tickCount)) * .pi * 2 - .pi / 2
    let isMajor = i % 5 == 0
    let innerR: CGFloat = isMajor ? outerRingRadius - 40 : outerRingRadius - 20
    let outerR = outerRingRadius
    let x1 = cx + cos(angle) * innerR
    let y1 = cy + sin(angle) * innerR
    let x2 = cx + cos(angle) * outerR
    let y2 = cy + sin(angle) * outerR
    context.setAlpha(isMajor ? 0.5 : 0.25)
    context.setLineWidth(isMajor ? 5 : 2)
    context.move(to: CGPoint(x: x1, y: y1))
    context.addLine(to: CGPoint(x: x2, y: y2))
    context.strokePath()
}

context.setAlpha(0.50)
context.setFillColor(white)
context.addArc(center: CGPoint(x: cx, y: cy), radius: 50, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.fillPath()

context.setAlpha(0.15)
context.setFillColor(white)
context.addArc(center: CGPoint(x: cx, y: cy), radius: 100, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.fillPath()

guard let cgImage = context.makeImage() else {
    fputs("error: failed to create CGImage\n", stderr); exit(1)
}

let outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appending(component: "AppIcon.png")
let uti = UTType.png.identifier as CFString
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, uti, 1, nil) else {
    fputs("error: failed to create image destination\n", stderr); exit(1)
}
CGImageDestinationAddImage(dest, cgImage, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("error: failed to write PNG\n", stderr); exit(1)
}
