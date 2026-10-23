import AppKit

/// The menu bar glyph: the app icon's one-line headphone mark as a template image, so the
/// menu bar tints it like an SF Symbol. The paths match Resources/AppIcon.icon/Assets, in
/// those files' 1024-point coordinates.
@MainActor
enum MenuBarIcon {
  /// Solid signal dot: the control channel is open.
  static let filled = makeImage(filled: true)
  /// Hollow signal dot: Bluetooth is up but the control channel is not.
  static let outlined = makeImage(filled: false)

  private static let canvas: CGFloat = 18
  // The band is thinner than in the app icon so the mark stays light at menu bar size.
  private static let bandWidth: CGFloat = 2.2
  // The band's centerline spans x 300...724 and y 264...764 in icon coordinates.
  private static let scale: CGFloat = (16 - bandWidth) / 500
  private static let origin = CGPoint(
    x: canvas / 2 - 512 * scale, y: 1 + bandWidth / 2 - 264 * scale)

  private static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
  }

  private static func makeImage(filled: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: true) { _ in
      NSColor.black.set()
      let band = NSBezierPath()
      band.move(to: point(300, 764))
      band.line(to: point(300, 564))
      band.curve(
        to: point(512, 264), controlPoint1: point(300, 380), controlPoint2: point(392, 264))
      band.curve(
        to: point(724, 564), controlPoint1: point(632, 264), controlPoint2: point(724, 380))
      band.line(to: point(724, 764))
      band.lineWidth = bandWidth
      band.lineCapStyle = .round
      band.stroke()

      // The dot is larger than in the app icon so it survives at menu bar size.
      let center = point(512, 464)
      let radius: CGFloat = 2
      let dot = NSBezierPath(
        ovalIn: CGRect(
          x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
      if filled {
        dot.fill()
      } else {
        dot.lineWidth = 1.2
        dot.stroke()
      }
      return true
    }
    image.isTemplate = true
    return image
  }
}
