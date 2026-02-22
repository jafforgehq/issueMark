//
//  AppDelegate.swift
//  IssueMark
//

import AppKit
import Carbon
import SwiftUI

// MARK: - Carbon hotkey callback (free function — required for C interop)

private func issueMarkHotKeyCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { delegate.startCapture() }
    return noErr
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    let captureManager = CaptureManager()

    // Carbon global hotkey (Cmd+Shift+6)
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        setupPopover()
        registerGlobalHotKey()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "IssueMark")
        button.action = #selector(togglePopover)
        button.target = self
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                onCapture:      { [weak self] in self?.startCapture() },
                onQuickCapture: { [weak self] in self?.startQuickCapture() }
            )
        )
    }

    // MARK: - Global hotkey (Cmd+Shift+6)

    private func registerGlobalHotKey() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            issueMarkHotKeyCallback,
            1, &eventSpec,
            selfPtr,
            &hotKeyHandlerRef
        )
        let hkID = EventHotKeyID(signature: 0x49534D4B /* ISMK */, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_6),
            UInt32(cmdKey | shiftKey),
            hkID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    // MARK: - Capture flow

    func startCapture() {
        popover.performClose(nil)
        checkPermissionThenCapture(mode: .annotate)
    }

    func startQuickCapture() {
        popover.performClose(nil)
        checkPermissionThenCapture(mode: .quickCopy)
    }

    private func checkPermissionThenCapture(mode: CaptureMode) {
        if !CGPreflightScreenCaptureAccess() {
            // Show the system prompt (no-op if already shown). Always returns false
            // on first call on macOS 13+; user must grant and re-trigger.
            CGRequestScreenCaptureAccess()
            showPermissionAlert()
            return
        }
        showSelectionOverlay(mode: mode)
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Grant IssueMark access in System Settings › Privacy & Security › Screen Recording, then click Capture Area again."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showSelectionOverlay(mode: CaptureMode) {
        SelectionOverlayWindow.show { [weak self] selectedRect, overlayWindow in
            guard let self else { return }
            Task { @MainActor in
                do {
                    let image = try await self.captureManager.captureRegion(
                        selectedRect, excludingWindow: overlayWindow
                    )
                    switch mode {
                    case .annotate:
                        AnnotationEditorWindow.show(with: image)
                    case .quickCopy:
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([image])
                        self.flashMenuBarConfirmation()
                    }
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Capture Failed"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    /// Briefly shows a checkmark in the menu bar to confirm a quick copy.
    private func flashMenuBarConfirmation() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "checkmark.circle", accessibilityDescription: "Copied!")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.statusItem.button?.image = NSImage(
                systemSymbolName: "camera.viewfinder", accessibilityDescription: "IssueMark")
        }
    }
}

// MARK: - Capture mode

enum CaptureMode { case annotate, quickCopy }
