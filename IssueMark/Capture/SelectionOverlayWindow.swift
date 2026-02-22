//
//  SelectionOverlayWindow.swift
//  IssueMark
//

import AppKit

final class SelectionOverlayWindow: NSWindow {

    // Strong reference so ARC doesn't collect the window while it's visible.
    private static var current: SelectionOverlayWindow?

    private let overlayView = SelectionOverlayView()

    /// Shows the selection overlay on the screen that currently contains the mouse cursor.
    /// `completion` is called with the selected rect in screen coordinates (bottom-left origin)
    /// and a reference to the overlay window so the capture can exclude it.
    static func show(completion: @escaping (CGRect, NSWindow) -> Void) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let window = SelectionOverlayWindow(screen: screen)
        current = window

        window.overlayView.onSelectionComplete = { rect in
            // Capture `window` strongly so it stays alive during the async capture.
            NSCursor.pop()
            window.orderOut(nil)
            SelectionOverlayWindow.current = nil
            completion(rect, window)
        }

        window.overlayView.onCancel = {
            NSCursor.pop()
            window.orderOut(nil)
            SelectionOverlayWindow.current = nil
        }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.overlayView)
    }

    private init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        contentView = overlayView
        NSCursor.crosshair.push()
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKey: Bool { true }
}
