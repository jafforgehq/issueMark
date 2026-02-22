//
//  AnnotationEditorWindow.swift
//  IssueMark
//

import AppKit
import SwiftUI

final class AnnotationEditorWindow: NSWindow {

    // Named constant to avoid magic literals.
    private static let toolbarHeight: CGFloat = 52

    // Strong reference so ARC doesn't collect the window while it's displayed.
    private static var current: AnnotationEditorWindow?

    static func show(with image: NSImage) {
        current?.close()

        let contentSize = NSSize(
            width:  max(image.size.width, 480),
            height: max(image.size.height, 300) + toolbarHeight
        )
        let window = AnnotationEditorWindow(image: image, contentSize: contentSize)
        current = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        // activate() is the non-deprecated form on macOS 14+.
        NSApp.activate()
    }

    private init(image: NSImage, contentSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "IssueMark – Annotate"
        minSize = NSSize(width: 480, height: 300)
        isReleasedWhenClosed = false
        // Use contentViewController (not contentView = NSHostingView) to avoid
        // the "layoutSubtreeIfNeeded called during layout" recursion warning.
        contentViewController = NSHostingController(rootView: AnnotationEditorView(baseImage: image))
    }

    override func close() {
        super.close()
        if AnnotationEditorWindow.current === self {
            AnnotationEditorWindow.current = nil
        }
    }
}
