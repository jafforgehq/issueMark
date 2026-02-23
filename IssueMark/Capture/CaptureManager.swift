//
//  CaptureManager.swift
//  IssueMark
//

import AppKit
import ScreenCaptureKit

@Observable
@MainActor
final class CaptureManager {

    /// Captures the specified region from the display containing it.
    /// - Parameters:
    ///   - rect: Selection rectangle in AppKit screen coordinates (bottom-left origin, points).
    ///           Coordinates are relative to the screen's origin, not absolute.
    ///   - overlayWindow: Window to exclude from capture (typically the selection overlay).
    /// - Returns: Image at logical point size (1:1 with rect dimensions).
    ///           Width and height match the rect's dimensions; pixels scale with display backingScaleFactor.
    /// - Throws: CaptureError.noDisplay if no matching display found.
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
    /// Bridges between ScreenCaptureKit (SC) and AppKit (NS) coordinate systems.
    /// - Parameters:
    ///   - rect: Selection rectangle in AppKit coordinates (bottom-left origin).
    ///   - content: Shareable content containing available displays.
    /// - Returns: Tuple of (SCDisplay for capture, NSScreen for coordinate conversion).
    /// - Throws: CaptureError.noDisplay if no displays available.
    /// - Note: CGDirectDisplayID serves as the bridge between SC and NS display IDs.
    private func matchDisplay(
        for rect: CGRect,
        in content: SCShareableContent
    ) throws -> (SCDisplay, NSScreen) {
        // Try to find exact match by checking which screen contains the rect origin
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

        // Fall back to primary display if no exact match
        guard let scDisplay = content.displays.first else {
            NSLog("IssueMark: No shareable displays found")
            throw CaptureError.noDisplay
        }
        let nsScreen = NSScreen.main ?? NSScreen.screens[0]
        NSLog("IssueMark: Using fallback display for capture")
        return (scDisplay, nsScreen)
    }
}

enum CaptureError: LocalizedError {
    case noDisplay

    var errorDescription: String? {
        "No display found to capture."
    }
}
