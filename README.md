# IssueMark

A sleek, efficient macOS menu-bar tool for taking screenshots and annotating them with arrows, text labels, rectangles, numbered callouts, and redactions—all without leaving your workflow.

## Features

- **Quick Screenshot**: Capture full screen, window, or selection from the menu bar
- **Smart Annotations**:
  - **Arrows** with intelligent label positioning (perpendicular to shaft)
  - **Text Labels** with dark backgrounds for readability
  - **Rectangles** for highlighting regions
  - **Numbered Callouts** for step-by-step guides
  - **Redactions** for privacy (solid black fill, non-reversible)
- **Keyboard Shortcuts**: Press 1–5 to switch tools instantly
- **Live Preview**: See label positions update as you draw
- **Tool Persistence**: Your last-selected tool is remembered across sessions
- **Instant Export**: Copy annotated images to clipboard or save as PNG
- **Undo/Redo**: Full undo support (Cmd+Z)
- **Custom Colors**: 6 preset colors or pick any color

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/jafforgehq/issueMark.git
   cd issueMark
   ```

2. Open in Xcode:
   ```bash
   open IssueMark.xcodeproj
   ```

3. Build and run (Cmd+B, then Cmd+R)

## Architecture

- **SwiftUI + AppKit hybrid** for native macOS feel
- **MVVM pattern** with `@Observable` ViewModels
- **NSStatusItem** for menu-bar presence
- **SCScreenshotManager** for system screenshot capture
- **ImageRenderer** for annotation rendering at full resolution

## Key Files

```
IssueMark/
├── IssueMarkApp.swift                    # Entry point with @NSApplicationDelegateAdaptor
├── App/AppDelegate.swift                 # Menu-bar orchestration
├── MenuBar/MenuBarPopoverView.swift      # Popover UI
├── Capture/
│   ├── CaptureManager.swift              # Screenshot capture logic
│   ├── SelectionOverlayWindow.swift      # Full-screen selection window
│   └── SelectionOverlayView.swift        # Mouse drag for selection
└── Annotation/
    ├── Models.swift                       # Arrow, TextLabel, AnnotationTool
    ├── AnnotationEditorViewModel.swift   # Annotation state & rendering
    ├── AnnotationEditorView.swift        # Canvas & toolbar UI
    └── AnnotationEditorWindow.swift      # Editor window management
```

## Usage

1. **Click the IssueMark menu-bar icon** (camera symbol)
2. **Select capture mode**: Full Screen, Window, or Selection
3. **In the annotation editor**:
   - Use **Tool buttons (1–5)** or press number keys to switch tools
   - **Draw arrows**, add text, highlight regions, or redact sensitive areas
   - **Color picker** to change annotation color
   - **Undo (Cmd+Z)** if needed
   - **Copy** to clipboard or **Save** as PNG
   - **Done** (Esc) to close

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `1` | Arrow tool |
| `2` | Text tool |
| `3` | Rectangle tool |
| `4` | Callout tool |
| `5` | Redaction tool |
| `Cmd+Z` | Undo |
| `Esc` | Close annotation editor |
| `Enter` | Confirm pending text |
| `Esc` | Cancel pending text |

## Build Requirements

- macOS 14+
- Xcode 16+
- Swift 5.9+

## Development

The project uses:
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` for thread safety
- `PBXFileSystemSynchronizedRootGroup` for auto-discovery of new Swift files
- App Sandbox + Hardened Runtime for security

## License

MIT

## Author

Fedja Hadziselimovic
