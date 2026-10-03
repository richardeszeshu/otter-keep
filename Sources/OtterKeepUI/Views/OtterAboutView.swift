//
//  OtterAboutView.swift
//  OtterKeepUI
//
//  Created for OtterKeep 1.0.0 (Build 1000).
//  Copyright © 2026 OtterKeep. All rights reserved.
//

import SwiftUI
import AppKit
import OtterKeepCore

/// Brand-new modern macOS Sequoia About (Névjegy) view celebrating the OtterKeep lore, architecture, and craftsmanship.
public struct OtterAboutView: View {
    @Environment(\.dismiss) private var dismiss
    private let onClose: (() -> Void)?

    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    private func closeAction() {
        if let onClose = onClose {
            onClose()
        } else {
            dismiss()
            AboutWindowController.shared.close()
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerView
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: OtterTheme.spacing16) {
                    // 1. Mascot Logo with Glowing Dual Ring
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(OtterTheme.oceanicTeal.opacity(0.18))
                                .frame(width: 110, height: 110)
                                .blur(radius: 12)

                            Circle()
                                .fill(OtterTheme.otterAmber.opacity(0.14))
                                .frame(width: 100, height: 100)
                                .blur(radius: 8)

                            OtterKeepLogoView(size: 88, withGlow: true, withBorder: true)
                        }

                        VStack(spacing: 4) {
                            Text("OtterKeep")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            HStack(spacing: 6) {
                                Text("v\(CoreEngine.version) (Build 1000)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2.5)
                                    .background(OtterTheme.oceanicTeal.opacity(0.15), in: Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(OtterTheme.oceanicTeal.opacity(0.35), lineWidth: 1)
                                    )
                                    .foregroundStyle(OtterTheme.oceanicTeal)
                            }
                        }
                    }

                    // 2. Slogans
                    VStack(spacing: 3) {
                        Text("„Keep what you love close to your chest.”")
                            .font(.system(size: 13, weight: .semibold, design: .serif).italic())
                            .foregroundStyle(OtterTheme.otterAmber)

                        Text("„Őrizd a legfontosabb kincseidet biztos kezekben.”")
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    // 3. Brand Lore Quote Card
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(OtterTheme.otterAmber)
                            .frame(width: 3)

                        Text(L10n.t(.aboutLoreStory))
                            .font(.system(size: 11, weight: .regular))
                            .lineSpacing(3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(OtterTheme.subtleBorder, lineWidth: 0.5)
                    )

                    // 4. Architecture & Feature Badges (2x2 Grid)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        architectureBadge(
                            icon: "bolt.shield.fill",
                            color: OtterTheme.oceanicTeal,
                            title: "APFS CoW Engine",
                            subtitle: "Zero-latency instant clones"
                        )
                        architectureBadge(
                            icon: "swift",
                            color: .orange,
                            title: "Swift 6 Concurrency",
                            subtitle: "Actor-isolated data safety"
                        )
                        architectureBadge(
                            icon: "internaldrive.fill",
                            color: OtterTheme.otterAmber,
                            title: "Local-First",
                            subtitle: "100% on-device private vaults"
                        )
                        architectureBadge(
                            icon: "hand.raised.slash.fill",
                            color: OtterTheme.statusGreen,
                            title: "Zero Telemetry",
                            subtitle: "No trackers, no telemetry"
                        )
                    }

                    // 5. Interactive Resource Links
                    HStack(spacing: 10) {
                        LinkButton(title: "Website", icon: "globe", url: "https://otterkeep.app")
                        LinkButton(title: "Website", icon: "globe", url: "https://otterkeep.app")
                        LinkButton(title: "GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/richardeszes/otter-keep")
                        LinkButton(title: "Releases", icon: "tag.fill", url: "https://github.com/richardeszes/otter-keep/releases")
                        LinkButton(title: "MIT License", icon: "doc.text.fill", url: "https://github.com/richardeszes/otter-keep/blob/main/LICENSE")
                    }
                    .padding(.top, 4)

                    // 6. Credits & Copyright Footnote
                    VStack(spacing: 2) {
                        Text("Crafted with care by Richárd Eszes & Open Source Contributors")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)

                        Text("© 2026 OtterKeep. All rights reserved.")
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(width: 480, height: 580)
        .background(
            RoundedRectangle(cornerRadius: OtterTheme.heroCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OtterTheme.heroCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: OtterTheme.specularHighlight, location: 0.0),
                            .init(color: OtterTheme.subtleBorder, location: 0.2),
                            .init(color: OtterTheme.subtleBorder, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.0
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: OtterTheme.heroCornerRadius, style: .continuous))
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundStyle(OtterTheme.oceanicTeal)
                .frame(width: 32, height: 32)
                .background(OtterTheme.oceanicTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t(.aboutWindowTitle))
                    .font(.headline.bold())
                Text("v\(CoreEngine.version) (Build 1000)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                closeAction()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(L10n.t(.cancel))
        }
    }

    private func architectureBadge(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(OtterTheme.subtleBorder, lineWidth: 0.5)
        )
    }
}

private struct LinkButton: View {
    let title: String
    let icon: String
    let url: String

    var body: some View {
        Button {
            if let linkURL = URL(string: url) {
                NSWorkspace.shared.open(linkURL)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Dedicated macOS NSWindowController presenting the About window as a clean floating modal panel without OS traffic lights.
@MainActor
public final class AboutWindowController: NSObject {
    public static let shared = AboutWindowController()
    private var window: NSWindow?

    public func show() {
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = OtterAboutView(onClose: { [weak self] in
            self?.close()
        })
        let hostingController = NSHostingController(rootView: aboutView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "About OtterKeep"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating

        // Hide standard OS window controls (traffic lights) so only the in-app close button is shown
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentViewController = hostingController
        panel.center()
        panel.isReleasedWhenClosed = false

        self.window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}
