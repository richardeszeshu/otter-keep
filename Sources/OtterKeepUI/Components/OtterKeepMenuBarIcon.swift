import SwiftUI
import AppKit

/// Generates and provides stylized otter icons for the macOS Menu Bar and native UI elements.
public enum OtterKeepMenuBarIcon {
    /// Generates a crisp vector NSImage template icon of the stylized otter mascot.
    /// - Parameters:
    ///   - size: Target dimension (default 18x18 pt, standard macOS status bar icon size).
    ///   - isRunning: Whether an active backup operation is in progress (adds an activity indicator ring/badge).
    /// - Returns: A template `NSImage` adapting automatically to macOS Dark and Light Menu Bars.
    public static func createMenuBarImage(size: CGFloat = 18, isRunning: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            
            let scale = bounds.width / 24.0
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            
            // Stylized Otter Floating Vector Path (24x24 coordinate system)
            // An adorable otter floating on its back, hugging a pebble
            
            // 1. Otter Head & Ears Path
            let headPath = NSBezierPath()
            headPath.appendOval(in: NSRect(x: 6.5, y: 9.0, width: 11.0, height: 11.0))
            
            // Left Ear
            let leftEar = NSBezierPath(ovalIn: NSRect(x: 5.5, y: 16.5, width: 3.5, height: 3.5))
            // Right Ear
            let rightEar = NSBezierPath(ovalIn: NSRect(x: 15.0, y: 16.5, width: 3.5, height: 3.5))
            
            // 2. Otter Body / Torso floating on water
            let bodyPath = NSBezierPath()
            bodyPath.move(to: NSPoint(x: 7.5, y: 10.0))
            bodyPath.curve(to: NSPoint(x: 8.5, y: 3.0), controlPoint1: NSPoint(x: 6.0, y: 6.5), controlPoint2: NSPoint(x: 7.0, y: 4.0))
            bodyPath.curve(to: NSPoint(x: 12.0, y: 2.2), controlPoint1: NSPoint(x: 9.5, y: 2.2), controlPoint2: NSPoint(x: 10.5, y: 2.2))
            bodyPath.curve(to: NSPoint(x: 15.5, y: 3.0), controlPoint1: NSPoint(x: 13.5, y: 2.2), controlPoint2: NSPoint(x: 14.5, y: 2.2))
            bodyPath.curve(to: NSPoint(x: 16.5, y: 10.0), controlPoint1: NSPoint(x: 17.0, y: 4.0), controlPoint2: NSPoint(x: 18.0, y: 6.5))
            bodyPath.close()

            // 3. Feet / Flippers sticking out slightly at the bottom
            let leftFoot = NSBezierPath(ovalIn: NSRect(x: 6.0, y: 2.0, width: 3.0, height: 3.5))
            let rightFoot = NSBezierPath(ovalIn: NSRect(x: 15.0, y: 2.0, width: 3.0, height: 3.5))

            NSColor.black.setFill()
            leftEar.fill()
            rightEar.fill()
            bodyPath.fill()
            leftFoot.fill()
            rightFoot.fill()
            headPath.fill()
            
            // Negative space cutouts: Eyes and Snout
            context.setBlendMode(.clear)
            
            // Left Eye & Right Eye
            let leftEye = NSBezierPath(ovalIn: NSRect(x: 9.0, y: 14.5, width: 1.4, height: 1.6))
            let rightEye = NSBezierPath(ovalIn: NSRect(x: 13.6, y: 14.5, width: 1.4, height: 1.6))
            leftEye.fill()
            rightEye.fill()
            
            // Nose (tiny button)
            let nose = NSBezierPath(ovalIn: NSRect(x: 11.2, y: 12.5, width: 1.6, height: 1.2))
            nose.fill()

            // Pebble cut / highlight in chest (an iconic gemstone/pebble negative space in paws)
            let pebblePath = NSBezierPath()
            pebblePath.move(to: NSPoint(x: 12.0, y: 8.5))
            pebblePath.line(to: NSPoint(x: 13.8, y: 6.5))
            pebblePath.line(to: NSPoint(x: 12.0, y: 4.5))
            pebblePath.line(to: NSPoint(x: 10.2, y: 6.5))
            pebblePath.close()
            pebblePath.fill()
            
            context.setBlendMode(.normal)
            
            if isRunning {
                // Outer sync / activity indicator dot in top right
                let badgeRect = NSRect(x: 19.5, y: 1.5, width: 4.5, height: 4.5)
                let badgePath = NSBezierPath(ovalIn: badgeRect)
                NSColor.black.setFill()
                badgePath.fill()
            }
            
            context.restoreGState()
            return true
        }
        
        image.isTemplate = true
        return image
    }
}

/// SwiftUI View rendering the stylized OtterKeep icon for menus and toolbars.
public struct OtterKeepMenuBarIconView: View {
    public let isRunning: Bool

    public init(isRunning: Bool = false) {
        self.isRunning = isRunning
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: OtterKeepMenuBarIcon.createMenuBarImage(size: 18, isRunning: isRunning))
            if isRunning {
                Circle()
                    .fill(OtterTheme.otterAmber)
                    .frame(width: 5, height: 5)
            }
        }
    }
}
