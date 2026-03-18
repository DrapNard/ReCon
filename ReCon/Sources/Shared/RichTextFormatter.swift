import Foundation
import SwiftUI

struct RichTextFormatter {
    private struct Style {
        var bold = false
        var color: Color?
        var size: CGFloat?
    }

    static func toAttributedString(_ input: String) -> AttributedString {
        let pattern = #"<[^>]+>|[^<]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AttributedString(input)
        }

        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        var stack: [Style] = [Style()]
        var out = AttributedString()

        for match in matches {
            guard let range = Range(match.range, in: input) else { continue }
            let token = String(input[range])
            let lower = token.lowercased()

            if token.hasPrefix("<"), token.hasSuffix(">") {
                switch lower {
                case "<br>", "<br/>", "<br />":
                    out.append(AttributedString("\n"))
                case "<b>":
                    var next = stack.last ?? Style()
                    next.bold = true
                    stack.append(next)
                case "</b>", "</color>", "</size>":
                    if stack.count > 1 { _ = stack.popLast() }
                default:
                    if lower.hasPrefix("<color") {
                        if let value = extractTagValue(token), let color = parseColor(value) {
                            var next = stack.last ?? Style()
                            next.color = color
                            stack.append(next)
                        }
                    } else if lower.hasPrefix("<size"), let value = extractTagValue(token), let size = parseSizeValue(value) {
                        var next = stack.last ?? Style()
                        next.size = CGFloat(size)
                        stack.append(next)
                    }
                }
                continue
            }

            var piece = AttributedString(token)
            let active = stack.last ?? Style()
            let clampedSize = max(11, min(24, active.size ?? 17))
            var container = AttributeContainer()
            container.font = .system(size: clampedSize, weight: active.bold ? .bold : .regular)
            if let color = active.color {
                container.foregroundColor = color
            }
            piece.mergeAttributes(container, mergePolicy: .keepNew)
            out.append(piece)
        }

        return out
    }
}

private extension RichTextFormatter {
    static func extractTagValue(_ tag: String) -> String? {
        let trimmed = tag.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        if let eqIndex = trimmed.firstIndex(of: "=") {
            let value = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count > 1 {
            return String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    static func parseColor(_ raw: String) -> Color? {
        let named = raw.lowercased()
        switch named {
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "white": return .white
        case "black": return .black
        case "gray", "grey": return .gray
        default: break
        }

        let hex = raw.replacingOccurrences(of: "#", with: "")
        let chars = Array(hex)
        guard chars.count == 6 || chars.count == 8 else { return nil }

        func byte(_ start: Int) -> Double {
            let part = String(chars[start..<(start + 2)])
            return Double(Int(part, radix: 16) ?? 0) / 255.0
        }

        let r = byte(0)
        let g = byte(2)
        let b = byte(4)
        let a = chars.count == 8 ? byte(6) : 1.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    static func parseSizeValue(_ raw: String) -> Double? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("%"), let pct = Double(cleaned.dropLast()) {
            let base = 17.0
            return base * (pct / 100.0)
        }
        return Double(cleaned)
    }
}
