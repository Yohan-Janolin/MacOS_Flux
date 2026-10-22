import Foundation
import SwiftData
import SwiftUI

@Model
final class Feed {
    @Attribute(.unique) var url: String
    var title: String
    var siteURL: String?
    var addedAt: Date
    var lastRefreshed: Date?
    var lastError: String?
    var folder: Folder?

    @Relationship(deleteRule: .cascade, inverse: \Article.feed)
    var articles: [Article] = []

    init(url: String, title: String, siteURL: String?) {
        self.url = url
        self.title = title
        self.siteURL = siteURL
        self.addedAt = .now
    }

    var faviconURL: URL? {
        guard let host = URL(string: siteURL ?? url)?.host() else { return nil }
        return URL(string: "https://\(host)/favicon.ico")
    }
}

@Model
final class Folder {
    @Attribute(.unique) var uid: String
    var name: String
    var isExpanded: Bool
    var createdAt: Date
    /// Nom d'un symbole SF Symbols (nil = "folder")
    var symbol: String?
    /// Nom d'une FolderColor (nil = couleur d'accent)
    var colorName: String?

    /// Supprimer un dossier ne supprime pas ses flux : ils reviennent à la racine.
    @Relationship(deleteRule: .nullify, inverse: \Feed.folder)
    var feeds: [Feed] = []

    init(name: String) {
        self.uid = UUID().uuidString
        self.name = name
        self.isExpanded = true
        self.createdAt = .now
    }
}

extension Folder {
    var symbolName: String { symbol ?? "folder" }
    var tint: Color? { colorName.flatMap(FolderColor.init(rawValue:))?.color }
}

enum FolderColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: String(localized: "Rouge")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Jaune")
        case .green: String(localized: "Vert")
        case .mint: String(localized: "Menthe")
        case .teal: String(localized: "Bleu canard")
        case .cyan: String(localized: "Cyan")
        case .blue: String(localized: "Bleu")
        case .indigo: String(localized: "Indigo")
        case .purple: String(localized: "Violet")
        case .pink: String(localized: "Rose")
        case .brown: String(localized: "Marron")
        case .gray: String(localized: "Gris")
        }
    }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

extension Locale {
    /// Langue de l'interface (celle que macOS a choisie pour l'app), pour formater les dates
    static var app: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}

@Model
final class Article {
    /// feedURL + "|" + guid (ou lien, ou titre)
    @Attribute(.unique) var key: String
    var feedURL: String
    var title: String
    var link: String?
    /// Extrait en texte brut, pour la liste
    var summary: String
    /// HTML fourni par le flux (content:encoded, description…)
    var contentHTML: String?
    /// HTML extrait de la page web par Readability (mis en cache)
    var fullHTML: String?
    var imageURL: String?
    var author: String?
    var published: Date
    var isRead: Bool
    var isStarred: Bool
    var feed: Feed?

    init(key: String, feedURL: String, title: String, link: String?, summary: String,
         contentHTML: String?, imageURL: String?, author: String?, published: Date) {
        self.key = key
        self.feedURL = feedURL
        self.title = title
        self.link = link
        self.summary = summary
        self.contentHTML = contentHTML
        self.fullHTML = nil
        self.imageURL = imageURL
        self.author = author
        self.published = published
        self.isRead = false
        self.isStarred = false
    }
}
