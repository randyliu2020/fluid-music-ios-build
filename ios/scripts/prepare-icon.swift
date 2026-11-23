import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Preserve the Android app's artwork, with an opaque iOS icon canvas.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let source = root.appendingPathComponent("ios/Branding/app_icon_fg.png")
let destination = root.appendingPathComponent("ios/FluidMusic/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { fatalError("Cannot read icon at \(source.path)") }
// Core Graphics supports 32-bit RGBX without alpha; a 24-bit AppKit context
// is not available on every headless runner.
guard let context = CGContext(data: nil, width: 1024, height: 1024,
    bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Cannot create RGBX icon context") }
let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
context.setFillColor(CGColor(red: 0.04, green: 0.07, blue: 0.12, alpha: 1))
context.fill(canvas)
context.interpolationQuality = .high
context.draw(sourceImage, in: canvas)
let iconURL = destination.appendingPathComponent("AppIcon.png")
guard let rendered = context.makeImage(),
      let output = CGImageDestinationCreateWithURL(iconURL as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot encode app icon") }
CGImageDestinationAddImage(output, rendered, nil)
guard CGImageDestinationFinalize(output) else { fatalError("Cannot save app icon") }
let contents = """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try contents.write(to: destination.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
