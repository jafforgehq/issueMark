//
//  Models.swift
//  IssueMark
//

import SwiftUI

// MARK: - Annotation types

struct Arrow: Identifiable {
    var id = UUID()
    var start: CGPoint
    var end: CGPoint
    var color: Color
    var strokeWidth: CGFloat = 2.5

    var labelPosition: CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = sqrt(dx*dx + dy*dy)
        guard len > 0 else { return start }
        let ux = dx/len, uy = dy/len
        let px = -uy, py = ux           // perpendicular-left
        return CGPoint(x: start.x - ux*4 + px*14,
                       y: start.y - uy*4 + py*14)
    }
}

struct TextLabel: Identifiable {
    var id = UUID()
    var position: CGPoint
    var text: String
    var color: Color
    var fontSize: CGFloat = 14
}

struct RectAnnotation: Identifiable {
    var id = UUID()
    var rect: CGRect
    var color: Color
    var strokeWidth: CGFloat = 2.5
}

struct Callout: Identifiable {
    var id = UUID()
    var center: CGPoint
    var number: Int
    var color: Color
}

/// Solid-fill redaction rectangle (privacy-safe: not reversible unlike blur).
struct Redaction: Identifiable {
    var id = UUID()
    var rect: CGRect
}

/// Blur rectangle for privacy.
struct Blur: Identifiable {
    var id = UUID()
    var rect: CGRect
}

/// Highlight/marker overlay (semi-transparent yellow).
struct Highlight: Identifiable {
    var id = UUID()
    var rect: CGRect
}

// MARK: - Tool

enum AnnotationTool: String, CaseIterable {
    case arrow = "arrow"
    case text = "text"
    case callout = "callout"
    case redact = "redact"
    case blur = "blur"
    case highlight = "highlight"

    var icon: String {
        switch self {
        case .arrow:     return "arrow.up.right"
        case .text:      return "text.cursor"
        case .callout:   return "number.circle"
        case .redact:    return "square.slash"
        case .blur:      return "eye.slash"
        case .highlight: return "highlighter"
        }
    }

    var tooltip: String {
        switch self {
        case .arrow:     return "Arrow (drag; Enter to add label, Esc to skip) (1)"
        case .text:      return "Text label (click) (2)"
        case .callout:   return "Numbered callout (click) (3)"
        case .redact:    return "Redact / solid fill (drag) (4)"
        case .blur:      return "Blur region (drag) (5)"
        case .highlight: return "Highlight / marker (drag) (6)"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .arrow:     return "1"
        case .text:      return "2"
        case .callout:   return "3"
        case .redact:    return "4"
        case .blur:      return "5"
        case .highlight: return "6"
        }
    }
}

// MARK: - Undo snapshot

struct AnnotationSnapshot {
    var arrows: [Arrow]
    var labels: [TextLabel]
    var rectAnnotations: [RectAnnotation]
    var callouts: [Callout]
    var redactions: [Redaction]
    var blurs: [Blur]
    var highlights: [Highlight]
    var nextCalloutNumber: Int
}
