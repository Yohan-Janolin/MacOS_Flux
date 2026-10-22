import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class FeedStore {
    private(set) var isRefreshing = false
    @ObservationIgnored let context: ModelContext

    /// Les articles lus (et non favoris) plus vieux que ça sont supprimés,
    /// et on n'importe pas les articles plus anciens.
    private let retention: TimeInterval = 60 * 24 * 3600

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Ajout

    @discardableResult
    func addFeed(urlString: String) async throws -> Feed {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), url.host() != nil else { throw FeedError.invalidURL }

        let (feedURL, parsed) = try await Self.discover(url)
        let key = feedURL.absoluteString

        let existing = try context.fetch(FetchDescriptor<Feed>(predicate: #Predicate { $0.url == key }))
        guard existing.isEmpty else { throw FeedError.alreadyExists }

        let title = parsed.title.map(HTMLUtils.plainText).flatMap { $0.isEmpty ? nil : $0 } ?? url.host() ?? key
        let feed = Feed(url: key, title: title, siteURL: parsed.siteURL)
        context.insert(feed)
        let added = ingest(parsed, into: feed)
        feed.lastRefreshed = .now
        try? context.save()

        Task { await fillMissingImages(added) }
        return feed
    }

    /// Accepte l'URL d'un flux, ou celle d'un site (détection automatique).
    nonisolated static func discover(_ url: URL) async throws -> (URL, ParsedFeed) {
        let (data, finalURL) = try await Net.get(url)
        if let parsed = FeedParser.parse(data) { return (finalURL, parsed) }

        let html = Net.decodeHTML(data)
        for candidate in HTMLUtils.feedLinks(in: html, base: finalURL) {
            if let r = try? await Net.get(candidate), let parsed = FeedParser.parse(r.0) { return (r.1, parsed) }
        }
        for path in ["/feed", "/rss", "/feed.xml", "/rss.xml", "/atom.xml", "/index.xml"] {
            guard let candidate = URL(string: path, relativeTo: finalURL)?.absoluteURL else { continue }
            if let r = try? await Net.get(candidate), let parsed = FeedParser.parse(r.0) { return (r.1, parsed) }
        }
        throw FeedError.notAFeed
    }

    // MARK: - Actualisation

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        let urls = feeds.map(\.url)

        let results = await withTaskGroup(of: (String, Result<ParsedFeed, Error>).self) { group in
            for u in urls {
                group.addTask { (u, await Self.fetchFeed(u)) }
            }
            var out: [String: Result<ParsedFeed, Error>] = [:]
            for await (u, r) in group { out[u] = r }
            return out
        }

        var added: [Article] = []
        for feed in feeds {
            guard let result = results[feed.url] else { continue }
            added += apply(result, to: feed)
        }
        prune()
        try? context.save()
        await fillMissingImages(added)
    }

    func refresh(_ feed: Feed) async {
        let result = await Self.fetchFeed(feed.url)
        let added = apply(result, to: feed)
        try? context.save()
        await fillMissingImages(added)
    }

    nonisolated static func fetchFeed(_ urlString: String) async -> Result<ParsedFeed, Error> {
        guard let url = URL(string: urlString) else { return .failure(FeedError.invalidURL) }
        do {
            let (data, _) = try await Net.get(url)
            guard let parsed = FeedParser.parse(data) else { return .failure(FeedError.notAFeed) }
            return .success(parsed)
        } catch {
            return .failure(error)
        }
    }

    private func apply(_ result: Result<ParsedFeed, Error>, to feed: Feed) -> [Article] {
        guard !feed.isDeleted, feed.modelContext != nil else { return [] }
        switch result {
        case .success(let parsed):
            feed.lastError = nil
            feed.lastRefreshed = .now
            return ingest(parsed, into: feed)
        case .failure(let error):
            feed.lastError = error.localizedDescription
            return []
        }
    }

    /// Insère les nouveaux articles d'un flux, sans toucher à ceux déjà connus.
    private func ingest(_ parsed: ParsedFeed, into feed: Feed) -> [Article] {
        if feed.siteURL == nil { feed.siteURL = parsed.siteURL }
        var known = Set(feed.articles.map(\.key))
        let base = URL(string: feed.siteURL ?? feed.url)
        let cutoff = Date.now.addingTimeInterval(-retention)
        var added: [Article] = []

        for item in parsed.items.prefix(200) {
            if let date = item.published, date < cutoff { continue }

            let link = item.link.flatMap { HTMLUtils.resolve($0, base: base) }
            guard let ident = item.guid ?? link ?? item.title else { continue }
            let key = feed.url + "|" + ident
            guard !known.contains(key) else { continue }
            known.insert(key)

            let html = item.contentHTML ?? item.summaryHTML
            let title = HTMLUtils.plainText(item.title ?? "")
            let summary = String(HTMLUtils.plainText(item.summaryHTML ?? item.contentHTML ?? "").prefix(280))
            let imageBase = link.flatMap { URL(string: $0) } ?? base
            let image = (item.imageURL ?? html.flatMap(HTMLUtils.firstImage))
                .flatMap { HTMLUtils.resolve($0, base: imageBase) }

            let article = Article(
                key: key,
                feedURL: feed.url,
                title: title.isEmpty ? "(Sans titre)" : title,
                link: link,
                summary: summary,
                contentHTML: html,
                imageURL: image,
                author: item.author.map(HTMLUtils.plainText),
                published: item.published ?? .now
            )
            context.insert(article)
            article.feed = feed
            added.append(article)
        }
        return added
    }

    /// Pour les articles sans miniature : récupère l'og:image de la page.
    private func fillMissingImages(_ articles: [Article]) async {
        let targets = articles
            .filter { $0.imageURL == nil }
            .compactMap { a in a.link.map { (a.key, $0) } }
            .prefix(40)
        guard !targets.isEmpty else { return }

        let list = Array(targets)
        var found: [String: String] = [:]
        for start in stride(from: 0, to: list.count, by: 6) {
            let chunk = list[start..<min(start + 6, list.count)]
            let partial = await withTaskGroup(of: (String, String?).self) { group in
                for (key, link) in chunk {
                    group.addTask { (key, await Self.ogImage(for: link)) }
                }
                var out: [String: String] = [:]
                for await (key, image) in group {
                    if let image { out[key] = image }
                }
                return out
            }
            found.merge(partial) { a, _ in a }
        }

        for article in articles where !article.isDeleted {
            if let image = found[article.key] { article.imageURL = image }
        }
        try? context.save()
    }

    nonisolated static func ogImage(for link: String) async -> String? {
        guard let url = URL(string: link), let r = try? await Net.get(url) else { return nil }
        return HTMLUtils.ogImage(in: Net.decodeHTML(r.0)).flatMap { HTMLUtils.resolve($0, base: r.1) }
    }

    // MARK: - Gestion

    func markAllRead(_ filter: SidebarSelection) {
        let predicate: Predicate<Article>
        switch filter {
        case .feed(let url):
            predicate = #Predicate { !$0.isRead && $0.feedURL == url }
        case .starred:
            predicate = #Predicate { !$0.isRead && $0.isStarred }
        case .all, .unread:
            predicate = #Predicate { !$0.isRead }
        }
        for article in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            article.isRead = true
        }
        try? context.save()
    }

    func delete(_ feed: Feed) {
        context.delete(feed)
        try? context.save()
    }

    private func prune() {
        let cutoff = Date.now.addingTimeInterval(-retention)
        let predicate = #Predicate<Article> { $0.isRead && !$0.isStarred && $0.published < cutoff }
        for article in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            context.delete(article)
        }
    }
}
