import Foundation
import SwiftData

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

extension Locale {
    static let fr = Locale(identifier: "fr_FR")
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
