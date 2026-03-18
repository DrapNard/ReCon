import Foundation
import SwiftUI

struct RichTextFormatter {
    static func toAttributedString(_ input: String) -> AttributedString {
        var stripped = input.replacingOccurrences(of: "<br>", with: "\n")
        stripped = stripped.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return AttributedString(stripped)
    }
}
