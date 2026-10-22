import Foundation

/// Petits outils HTML sans dépendance (regex), utilisables hors du main thread.
enum HTMLUtils {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static let scriptStyle = regex("<(script|style|noscript)\\b[^>]*>.*?</\\1\\s*>")
    private static let blockBreaks = regex("<(br|/p|/div|/li|/h[1-6]|/blockquote)\\b[^>]*>")
    private static let tags = regex("<[^>]+>")
    private static let whitespace = regex("\\s+")
    private static let imgTag = regex("<img\\b[^>]*>")
    private static let metaTag = regex("<meta\\b[^>]*>")
    private static let linkTag = regex("<link\\b[^>]*>")
    private static let entity = regex("&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);")

    // MARK: - Texte brut

    static func plainText(_ html: String) -> String {
        guard !html.isEmpty else { return "" }
        var s = replace(scriptStyle, in: html, with: " ")
        s = replace(blockBreaks, in: s, with: " ")
        s = replace(tags, in: s, with: "")
        s = decodeEntities(s)
        s = replace(whitespace, in: s, with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in entity.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let body = ns.substring(with: m.range(at: 1))
            out += decodeEntity(body) ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static func decodeEntity(_ body: String) -> String? {
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            return UInt32(body.dropFirst(2), radix: 16).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
        }
        if body.hasPrefix("#") {
            return UInt32(body.dropFirst()).flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
        }
        return namedEntities[body]
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "laquo": "«", "raquo": "»", "bull": "•", "middot": "·", "copy": "©", "reg": "®", "trade": "™",
        "euro": "€", "deg": "°", "times": "×", "shy": "", "thinsp": "\u{2009}", "zwnj": "",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "agrave": "à", "acirc": "â", "auml": "ä",
        "ccedil": "ç", "icirc": "î", "iuml": "ï", "ocirc": "ô", "ouml": "ö", "ugrave": "ù", "ucirc": "û",
        "uuml": "ü", "oelig": "œ", "aelig": "æ", "ntilde": "ñ", "szlig": "ß",
        "Eacute": "É", "Egrave": "È", "Ecirc": "Ê", "Agrave": "À", "Acirc": "Â", "Ccedil": "Ç",
        "Ocirc": "Ô", "Ugrave": "Ù", "OElig": "Œ", "Icirc": "Î",
    ]

    // MARK: - Images & liens

    /// Première image "réelle" d'un fragment HTML (ignore les pixels de tracking).
    static func firstImage(in html: String) -> String? {
        for tag in matches(imgTag, in: html) {
            if attribute("width", in: tag) == "1" || attribute("height", in: tag) == "1" { continue }
            guard let src = attribute("src", in: tag) ?? attribute("data-src", in: tag) else { continue }
            let lower = src.lowercased()
            if lower.hasPrefix("data:") || lower.contains("feedburner") || lower.contains("pixel")
                || lower.contains("/1x1") || lower.contains("tracking") || lower.contains("gravatar") { continue }
            return src
        }
        return nil
    }

    /// og:image (ou twitter:image) d'une page.
    static func ogImage(in html: String) -> String? {
        var found: [String: String] = [:]
        for tag in matches(metaTag, in: html) {
            guard let prop = (attribute("property", in: tag) ?? attribute("name", in: tag))?.lowercased(),
                  let content = attribute("content", in: tag), !content.isEmpty else { continue }
            if found[prop] == nil { found[prop] = content }
        }
        return found["og:image"] ?? found["og:image:url"] ?? found["twitter:image"] ?? found["twitter:image:src"]
    }

    /// Liens <link rel="alternate" type="application/rss+xml|atom+xml"> d'une page.
    static func feedLinks(in html: String, base: URL) -> [URL] {
        matches(linkTag, in: html).compactMap { tag in
            guard let rel = attribute("rel", in: tag)?.lowercased(), rel.contains("alternate"),
                  let type = attribute("type", in: tag)?.lowercased(),
                  type.contains("rss") || type.contains("atom"),
                  let href = attribute("href", in: tag),
                  let resolved = resolve(href, base: base) else { return nil }
            return URL(string: resolved)
        }
    }

    static func resolve(_ raw: String, base: URL?) -> String? {
        var s = decodeEntities(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("//") { s = "https:" + s }
        s = s.replacingOccurrences(of: " ", with: "%20")
        return URL(string: s, relativeTo: base)?.absoluteURL.absoluteString
    }

    // MARK: - Helpers regex

    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\s" + NSRegularExpression.escapedPattern(for: name)
            + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
        let r = regex(pattern)
        let ns = tag as NSString
        guard let m = r.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for i in 1...3 where m.range(at: i).location != NSNotFound {
            return ns.substring(with: m.range(at: i))
        }
        return nil
    }

    private static func matches(_ r: NSRegularExpression, in s: String) -> [String] {
        let ns = s as NSString
        return r.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func replace(_ r: NSRegularExpression, in s: String, with template: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }
}
