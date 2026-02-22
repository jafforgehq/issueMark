//
//  CaptureManager.swift
//  IssueMark
//

import AppKit
import ScreenCaptureKit

@Observable
final class CaptureManager {

    /// Captures `rect` (AppKit screen coordinates: bottom-left origin, points)
    /// on the display that contains the rect, excluding the overlay window.
    func captureRegion(_ rect: CGRect, excludingWindow overlayWindow: NSWindow) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Match the SCDisplay to the NSScreen that owns this rect.
        let (scDisplay, nsScreen) = try matchDisplay(for: rect, in: content)

        // Exclude the overlay window from the capture.
        let overlayID = CGWindowID(overlayWindow.windowNumber)
        let excluded = content.windows.filter { $0.windowID == overlayID }

        let filter = SCContentFilter(display: scDisplay, excludingWindows: excluded)

        // sourceRect: points, top-left origin.
        // rect is in AppKit coords (bottom-left origin). Convert y:
        //   scY = screenHeight(pts) − appKitY − selectionHeight
        let screenH = nsScreen.frame.height
        let scRect = CGRect(
            x: rect.origin.x - nsScreen.frame.origin.x,   // make relative to display
            y: screenH - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        let scale = nsScreen.backingScaleFactor

        let config = SCStreamConfiguration()
        config.sourceRect = scRect
        config.width  = Int((rect.width  * scale).rounded())
        config.height = Int((rect.height * scale).rounded())

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        )
        // Return at logical (point) size so annotation coordinates are 1:1.
        return NSImage(cgImage: cgImage, size: rect.size)
    }

    // MARK: - Helpers

    /// Finds the SCDisplay / NSScreen pair whose bounds contain `rect`.
    private func matchDisplay(
        for rect: CGRect,
        in content: SCShareableContent
    ) throws -> (SCDisplay, NSScreen) {
        for scDisplay in content.displays {
            // CGDirectDisplayID is used as the bridge between SC and NS worlds.
            if let nsScreen = NSScreen.screens.first(where: {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                    == scDisplay.displayID
            }) {
                if nsScreen.frame.contains(rect.origin) {
                    return (scDisplay, nsScreen)
                }
            }
        }
        // Fall back to the first display if nothing matches.
        guard let scDisplay = content.displays.first else { throw CaptureError.noDisplay }
        let nsScreen = NSScreen.main ?? NSScreen.screens[0]
        return (scDisplay, nsScreen)
    }
}

enum CaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        "No display found to capture."
    }
}
