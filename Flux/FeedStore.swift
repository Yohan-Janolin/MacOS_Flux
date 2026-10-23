import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class FeedStore {
    private(set) var isRefreshing = false
    /// Pas de connexion lors de la dernière actualisation
    private(set) var isOffline = false
    /// Progression de la préparation hors ligne (nil = rien en cours)
    private(set) var offlineStatus: String?
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
        for path in ["/feed", "/rss", "/feed.xml", "/rss.xml", "/atom.xml", "/index.xml", "/feed.json"] {
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

        // Hors ligne si toutes les requêtes ont échoué faute de connexion
        let failures = results.values.compactMap { r -> Error? in
            if case .failure(let e) = r { return e } else { return nil }
        }
        isOffline = !results.isEmpty && failures.count == results.count && failures.allSatisfy(Self.isOfflineError)

        var added: [Article] = []
        for feed in feeds {
            guard let result = results[feed.url] else { continue }
            added += apply(result, to: feed)
        }
        applyAutoMarkRead(save: false)
        prune()
        if context.hasChanges { try? context.save() }
        guard !isOffline else { return }
        await fillMissingImages(added)
        // En tâche séparée : l'actualisation (et son indicateur) se termine sans attendre
        if Prefs.offline { Task { await prepareOffline() } }
        if Prefs.archive { Task { await archiveFavorites() } }

        // Le cache d'images se remplit aussi en lisant normalement : on le garde sous la limite
        let limit = Prefs.imageCacheLimitBytes
        Task.detached(priority: .background) { ImageCache.trim(toBytes: limit) }
    }

    nonisolated static func isOfflineError(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                .internationalRoamingOff, .timedOut].contains(code)
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
            // Pas de connexion : ce n'est pas la faute du flux, on ne le signale pas en erreur
            if Self.isOfflineError(error) { return [] }
            let message = error.localizedDescription
            if feed.lastError != message { feed.lastError = message }
            return []
        }
    }

    /// Insère les nouveaux articles d'un flux, sans toucher à ceux déjà connus.
    private func ingest(_ parsed: ParsedFeed, into feed: Feed) -> [Article] {
        if feed.siteURL == nil, let site = parsed.siteURL { feed.siteURL = site }
        // Le nom d'origine suit le flux ; un nom personnalisé (customTitle) reste prioritaire à l'affichage
        if let fresh = parsed.title.map(HTMLUtils.plainText), !fresh.isEmpty, fresh != feed.title {
            feed.title = fresh
        }
        var known = Set(feed.articles.map(\.key))
        let base = URL(string: feed.siteURL ?? feed.url)
        // On n'importe pas les articles plus vieux que la durée de conservation
        let cutoff = Prefs.retentionCutoff
        let autoReadCutoff = Prefs.autoMarkReadCutoff
        let filters = compiledFilters()
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
            applyFilters(filters, to: article)
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
        case .history:
            predicate = #Predicate { !$0.isRead && $0.openedAt != nil }
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
        let changed = articles.filter { $0.isStarred != starred }
        for article in changed { article.isStarred = starred }
        try? context.save()
        guard !changed.isEmpty else { return }
        if starred {
            Task { await archiveFavorites(changed) }
        } else {
            unarchive(changed)
        }
    }

    func articles(withKeys keys: Set<String>) -> [Article] {
        let list = Array(keys)
        return (try? context.fetch(FetchDescriptor<Article>(predicate: #Predicate { list.contains($0.key) }))) ?? []
    }

    /// Renomme un flux ; un nom vide rétablit le nom d'origine
    func rename(_ feed: Feed, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        feed.customTitle = (trimmed.isEmpty || trimmed == feed.title) ? nil : trimmed
        try? context.save()
    }

    func delete(_ feed: Feed) {
        context.delete(feed)
        try? context.save()
    }

    // MARK: - Filtres

    func compiledFilters() -> [CompiledFilter] {
        ((try? context.fetch(FetchDescriptor<FilterRule>())) ?? []).map(CompiledFilter.init)
    }

    /// Applique la première règle qui correspond (les favoris ne sont jamais filtrés)
    private func applyFilters(_ filters: [CompiledFilter], to article: Article) {
        guard !article.isStarred, article.filteredBy == nil,
              let rule = filters.first(where: { $0.matches(title: article.title, feedURL: article.feedURL) }) else { return }
        article.filteredBy = rule.uid
        switch rule.action {
        case .hide: article.isHidden = true
        case .markRead: article.isRead = true
        }
    }

    /// Repasse toutes les règles sur les articles qui ne sont filtrés par aucune
    func applyFiltersToExisting() {
        let filters = compiledFilters()
        guard !filters.isEmpty else { return }
        let predicate = #Predicate<Article> { $0.filteredBy == nil && !$0.isStarred }
        for article in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            applyFilters(filters, to: article)
        }
        try? context.save()
    }

    /// Libère les articles filtrés par une règle (ils réapparaissent ; ceux déjà marqués comme lus le restent)
    private func releaseArticles(of uid: String) {
        let predicate = #Predicate<Article> { $0.filteredBy == uid }
        for article in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            article.filteredBy = nil
            article.isHidden = false
        }
    }

    func addFilter(keyword: String, wholeWord: Bool, action: FilterAction, feedURL: String?) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(FilterRule(keyword: trimmed, wholeWord: wholeWord, action: action, feedURL: feedURL))
        try? context.save()
        applyFiltersToExisting()
    }

    func updateFilter(_ rule: FilterRule, keyword: String, wholeWord: Bool, action: FilterAction, feedURL: String?) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        releaseArticles(of: rule.uid)
        rule.keyword = trimmed
        rule.wholeWord = wholeWord
        rule.action = action.rawValue
        rule.feedURL = feedURL
        try? context.save()
        applyFiltersToExisting()
    }

    func deleteFilter(_ rule: FilterRule) {
        releaseArticles(of: rule.uid)
        context.delete(rule)
        try? context.save()
        applyFiltersToExisting()   // une autre règle peut encore s'appliquer
    }

    /// Aperçu d'une règle pas encore enregistrée : nombre d'articles (hors favoris) dont le titre correspond
    func previewMatchCount(_ filter: CompiledFilter) -> Int {
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { !$0.isStarred })
        descriptor.propertiesToFetch = [\.title, \.feedURL]
        let articles = (try? context.fetch(descriptor)) ?? []
        return articles.reduce(0) { $0 + (filter.matches(title: $1.title, feedURL: $1.feedURL) ? 1 : 0) }
    }

    /// Nombre d'articles actuellement touchés par une règle
    func matchCount(of rule: FilterRule) -> Int {
        let uid = rule.uid
        return (try? context.fetchCount(FetchDescriptor<Article>(predicate: #Predicate { $0.filteredBy == uid }))) ?? 0
    }

    // MARK: - Archive des favoris

    /// Progression de l'archivage des favoris (nil = rien en cours)
    private(set) var archiveStatus: String?

    /// Range dans l'archive permanente l'article complet et les images des favoris
    /// (par défaut : tous les favoris pas encore archivés)
    func archiveFavorites(_ articles: [Article]? = nil) async {
        guard Prefs.archive, !isOffline, archiveStatus == nil else { return }
        let targets = (articles ?? ((try? context.fetch(FetchDescriptor<Article>(
            predicate: #Predicate { $0.isStarred && !$0.isArchived }))) ?? []))
            .filter { $0.isStarred && !$0.isArchived }
        guard !targets.isEmpty else { return }
        archiveStatus = String(localized: "Archivage…")
        defer { archiveStatus = nil }

        for (index, article) in targets.enumerated() {
            guard !article.isDeleted, article.isStarred, Prefs.archive, !isOffline else { continue }
            archiveStatus = String(localized: "Favoris : \(index + 1) sur \(targets.count)")

            // 1. Article complet, si le flux ne donne qu'un extrait
            if article.fullHTML == nil, HTMLUtils.looksLikeExcerpt(article.contentHTML),
               let link = article.link, let url = URL(string: link) {
                do {
                    if let content = try await FullTextLoader.load(url) {
                        article.fullHTML = content
                        article.updateSearchText()
                    }
                } catch {
                    if let e = error as? URLError, Self.isOfflineError(e) { return }   // on réessaiera plus tard
                }
            }

            // 2. Images (miniature + images du texte, 50 max)
            let base = article.link.flatMap { URL(string: $0) }
            var urls = Array(HTMLUtils.imageURLs(in: article.fullHTML ?? article.contentHTML ?? "", base: base).prefix(50))
            if let thumb = article.imageURL.flatMap({ URL(string: $0) }) { urls.insert(thumb, at: 0) }
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask { _ = await ImageCache.archive(url) }
                }
            }
            article.isArchived = true
            try? context.save()
        }
    }

    /// Favoris retirés : leurs images quittent l'archive (retour dans le cache normal)
    private func unarchive(_ articles: [Article]) {
        for article in articles { article.isArchived = false }
        try? context.save()
        let favorites = (try? context.fetch(FetchDescriptor<Article>(predicate: #Predicate { $0.isStarred }))) ?? []
        var keep = Set<URL>()
        for article in favorites {
            let base = article.link.flatMap { URL(string: $0) }
            keep.formUnion(HTMLUtils.imageURLs(in: article.fullHTML ?? article.contentHTML ?? "", base: base).prefix(50))
            if let thumb = article.imageURL.flatMap({ URL(string: $0) }) { keep.insert(thumb) }
        }
        Task.detached(priority: .utility) { ImageCache.pruneArchive(keeping: keep) }
    }

    func pendingArchiveCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<Article>(predicate: #Predicate { $0.isStarred && !$0.isArchived }))) ?? 0
    }

    // MARK: - Hors ligne

    /// Prépare la lecture hors ligne des articles non lus et des favoris :
    /// récupère l'article complet quand le flux ne donne qu'un extrait,
    /// puis télécharge toutes leurs images dans le cache disque.
    func prepareOffline() async {
        guard offlineStatus == nil else { return }
        offlineStatus = String(localized: "Préparation…")
        defer { offlineStatus = nil }

        var descriptor = FetchDescriptor<Article>(
            predicate: #Predicate { (!$0.isRead && !$0.isHidden) || $0.isStarred },
            sortBy: [SortDescriptor(\.published, order: .reverse)]
        )
        descriptor.fetchLimit = 400
        let articles = (try? context.fetch(descriptor)) ?? []

        // 1. Articles complets (téléchargement 4 par 4, extraction une par une)
        let needFull = articles.filter {
            $0.fullHTML == nil && $0.link != nil && HTMLUtils.looksLikeExcerpt($0.contentHTML)
        }
        var done = 0
        for start in stride(from: 0, to: needFull.count, by: 4) {
            guard Prefs.offline, !isOffline else { return }
            let chunk = Array(needFull[start..<min(start + 4, needFull.count)])
            let pages = await withTaskGroup(of: (String, String, URL)?.self) { group in
                for article in chunk {
                    guard let link = article.link, let url = URL(string: link) else { continue }
                    let key = article.key
                    group.addTask {
                        guard let r = try? await Net.get(url) else { return nil }
                        return (key, Net.decodeHTML(r.0), r.1)
                    }
                }
                var out: [(String, String, URL)] = []
                for await page in group { if let page { out.append(page) } }
                return out
            }
            for (key, html, finalURL) in pages {
                guard let article = chunk.first(where: { $0.key == key }), !article.isDeleted,
                      article.fullHTML == nil,
                      let content = (try? await ArticleExtractor.shared.extract(html: html, url: finalURL))?.content
                else { continue }
                article.fullHTML = content
                article.updateSearchText()
                if article.imageURL == nil, let first = HTMLUtils.imageURLs(in: content, base: finalURL).first {
                    article.imageURL = first.absoluteString
                }
            }
            done += chunk.count
            offlineStatus = String(localized: "Articles : \(done) sur \(needFull.count)")
            if context.hasChanges { try? context.save() }
        }

        // 2. Images (miniature + images du texte, 25 max par article)
        var imageURLs: [URL] = []
        var seen = Set<URL>()
        for article in articles where !article.isDeleted {
            let base = article.link.flatMap { URL(string: $0) }
            var urls = HTMLUtils.imageURLs(in: article.fullHTML ?? article.contentHTML ?? "", base: base).prefix(25).map { $0 }
            if let thumb = article.imageURL.flatMap({ URL(string: $0) }) { urls.insert(thumb, at: 0) }
            for url in urls where seen.insert(url).inserted { imageURLs.append(url) }
        }
        let missing = imageURLs.filter { !ImageCache.isCached($0) }
        for start in stride(from: 0, to: missing.count, by: 24) {
            guard Prefs.offline, !isOffline else { return }
            offlineStatus = String(localized: "Images : \(start) sur \(missing.count)")
            await ImageCache.prefetch(Array(missing[start..<min(start + 24, missing.count)]))
        }
        ImageCache.trim(toBytes: Prefs.imageCacheLimitBytes)
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

    /// Nombre d'articles non lus (hors favoris) publiés il y a plus de `days` jours
    func unreadCount(olderThanDays days: Int) -> Int {
        let cutoff = Date.now.addingTimeInterval(-Double(max(days, 1)) * 86_400)
        let predicate = #Predicate<Article> { !$0.isRead && !$0.isHidden && !$0.isStarred && $0.published < cutoff }
        return (try? context.fetchCount(FetchDescriptor(predicate: predicate))) ?? 0
    }

    private func prune() {
        let cutoff = Prefs.retentionCutoff
        let predicate = #Predicate<Article> { $0.isRead && !$0.isStarred && $0.published < cutoff }
        for article in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            context.delete(article)
        }
    }
}
