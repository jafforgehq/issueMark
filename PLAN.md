# IssueMark – Implementation Plan

## Context
Fresh SwiftUI macOS app (`com.jafforge.IssueMark`, macOS 26.2 target, sandbox + hardened runtime already enabled). The goal is a menu bar tool that lets you capture a screen region, annotate it with arrows and labels, then either copy to clipboard or save to file.

## User choices
- Export: both Copy to Clipboard + Save to File
- Distribution: Direct (outside Mac App Store)

---

## Architecture Overview

SwiftUI + AppKit hybrid. AppKit is required for `NSStatusItem` (menu bar) and the full-screen capture overlay (`NSWindow`). SwiftUI handles the popover and annotation editor UI.

Pattern: MVVM — thin AppDelegate orchestrates windows; ViewModels hold state.

---

## File Plan

### Modify existing files
| File | Change |
|---|---|
| `IssueMark/IssueMarkApp.swift` | Replace `WindowGroup` scene with `@NSApplicationDelegateAdaptor(AppDelegate.self)` + empty `Settings {}` scene |
| `IssueMark/ContentView.swift` | Delete (replaced by MenuBarPopoverView) |

### Create new files

```
IssueMark/
├── App/
│   └── AppDelegate.swift               # NSStatusItem, NSPopover, wires everything together
├── MenuBar/
│   └── MenuBarPopoverView.swift        # SwiftUI: "Capture Area" button + quit button
├── Capture/
│   ├── CaptureManager.swift            # Permission check + ScreenCaptureKit capture
│   ├── SelectionOverlayWindow.swift    # Borderless full-screen NSWindow
│   └── SelectionOverlayView.swift      # NSView: tracks mouse drag, draws dim + selection rect
└── Annotation/
    ├── Models.swift                     # Arrow, TextLabel structs (value types, Identifiable)
    ├── AnnotationEditorViewModel.swift  # @Observable: tool selection, annotations array, export
    ├── AnnotationEditorView.swift       # SwiftUI Canvas + toolbar overlay
    └── AnnotationEditorWindow.swift     # NSWindow subclass that hosts the SwiftUI editor
```

### Info.plist additions
```xml
<key>LSUIElement</key><true/>   <!-- hides dock icon -->
<key>NSScreenCaptureUsageDescription</key>
<string>IssueMark needs screen recording access to capture a selected area of your screen.</string>
```

### Entitlements (IssueMark.entitlements)
No extra entitlement needed for screen recording on direct distribution — user grants access in System Settings > Privacy & Security > Screen Recording. Keep existing sandbox + hardened runtime entries.

---

## Implementation Steps

- [x] Step 0 – Read existing project structure
- [x] Step 1 – Menu Bar skeleton
- [x] Step 2 – Screen recording permission
- [x] Step 3 – Area selection overlay
- [x] Step 4 – Screen capture (ScreenCaptureKit)
- [x] Step 5 – Annotation editor (Models, ViewModel, View, Window)
- [x] Step 6 – Wiring (AppDelegate full flow)
- [x] Step 7 – Info.plist additions

## Bug Fixes Applied
- `ENABLE_USER_SELECTED_FILES` changed from `readonly` → `"read-write"` (save-to-file was broken in sandbox)
- `NSCursor.pop()` added to both overlay dismiss paths (cursor was stuck as crosshair)
- Removed explicit `popover.contentSize` (height was clipping the popover content)
- Removed non-existent `SCStreamConfiguration.scaleFactor` property
- Added missing `import UniformTypeIdentifiers` for `UTType.png`

---

## Step 1 – Menu Bar skeleton
- `IssueMarkApp.swift`: use `@NSApplicationDelegateAdaptor`, no `WindowGroup`
- `AppDelegate.swift`: create `NSStatusItem` with SF Symbol (`camera.viewfinder`) as button image, attach `NSPopover` containing `MenuBarPopoverView`
- `MenuBarPopoverView.swift`: "Capture Area" button + "Quit IssueMark" button at bottom
- `Info.plist`: add `LSUIElement = YES`

