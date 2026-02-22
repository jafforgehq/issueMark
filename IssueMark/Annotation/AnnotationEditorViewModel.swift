//
//  AnnotationEditorViewModel.swift
//  IssueMark
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ViewModel

@Observable
final class AnnotationEditorViewModel {

    // MARK: Tool + colour
    var tool: AnnotationTool = {
        if let raw = UserDefaults.standard.string(forKey: "lastTool"),
           let t = AnnotationTool(rawValue: raw) { return t }
        return .arrow
    }() {
        didSet { UserDefaults.standard.set(tool.rawValue, forKey: "lastTool") }
    }
    var selectedColor: Color = .red
    var didCopyToClipboard: Bool = false

    // MARK: Committed annotations
    var arrows: [Arrow] = []
    var labels: [TextLabel] = []
    var rectAnnotations: [RectAnnotation] = []
    var callouts: [Callout] = []
    var redactions: [Redaction] = []
    var nextCalloutNumber: Int = 1

    // MARK: In-progress drag state
    var dragStart: CGPoint?
    var dragCurrent: CGPoint?

    /// Arrow waiting for an optional label (auto-label flow).
    var pendingArrow: Arrow?

    // MARK: Text input state
    var pendingTextPosition: CGPoint?
    var pendingText = ""

    // MARK: Canvas size (set by the view via GeometryReader)
    var canvasSize: CGSize = .zero

    // MARK: Undo
    private var history: [AnnotationSnapshot] = []
    private let maxHistoryDepth = 50

    func saveSnapshot() {
        let snap = AnnotationSnapshot(
            arrows: arrows, labels: labels,
            rectAnnotations: rectAnnotations, callouts: callouts,
            redactions: redactions, nextCalloutNumber: nextCalloutNumber
        )
        history.append(snap)
        if history.count > maxHistoryDepth { history.removeFirst() }
    }

    func undo() {
        guard let snap = history.popLast() else { return }
        arrows            = snap.arrows
        labels            = snap.labels
        rectAnnotations   = snap.rectAnnotations
        callouts          = snap.callouts
        redactions        = snap.redactions
        nextCalloutNumber = snap.nextCalloutNumber
        // Cancel any in-progress input
        pendingArrow = nil
        pendingTextPosition = nil
        pendingText = ""
        dragStart = nil
        dragCurrent = nil
    }

    var canUndo: Bool { !history.isEmpty }

    // MARK: Derived helpers

    /// Rectangle formed by the current drag start/end (used for .rectangle and .redact tools).
    var dragRect: CGRect? {
        guard let s = dragStart, let e = dragCurrent else { return nil }
        return CGRect(
            x: min(s.x, e.x), y: min(s.y, e.y),
            width: abs(e.x - s.x), height: abs(e.y - s.y)
        )
    }

    // MARK: Pending text / arrow commit

    func commitPendingText() {
        if let arrow = pendingArrow {
            // Auto-label flow: always commit the arrow, optionally attach label.
            saveSnapshot()
            arrows.append(arrow)
            let trimmed = pendingText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, let pos = pendingTextPosition {
                labels.append(TextLabel(position: pos, text: trimmed, color: selectedColor))
            }
            pendingArrow = nil
        } else {
            // Plain text-tool flow.
            let trimmed = pendingText.trimmingCharacters(in: .whitespaces)
            guard let pos = pendingTextPosition, !trimmed.isEmpty else {
                pendingTextPosition = nil
                pendingText = ""
                return
            }
            saveSnapshot()
            labels.append(TextLabel(position: pos, text: trimmed, color: selectedColor))
        }
        pendingTextPosition = nil
        pendingText = ""
    }

    /// Escape during pending text: commit arrow (if any) without a label, discard text.
    func cancelPendingText() {
        if let arrow = pendingArrow {
            saveSnapshot()
            arrows.append(arrow)
            pendingArrow = nil
        }
        pendingTextPosition = nil
        pendingText = ""
    }

    // MARK: Export

    /// Renders base image + all annotations. Scales annotation coordinates from canvas
    /// space to image space so exports are always at full image resolution.
    @MainActor
    func renderAnnotated(baseImage: NSImage) -> NSImage {
        let imageSize = baseImage.size
        let canvas = canvasSize == .zero ? imageSize : canvasSize

        let sx = imageSize.width  / canvas.width
        let sy = imageSize.height / canvas.height

        let capturedArrows  = arrows
        let capturedLabels  = labels
        let capturedRects   = rectAnnotations
        let capturedCallouts = callouts
        let capturedRedactions = redactions

        let view = ZStack(alignment: .topLeading) {
            Image(nsImage: baseImage)
                .resizable()
                .frame(width: imageSize.width, height: imageSize.height)
            Canvas { context, _ in
                var ctx = context
                // Scale annotation coordinates (canvas → image).
                if sx != 1 || sy != 1 { ctx.scaleBy(x: sx, y: sy) }
                AnnotationRenderer.drawAll(
                    in: ctx,
                    arrows: capturedArrows, labels: capturedLabels,
                    rects: capturedRects, callouts: capturedCallouts,
                    redactions: capturedRedactions,
                    inProgressArrow: nil, inProgressRect: nil, inProgressTool: .arrow
                )
            }
            .frame(width: imageSize.width, height: imageSize.height)
        }
        .frame(width: imageSize.width, height: imageSize.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return renderer.nsImage ?? baseImage
    }

    @MainActor
    func exportToClipboard(baseImage: NSImage) {
        let rendered = renderAnnotated(baseImage: baseImage)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([rendered])
        didCopyToClipboard = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyToClipboard = false
        }
    }

