import Foundation

enum MarkdownDetector {
    /// Returns true if the text appears to contain markdown formatting.
    /// Checks the first 30 lines for at least 2 distinct markdown patterns.
    static func looksLikeMarkdown(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).prefix(30)
        var patternHits: Set<String> = []

        for line in lines {
            if line.range(of: "^#{1,6}\\s", options: .regularExpression) != nil {
                patternHits.insert("header")
            }
            if line.range(of: "^[\\-\\*\\+]\\s", options: .regularExpression) != nil {
                patternHits.insert("unorderedList")
            }
            if line.range(of: "^\\d+\\.\\s", options: .regularExpression) != nil {
                patternHits.insert("orderedList")
            }
            if line.range(of: "\\[.+\\]\\(.+\\)", options: .regularExpression) != nil {
                patternHits.insert("link")
            }
            if line.contains("```") {
                patternHits.insert("codeFence")
            }
            if line.range(of: "\\*\\*.+\\*\\*", options: .regularExpression) != nil {
                patternHits.insert("bold")
            }
            if line.range(of: "(?<![*])\\*[^*]+\\*(?![*])", options: .regularExpression) != nil {
                patternHits.insert("italic")
            }
            if patternHits.count >= 2 { return true }
        }

        return patternHits.count >= 2
    }
}
