//
//  AnnotationEditorView.swift
//  IssueMark
//

import SwiftUI

struct AnnotationEditorView: View {
    let baseImage: NSImage
    @State private var vm = AnnotationEditorViewModel()
    @State private var isHoveringCanvas = false

    var body: some View {
        VStack(spacing: 0) {
            canvasArea
            Divider()
            toolbar
        }
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { proxy in
            let fitted = fittedSize(imageSize: baseImage.size, in: proxy.size)
            ZStack {
                Image(nsImage: baseImage)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)

                Canvas { context, _ in
                    let inProgressArrow: Arrow? = vm.pendingArrow
                        ?? (vm.tool == .arrow
                            ? vm.dragStart.flatMap { s in
                                vm.dragCurrent.map { e in Arrow(start: s, end: e, color: vm.selectedColor) }
                            }
                            : nil)

                    AnnotationRenderer.drawAll(
                        in: context,
                        arrows: vm.arrows, labels: vm.labels,
                        rects: vm.rectAnnotations, callouts: vm.callouts,
                        redactions: vm.redactions,
                        inProgressArrow: inProgressArrow,
                        inProgressRect: vm.dragRect,
                        inProgressTool: vm.tool
                    )

                    if vm.tool == .arrow, let s = vm.dragStart, let e = vm.dragCurrent {
                        let preview = Arrow(start: s, end: e, color: vm.selectedColor)
                        let dot = preview.labelPosition
                        let r: CGFloat = 4
                        let dotRect = CGRect(x: dot.x - r, y: dot.y - r, width: r*2, height: r*2)
                        context.fill(Path(ellipseIn: dotRect), with: .color(vm.selectedColor.opacity(0.8)))
                        context.stroke(Path(ellipseIn: dotRect), with: .color(.white.opacity(0.7)),
                                       style: StrokeStyle(lineWidth: 1))
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .gesture(makeDragGesture())
                .onTapGesture { location in handleTap(at: location) }
                .onHover { hovering in
                    isHoveringCanvas = hovering
                    if hovering { cursorForTool(vm.tool).push() } else { NSCursor.pop() }
                }
                .onChange(of: vm.tool) { _, newTool in
                    if isHoveringCanvas { NSCursor.pop(); cursorForTool(newTool).push() }
                }

                // Pending text field (arrow auto-label or text tool)
                if let pos = vm.pendingTextPosition {
                    TextField(vm.pendingArrow != nil ? "Label… (Enter to add, Esc to skip)" : "Label…",
                              text: $vm.pendingText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(vm.selectedColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.55)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(vm.selectedColor.opacity(0.8), lineWidth: 1))
                        .fixedSize()
                        .position(pos)
                        .onSubmit { vm.commitPendingText() }
                        .onKeyPress(.escape) { vm.cancelPendingText(); return .handled }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { vm.canvasSize = fitted }
            .onChange(of: fitted) { _, s in vm.canvasSize = s }
        }
    }

    private func fittedSize(imageSize: CGSize, in available: CGSize) -> CGSize {
        guard available.width > 0, available.height > 0 else { return imageSize }
        let scale = min(available.width / imageSize.width, available.height / imageSize.height)
        // Never upscale; only downscale if the image is larger than the available area.
        let s = min(scale, 1.0)
        return CGSize(width: imageSize.width * s, height: imageSize.height * s)
    }

    private func cursorForTool(_ tool: AnnotationTool) -> NSCursor {
        switch tool {
        case .arrow, .rectangle, .redact: return .crosshair
        case .text, .callout:             return .iBeam
        }
    }

    // MARK: - Gestures

    private func makeDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard vm.tool == .arrow || vm.tool == .rectangle || vm.tool == .redact else { return }
                if vm.dragStart == nil { vm.dragStart = value.startLocation }
                vm.dragCurrent = value.location
            }
            .onEnded { value in
                defer { vm.dragStart = nil; vm.dragCurrent = nil }
                switch vm.tool {
                case .arrow:
                    guard let start = vm.dragStart else { return }
                    let arrow = Arrow(start: start, end: value.location, color: vm.selectedColor)
                    let length = hypot(arrow.end.x - arrow.start.x, arrow.end.y - arrow.start.y)
                    if length > 20 {
                        // Trigger auto-label: commit arrow on Enter, skip on Esc.
                        vm.pendingArrow = arrow
                        vm.pendingTextPosition = arrow.labelPosition
                        vm.pendingText = ""
                    } else {
                        vm.saveSnapshot()
                        vm.arrows.append(arrow)
                    }
                case .rectangle:
                    guard let rect = vm.dragRect, rect.width > 4, rect.height > 4 else { return }
                    vm.saveSnapshot()
                    vm.rectAnnotations.append(RectAnnotation(rect: rect, color: vm.selectedColor))
                case .redact:
                    guard let rect = vm.dragRect, rect.width > 4, rect.height > 4 else { return }
                    vm.saveSnapshot()
                    vm.redactions.append(Redaction(rect: rect))
                default:
                    break
                }
            }
    }

    private func handleTap(at location: CGPoint) {
        // Commit any open text field first.
        if vm.pendingTextPosition != nil { vm.commitPendingText() }

        switch vm.tool {
        case .text:
            vm.pendingTextPosition = location
            vm.pendingText = ""
        case .callout:
            vm.saveSnapshot()
            vm.callouts.append(Callout(center: location, number: vm.nextCalloutNumber, color: vm.selectedColor))
            vm.nextCalloutNumber += 1
        default:
            break
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            // Tool buttons
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                toolButton(for: tool)
            }

            Divider().frame(height: 20)

            ColorPicker("", selection: $vm.selectedColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28)
                .help("Annotation colour")

            Spacer()

            // Undo
            Button {
                vm.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!vm.canUndo)
            .help("Undo (⌘Z)")
            .keyboardShortcut("z", modifiers: .command)

            Divider().frame(height: 20)

            Button {
                flushPendingInput()
                vm.exportToClipboard(baseImage: baseImage)
            } label: {
                if vm.didCopyToClipboard {
                    Label("Copied!", systemImage: "checkmark").foregroundStyle(.green)
                } else {
                    Label("Copy", systemImage: "doc.on.clipboard")
                }
            }
            .help("Copy annotated image to clipboard")

            Button {
                flushPendingInput()
                vm.saveToFile(baseImage: baseImage)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .help("Save as PNG…")

            Divider().frame(height: 20)

            Button("Done") {
                NSApp.keyWindow?.close()
            }
            .help("Close the annotation editor")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func toolButton(for tool: AnnotationTool) -> some View {
        let isSelected = vm.tool == tool
        return Button {
            if vm.pendingTextPosition != nil { vm.commitPendingText() }
            vm.tool = tool
        } label: {
            Image(systemName: tool.icon)
                .frame(width: 26, height: 26)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(tool.tooltip)
        .keyboardShortcut(tool.shortcutKey, modifiers: [])
    }

    private func flushPendingInput() {
        if vm.pendingTextPosition != nil { vm.commitPendingText() }
    }
}
