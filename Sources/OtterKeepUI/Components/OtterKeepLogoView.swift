import SwiftUI
import AppKit

/// Mascot logo presentation view for OtterKeep featuring modern macOS squircle styling.
public struct OtterKeepLogoView: View {
    public let size: CGFloat
    public let withGlow: Bool
    public let withBorder: Bool

    public init(size: CGFloat = 44, withGlow: Bool = true, withBorder: Bool = true) {
        self.size = size
        self.withGlow = withGlow
        self.withBorder = withBorder
    }

    public var body: some View {
        ZStack {
            if withGlow {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(OtterTheme.oceanicTeal.opacity(0.25))
                    .blur(radius: size * 0.15)
                    .frame(width: size * 1.05, height: size * 1.05)
            }

            if let nsImage = resolvedLogoImage() {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        OtterTheme.oceanicTeal.opacity(withBorder ? 0.6 : 0),
                                        OtterTheme.otterAmber.opacity(withBorder ? 0.4 : 0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: withBorder ? max(1, size * 0.03) : 0
                            )
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: size * 0.08, x: 0, y: size * 0.04)
            } else {
                fallbackMascotView
            }
        }
        .frame(width: size, height: size)
    }

    private var fallbackMascotView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [OtterTheme.otterAmber, OtterTheme.deepSeaNavy],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: size * 0.02) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .foregroundStyle(OtterTheme.oceanicTeal)
            }
        }
        .frame(width: size, height: size)
    }

    private func resolvedLogoImage() -> NSImage? {
        Self.resolveLogoImage()
    }

    /// Resolves the raw OtterKeep mascot logo image from bundle resources or local fallback paths.
    public static func resolveLogoImage() -> NSImage? {
        // 1. Search within Swift Package module resources
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "OtterKeepLogo", withExtension: "jpg"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        #endif

        // 2. Search in main application bundle resources
        if let url = Bundle.main.url(forResource: "OtterKeepLogo", withExtension: "jpg"),
           let img = NSImage(contentsOf: url) {
            return img
        }

        // 3. Search in nested SPM bundle within Contents/Resources
        if let resourceURL = Bundle.main.resourceURL {
            let bundleURL = resourceURL.appendingPathComponent("OtterKeep_OtterKeepUI.bundle")
            if let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: "OtterKeepLogo", withExtension: "jpg"),
               let img = NSImage(contentsOf: url) {
                return img
            }
        }

        // 4. Development filesystem fallback
        let devRelativePath = "Sources/OtterKeepUI/Resources/OtterKeepLogo.jpg"
        if FileManager.default.fileExists(atPath: devRelativePath),
           let img = NSImage(contentsOfFile: devRelativePath) {
            return img
        }

        return nil
    }

    /// Creates a 512x512 rounded macOS squircle dock icon using the OtterKeep mascot logo.
    @MainActor
    public static func createApplicationDockIcon() -> NSImage? {
        guard let baseImage = resolveLogoImage() else { return nil }
        let iconSize = NSSize(width: 512, height: 512)
        let outputImage = NSImage(size: iconSize)
        outputImage.lockFocus()

        let rect = NSRect(origin: .zero, size: iconSize)
        let cornerRadius = iconSize.width * 0.2237 // macOS standard app icon continuous corner radius ratio
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()
        baseImage.draw(in: rect, from: NSRect(origin: .zero, size: baseImage.size), operation: .sourceOver, fraction: 1.0)

        outputImage.unlockFocus()
        return outputImage
    }
}
