//
//  MenuBarPopoverView.swift
//  IssueMark
//

import SwiftUI

struct MenuBarPopoverView: View {
    let onCapture: () -> Void
    let onQuickCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onCapture) {
                Label("Capture Area…", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Capture a region and open the annotation editor (⌘⇧6)")

            Button(action: onQuickCapture) {
                Label("Quick Copy", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Capture a region and copy directly to clipboard")

            Divider()

            Button("Quit IssueMark") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(width: 230)
    }
}
