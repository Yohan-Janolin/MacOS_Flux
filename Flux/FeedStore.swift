import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class FeedStore {
    private(set) var isRefreshing = false
    @ObservationIgnored let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Ajout

    @discardableResult
    func addFeed(urlString: String, folder: Folder? = nil) async throws -> Feed {
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
        feed.folder = folder
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

        backfillSearchText()

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
        applyAutoMarkRead(save: false)
        prune()
        if context.hasChanges { try? context.save() }
        await fillMissingImages(added)
    }

    func refresh(_ feed: Feed) async {
        let result = await Self.fetchFeed(feed.url)
        let added = apply(result, to: feed)
        if context.hasChanges { try? context.save() }
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
            // On n'écrit que ce qui change, pour ne pas réveiller les vues inutilement
            if feed.lastError != nil { feed.lastError = nil }
            feed.lastRefreshed = .now
            return ingest(parsed, into: feed)
        case .failure(let error):
            let message = error.localizedDescription
            if feed.lastError != message { feed.lastError = message }
            return []
        }
    }

    /// Insère les nouveaux articles d'un flux, sans toucher à ceux déjà connus.
    private func ingest(_ parsed: ParsedFeed, into feed: Feed) -> [Article] {
        if feed.siteURL == nil, let site = parsed.siteURL { feed.siteURL = site }
        var known = Set(feed.articles.map(\.key))
        let base = URL(string: feed.siteURL ?? feed.url)
        // On n'importe pas les articles plus vieux que la durée de conservation
        let cutoff = Prefs.retentionCutoff
        let autoReadCutoff = Prefs.autoMarkReadCutoff
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
                title: title.isEmpty ? String(localized: "(Sans titre)") : title,
                link: link,
                summary: summary,
                contentHTML: html,
                imageURL: image,
                author: item.author.map(HTMLUtils.plainText),
                published: item.published ?? .now
            )
            if let autoReadCutoff, article.published < autoReadCutoff, !article.isStarred {
                article.isRead = true
            }
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

    /// Calcule le texte de recherche des articles enregistrés avant la recherche plein texte
    /// (par lots, pour ne pas bloquer l'interface)
    private func backfillSearchText() {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.searchText == "" })
        descriptor.fetchLimit = 500
        for article in (try? context.fetch(descriptor)) ?? [] {
            article.updateSearchText()
        }
    }

    // MARK: - Gestion

    func markAllRead(_ filter: SidebarSelection) {
        let predicate: Predicate<Article>
        switch filter {
        case .feed(let url):
            predicate = #Predicate { !$0.isRead && $0.feedURL == url }
        case .starred:
            predicate = #Predicate { !$0.isRead && $0.isStarred }
        case .folder(let uid):
            let urls = feedURLs(inFolder: uid)
            predicate = #Predicate { !$0.isRead && urls.contains($0.feedURL) }
        case .all, .unread:
            predicate = #Predicate { !$0.isRead }
        }
        for article in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            article.isRead = true
        }
        try? context.save()
    }

    func setRead(_ read: Bool, _ articles: [Article]) {
        for article in articles where article.isRead != read { article.isRead = read }
        try? context.save()
    }

    func setStarred(_ starred: Bool, _ articles: [Article]) {
        for article in articles where article.isStarred != starred { article.isStarred = starred }
        try? context.save()
    }

    func articles(withKeys keys: Set<String>) -> [Article] {
        let list = Array(keys)
        return (try? context.fetch(FetchDescriptor<Article>(predicate: #Predicate { list.contains($0.key) }))) ?? []
    }

    func delete(_ feed: Feed) {
        context.delete(feed)
        try? context.save()
    }

    // MARK: - OPML

    struct ImportResult {
        var added = 0
        var skipped = 0
    }

    /// Importe les abonnements d'un fichier OPML : crée les dossiers manquants,
    /// ignore les flux déjà présents, puis actualise pour récupérer les articles.
    func importOPML(_ data: Data) async -> ImportResult {
        var result = ImportResult()
        let entries = OPML.parse(data)
        guard !entries.isEmpty else { return result }

        let feeds = (try? context.fetch(FetchDescriptor<Feed>())) ?? []
        var knownURLs = Set(feeds.map(\.url))
        var foldersByName: [String: Folder] = [:]
        for folder in (try? context.fetch(FetchDescriptor<Folder>())) ?? [] {
            foldersByName[folder.name.lowercased()] = folder
        }

        for entry in entries {
            guard let url = URL(string: entry.xmlURL), url.host() != nil else {
                result.skipped += 1
                continue
            }
            let key = url.absoluteString
            guard !knownURLs.contains(key) else {
                result.skipped += 1
                continue
            }
            knownURLs.insert(key)

            var folder: Folder?
            if let name = entry.folder {
                if let existing = foldersByName[name.lowercased()] {
                    folder = existing
                } else {
                    let created = Folder(name: name)
                    context.insert(created)
                    foldersByName[name.lowercased()] = created
                    folder = created
                }
            }

            let title = entry.title.isEmpty ? (url.host() ?? key) : entry.title
            let feed = Feed(url: key, title: title, siteURL: entry.htmlURL)
            context.insert(feed)
            feed.folder = folder
            result.added += 1
        }

        try? context.save()
        if result.added > 0 {
            // Si une actualisation est déjà en cours, on attend sa fin pour inclure les nouveaux flux
            while isRefreshing { try? await Task.sleep(for: .milliseconds(300)) }
            await refreshAll()
        }
        return result
    }

    func exportOPML() -> String {
        OPML.export(feeds: (try? context.fetch(FetchDescriptor<Feed>())) ?? [])
    }

    // MARK: - Dossiers

    func folder(uid: String) -> Folder? {
        var descriptor = FetchDescriptor<Folder>(predicate: #Predicate { $0.uid == uid })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func feedURLs(inFolder uid: String) -> [String] {
        folder(uid: uid)?.feeds.map(\.url) ?? []
    }

    func createFolder(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(Folder(name: trimmed))
        try? context.save()
    }

    func update(_ folder: Folder, name: String, symbol: String?, colorName: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { folder.name = trimmed }
        folder.symbol = (symbol == "folder") ? nil : symbol
        folder.colorName = colorName
        try? context.save()
    }

    /// Les flux du dossier reviennent à la racine.
    func delete(_ folder: Folder) {
        for feed in folder.feeds { feed.folder = nil }
        context.delete(folder)
        try? context.save()
    }

    func move(_ feed: Feed, to folder: Folder?) {
        feed.folder = folder
        try? context.save()
    }

    /// Utilisé par le glisser-déposer (on transporte l'URL du flux).
    func move(feedURLs urls: [String], to folder: Folder?) {
        for url in urls {
            let descriptor = FetchDescriptor<Feed>(predicate: #Predicate { $0.url == url })
            if let feed = try? context.fetch(descriptor).first {
                feed.folder = folder
            }
        }
        try? context.save()
    }

    /// Réglage « marquer automatiquement comme lus les articles de plus de X jours »
    /// (les favoris ne sont pas concernés)
    func applyAutoMarkRead(save: Bool = true) {
        guard let cutoff = Prefs.autoMarkReadCutoff else { return }
        let predicate = #Predicate<Article> { !$0.isRead && !$0.isStarred && $0.published < cutoff }
        for article in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            article.isRead = true
        }
        if save, context.hasChanges { try? context.save() }
    }

    private func prune() {
        let cutoff = Prefs.retentionCutoff
        let predicate = #Predicate<Article> { $0.isRead && !$0.isStarred && $0.published < cutoff }
        for article in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            context.delete(article)
        }
    }
}
