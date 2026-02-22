//
//  SelectionOverlayView.swift
//  IssueMark
//

import AppKit

final class SelectionOverlayView: NSView {

    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private var isDragging = false

    override var acceptsFirstResponder: Bool { true }

    /// Allows the first mouse-down (the click that activates the window) to be
    /// treated as a real drag-start event instead of being swallowed by AppKit.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent dark overlay
        NSColor(white: 0, alpha: 0.45).setFill()
        bounds.fill()

        guard isDragging, !currentRect.isEmpty else { return }

        // Reveal the screen beneath the selection
        NSGraphicsContext.current?.cgContext.clear(currentRect)

        // White border around selection
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: currentRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        // Size label
        let isSquare = currentRect.width == currentRect.height
        let sizeStr = "\(Int(currentRect.width)) × \(Int(currentRect.height))\(isSquare ? "  (square)" : "")"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let labelSize = (sizeStr as NSString).size(withAttributes: attrs)

        // Default: draw above selection; fall back to below if it would clip off-screen.
        var labelX = currentRect.minX + 4
        var labelY = currentRect.maxY + 4
        if labelY + labelSize.height > bounds.maxY - 4 {
            labelY = currentRect.minY - labelSize.height - 4
        }
        // Prevent right-edge clipping.
        if labelX + labelSize.width > bounds.maxX - 4 {
            labelX = bounds.maxX - labelSize.width - 4
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

        // Hold Shift to constrain to a square.
        if event.modifierFlags.contains(.shift) {
            let side = max(w, h)
            w = side; h = side
        }

        currentRect = NSRect(
            x: current.x < start.x ? start.x - w : start.x,
            y: current.y < start.y ? start.y - h : start.y,
            width: w, height: h
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

    private func screenRect(from viewRect: NSRect, in window: NSWindow) -> NSRect {
        window.convertToScreen(convert(viewRect, to: nil))
    }
}