    @MainActor
    func saveToFile(baseImage: NSImage) {
        let rendered = renderAnnotated(baseImage: baseImage)
        guard let tiff   = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png    = bitmap.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screenshot.png"
        panel.title = "Save Screenshot"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try png.write(to: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Save Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

// MARK: - AnnotationRenderer

/// Pure drawing utilities. Separated from the ViewModel to keep concerns distinct.
enum AnnotationRenderer {

    static func drawAll(
        in context: GraphicsContext,
        arrows: [Arrow],
        labels: [TextLabel],
        rects: [RectAnnotation],
        callouts: [Callout],
        redactions: [Redaction],
        inProgressArrow: Arrow?,
        inProgressRect: CGRect?,
        inProgressTool: AnnotationTool
    ) {
        var ctx = context

        // Redactions first (behind everything)
        for r in redactions { drawRedaction(in: &ctx, redaction: r) }

        // In-progress redaction preview
        if let rect = inProgressRect, inProgressTool == .redact {
            ctx.fill(Path(rect), with: .color(.black.opacity(0.65)))
        }

        // Rectangles
        for r in rects { drawRect(in: &ctx, rect: r) }

        // In-progress rectangle preview (dashed)
        if let rect = inProgressRect, inProgressTool == .rectangle {
            ctx.stroke(
                Path(roundedRect: rect, cornerRadius: 3),
                with: .color(.white.opacity(0.9)),
                style: StrokeStyle(lineWidth: 2, dash: [6, 3])
            )
        }

        // Arrows
        for a in arrows { drawArrow(in: &ctx, arrow: a) }
        if let a = inProgressArrow { drawArrow(in: &ctx, arrow: a) }

        // Callouts
        for c in callouts { drawCallout(in: &ctx, callout: c) }

        // Labels (always on top)
        for l in labels { drawLabel(in: &ctx, label: l) }
    }

    static func drawArrow(in context: inout GraphicsContext, arrow: Arrow) {
        var line = Path()
        line.move(to: arrow.start)
        line.addLine(to: arrow.end)
        context.stroke(line, with: .color(arrow.color),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        let dx = arrow.end.x - arrow.start.x
        let dy = arrow.end.y - arrow.start.y
        guard dx != 0 || dy != 0 else { return }

        let headLen: CGFloat = 14
        let headAngle: CGFloat = .pi / 6
        let angle = atan2(dy, dx)
        let p1 = CGPoint(x: arrow.end.x - headLen * cos(angle - headAngle),
                         y: arrow.end.y - headLen * sin(angle - headAngle))
        let p2 = CGPoint(x: arrow.end.x - headLen * cos(angle + headAngle),
                         y: arrow.end.y - headLen * sin(angle + headAngle))
        var head = Path()
        head.move(to: arrow.end)
        head.addLine(to: p1)
        head.addLine(to: p2)
        head.closeSubpath()
        context.fill(head, with: .color(arrow.color))
    }

    static func drawLabel(in context: inout GraphicsContext, label: TextLabel) {
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let textSize = (label.text as NSString).size(withAttributes: [.font: font])
        let hPad: CGFloat = 6, vPad: CGFloat = 3
        let bgRect = CGRect(
            x: label.position.x - textSize.width/2 - hPad,
            y: label.position.y - textSize.height/2 - vPad,
            width: textSize.width + hPad*2, height: textSize.height + vPad*2)
        context.fill(Path(roundedRect: bgRect, cornerRadius: 4), with: .color(.black.opacity(0.5)))
        context.draw(Text(label.text).font(.system(size: 14, weight: .semibold)).foregroundStyle(label.color),
                     at: label.position)
    }

    static func drawRect(in context: inout GraphicsContext, rect: RectAnnotation) {
        context.stroke(
            Path(roundedRect: rect.rect, cornerRadius: 3),
            with: .color(rect.color),
            style: StrokeStyle(lineWidth: 2.5)
        )
    }

    static func drawCallout(in context: inout GraphicsContext, callout: Callout) {
        let r: CGFloat = 14
        let circle = CGRect(x: callout.center.x - r, y: callout.center.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: circle), with: .color(callout.color))
        context.stroke(Path(ellipseIn: circle), with: .color(.white),
                       style: StrokeStyle(lineWidth: 1.5))
        context.draw(
            Text("\(callout.number)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white),
            at: callout.center
        )
    }

    static func drawRedaction(in context: inout GraphicsContext, redaction: Redaction) {
        context.fill(Path(redaction.rect), with: .color(.black))
    }
}
