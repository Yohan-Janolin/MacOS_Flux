import Foundation

/// Règles d'exclusion prêtes à être testées (mot-clé normalisé, expression compilée)
struct CompiledFilter {
    let uid: String
    let feedURL: String?
    let action: FilterAction
    private let needle: String
    private let regex: NSRegularExpression?

    init(_ rule: FilterRule) {
        self.init(uid: rule.uid, keyword: rule.keyword, wholeWord: rule.wholeWord,
                  action: rule.filterAction, feedURL: rule.feedURL)
    }

    init(uid: String = "", keyword: String, wholeWord: Bool, action: FilterAction, feedURL: String?) {
        self.uid = uid
        self.feedURL = feedURL
        self.action = action
        needle = CompiledFilter.fold(keyword.trimmingCharacters(in: .whitespacesAndNewlines))
        if wholeWord, !needle.isEmpty {
            // Mot entier : pas de lettre ni de chiffre juste avant ou juste après
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: needle) + "(?![\\p{L}\\p{N}])"
            regex = try? NSRegularExpression(pattern: pattern)
        } else {
            regex = nil
        }
    }

    /// Minuscules et sans accents : « Élection » = « election »
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    func matches(title: String, feedURL articleFeed: String) -> Bool {
        guard !needle.isEmpty else { return false }
        if let feedURL, feedURL != articleFeed { return false }
        let folded = CompiledFilter.fold(title)
        if let regex {
            return regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)) != nil
        }
        return folded.contains(needle)
    }
}
