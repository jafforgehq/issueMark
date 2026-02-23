//
//  SelectionOverlayView.swift
//  IssueMark
//

import AppKit

/// Full-screen view for interactive rectangle selection.
/// Displays a semi-transparent overlay with a clear selection rectangle and dimension label.
/// Communicates selection via closures when user completes or cancels.
final class SelectionOverlayView: NSView {

    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isDragging = false

    // Overlay appearance constants
    private let dimOverlayOpacity: CGFloat = 0.45  // Visible yet dim enough to see screen
    private let selectionBorderWidth: CGFloat = 1
    private let labelFontSize: CGFloat = 11
    private let edgeInset: CGFloat = 4

    override var acceptsFirstResponder: Bool { true }

    /// Allows the first mouse-down (the click that activates the window) to be
    /// treated as a real drag-start event instead of being swallowed by AppKit.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent dark overlay dims the screen
        NSColor(white: 0, alpha: dimOverlayOpacity).setFill()
        bounds.fill()

        guard isDragging, !currentRect.isEmpty else { return }

        // Reveal the screen beneath the selection
        NSGraphicsContext.current?.cgContext.clear(currentRect)

        // White border around selection
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: currentRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = selectionBorderWidth
        border.stroke()

        // Size label with optional "square" indicator
        let isSquare = currentRect.width == currentRect.height
        let sizeStr = "\(Int(currentRect.width)) × \(Int(currentRect.height))\(isSquare ? "  (square)" : "")"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: labelFontSize, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let labelSize = (sizeStr as NSString).size(withAttributes: attrs)

        // Position label: prefer above selection, fall back to below if would clip
        var labelX = currentRect.minX + edgeInset
        var labelY = currentRect.maxY + edgeInset
        if labelY + labelSize.height > bounds.maxY - edgeInset {
            labelY = currentRect.minY - labelSize.height - edgeInset
        }
        // Prevent right-edge clipping
        if labelX + labelSize.width > bounds.maxX - edgeInset {
            labelX = bounds.maxX - labelSize.width - edgeInset
        }
        (sizeStr as NSString).draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        isDragging = false
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)

        var w = abs(current.x - start.x)
        var h = abs(current.y - start.y)

        // Shift modifier: constrain to square selection
        if event.modifierFlags.contains(.shift) {
            let side = max(w, h)
            w = side
            h = side
        }

        // Calculate rect origin depending on drag direction
        currentRect = NSRect(
            x: current.x < start.x ? start.x - w : start.x,
            y: current.y < start.y ? start.y - h : start.y,
            width: w,
            height: h
        )
        isDragging = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging, !currentRect.isEmpty else {
            onCancel?()
            return
        }
        let selectedRect = window.map { screenRect(from: currentRect, in: $0) } ?? currentRect
        onSelectionComplete?(selectedRect)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        // keyCode 53 = Escape
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    // MARK: - Helpers

    /// Converts a selection rectangle from view coordinates to screen coordinates.
    /// - Parameters:
    ///   - viewRect: Rectangle in view coordinate system
    ///   - window: Window to convert through
    /// - Returns: Rectangle in screen coordinate system (bottom-left origin)
    private func screenRect(from viewRect: NSRect, in window: NSWindow) -> NSRect {
        window.convertToScreen(convert(viewRect, to: nil))
    }
}