## Step 2 – Screen recording permission
- `CaptureManager.swift` (singleton `@Observable`):
  - `checkPermission()` → `CGPreflightScreenCaptureAccess()`
  - `requestPermission()` → `CGRequestScreenCaptureAccess()` (triggers system prompt)
  - On "Capture Area" press: check permission; if denied show an `NSAlert` directing user to System Settings

## Step 3 – Area selection overlay
- `SelectionOverlayWindow.swift`: borderless, transparent `NSWindow` at level `.screenSaver`, covering the main display. Shows a semi-transparent dark overlay.
- `SelectionOverlayView.swift` (`NSView` subclass):
  - `mouseDown` → record `startPoint`
  - `mouseDragged` → update `currentRect`, call `setNeedsDisplay`
  - `mouseUp` → call completion closure with final `CGRect`, close window
  - Drawing: fill full rect with `rgba(0,0,0,0.4)`, clear the selection rect, draw white 1pt border around selection
  - ESC key cancels and closes overlay

## Step 4 – Screen capture
After `mouseUp`, hide the overlay window, then capture using **ScreenCaptureKit**:
```swift
let filter = SCContentFilter(display: display, excludingWindows: [overlayWindow])
let config = SCStreamConfiguration()
config.sourceRect = selectedCGRect   // in display coordinates
let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
```
Convert `CGImage` → `NSImage`, pass to `AnnotationEditorWindow`.

## Step 5 – Annotation editor

**Models.swift**
```swift
struct Arrow: Identifiable { var id = UUID(); var start, end: CGPoint; var color: Color }
struct TextLabel: Identifiable { var id = UUID(); var position: CGPoint; var text: String; var color: Color }
```

**AnnotationEditorViewModel.swift** (`@Observable`)
- `tool: Tool` enum (`.arrow`, `.text`)
- `arrows: [Arrow]`, `labels: [TextLabel]`
- `selectedColor: Color`
- `dragStart: CGPoint?` (in-progress arrow)
- `exportToClipboard(image: NSImage)` — renders canvas to `NSImage`, writes to `NSPasteboard`
- `saveToFile(image: NSImage)` — renders canvas, shows `NSSavePanel`, writes PNG

**AnnotationEditorView.swift** (SwiftUI)
- `Image(nsImage:)` fills the view as background
- `Canvas` overlay draws all arrows (line + arrowhead triangle) and labels
- `DragGesture` on Canvas: if tool == `.arrow`, draw in-progress arrow live
- `TapGesture`: if tool == `.text`, show inline text field at tap location
- Bottom toolbar: Arrow tool button, Text tool button, `ColorPicker`, "Copy" button, "Save" button, "Done/Close" button

**AnnotationEditorWindow.swift**
- `NSWindow` subclass, titled "IssueMark – Annotate", not resizable below image size
- Hosts `NSHostingView<AnnotationEditorView>`
- Opens centered on screen

## Step 6 – Wiring (AppDelegate)
Full flow:
1. User clicks "Capture Area" → popover closes
2. `CaptureManager.checkPermission()` → if denied show alert
3. `SelectionOverlayWindow` appears
4. On selection complete → capture → open `AnnotationEditorWindow`

---

## Permissions Summary
| Permission | How enabled |
|---|---|
| Screen Recording | `NSScreenCaptureUsageDescription` in Info.plist; user grants in System Settings |
| No microphone/camera/network needed | — |

---

## Verification Checklist
- [ ] Build and run → app appears in menu bar only (no Dock icon)
- [ ] Click menu bar icon → popover with "Capture Area"
- [ ] First launch: clicking Capture Area triggers system permission dialog
- [ ] After permission granted: full-screen dim overlay appears, drag selects region
- [ ] ESC cancels cleanly
- [ ] After selection: annotation editor window opens with captured image
- [ ] Draw arrows by click-dragging
- [ ] Click with text tool to place labels
- [ ] "Copy" copies annotated image to clipboard (paste in Slack to verify)
- [ ] "Save" opens save panel, saves PNG
