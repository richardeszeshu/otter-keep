import Foundation
import AppKit
@preconcurrency import QuickLookUI
import SwiftUI

/// Coordinator managing macOS Quick Look preview panel (`QLPreviewPanel`) presentation and data source delegates.
public final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = QuickLookCoordinator()

    /// Current preview item file URL.
    public private(set) var currentURL: URL?

    /// Active AppKit local event monitor for Space key down events.
    private var keyMonitor: Any? = nil

    public override init() {
        super.init()
    }

    /// Attaches a local key-down event monitor that intercepts the Space bar (keyCode 49) for Quick Look.
    @MainActor
    public func startKeyboardMonitoring(for appState: AppState) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak appState] event in
            guard let appState = appState else { return event }
            if event.keyCode == 49 { // Space bar
                // Let user type a space normally if focused in an editable text field
                if let window = NSApp.keyWindow,
                   let responder = window.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }

                if QuickLookCoordinator.shared.isVisible {
                    QuickLookCoordinator.shared.closeQuickLook()
                    return nil
                } else if appState.currentSelectedFileURL() != nil {
                    appState.toggleQuickLook()
                    return nil
                } else if let selected = appState.selectedFileVersionHistoryRecord,
                          let previewURL = appState.urlForVersionHistoryRecord(selected) {
                    QuickLookCoordinator.shared.toggleQuickLook(for: previewURL)
                    return nil
                }
            }
            return event
        }
    }

    /// Detaches the local key monitor and closes Quick Look if open.
    @MainActor
    public func stopKeyboardMonitoring() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        closeQuickLook()
    }

    /// Toggles or opens the Quick Look preview panel for the specified file URL.
    /// - Parameter url: Target file URL to preview.
    @MainActor
    public func toggleQuickLook(for url: URL?) {
        guard let url = url, FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false)) else {
            closeQuickLook()
            return
        }

        guard let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible && currentURL == url {
            closeQuickLook()
        } else {
            currentURL = url
            panel.dataSource = self
            panel.delegate = self
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }

    /// Updates the active file selection in the Quick Look panel live if currently visible.
    /// - Parameter url: Selected file URL.
    @MainActor
    public func updateSelection(url: URL?) {
        self.currentURL = url
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(),
              panel.isVisible else { return }

        if let url = url, FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false)) {
            panel.reloadData()
        } else {
            panel.orderOut(nil)
        }
    }

    /// Closes the Quick Look preview panel.
    @MainActor
    public func closeQuickLook() {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() {
            panel.orderOut(nil)
        }
        currentURL = nil
    }

    /// Indicates whether the Quick Look preview panel is currently open on screen.
    @MainActor
    public var isVisible: Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return false }
        return panel.isVisible
    }

    // MARK: - QLPreviewPanelDataSource

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return (currentURL != nil) ? 1 : 0
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let url = currentURL else { return nil }
        return url as NSURL
    }

    // MARK: - QLPreviewPanelDelegate

    public func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown && event.keyCode == 49 { // Spacebar dismiss
            MainActor.assumeIsolated {
                closeQuickLook()
            }
            return true
        }
        return false
    }
}
