import AppKit
import SwiftData
import SwiftUI

struct ArticleListView: View {
    @Query private var articles: [Article]
    /// Clés des articles sélectionnés (sélection multiple)
    @Binding var selection: Set<String>
    private let filter: SidebarSelection

    private let isSearching: Bool

    /// Point de départ d'une sélection étendue (⇧-clic, ⇧↑/↓)
    @State private var anchor: String?
    /// Dernier article atteint au clavier ou à la souris
    @State private var cursor: String?

    /// `folderFeedURLs` : adresses des flux du dossier quand `filter` est `.folder`
    /// `searchText` : recherche dans le titre et le texte complet (vide = pas de recherche)
    init(filter: SidebarSelection, selection: Binding<Set<String>>, folderFeedURLs: [String] = [], searchText: String = "") {
        self.filter = filter
        self._selection = selection
        self.isSearching = !searchText.isEmpty

        // Les articles sélectionnés restent visibles dans "Non lus" même une fois marqués comme lus
        let sticky = Array(selection.wrappedValue)
        let urls = folderFeedURLs
        let q = searchText
        let predicate: Predicate<Article>?

        if q.isEmpty {
            switch filter {
            case .all:
                predicate = nil
            case .unread:
                predicate = #Predicate { !$0.isRead || sticky.contains($0.key) }
            case .starred:
                predicate = #Predicate { $0.isStarred }
            case .feed(let url):
                predicate = #Predicate { $0.feedURL == url }
            case .folder:
                predicate = #Predicate { urls.contains($0.feedURL) }
            }
        } else {
            // Même filtres, restreints aux articles dont le titre ou le texte contient la recherche
            switch filter {
            case .all:
                predicate = #Predicate {
                    $0.title.localizedStandardContains(q) || $0.searchText.localizedStandardContains(q)
                }
            case .unread:
                predicate = #Predicate {
                    (!$0.isRead || sticky.contains($0.key))
                        && ($0.title.localizedStandardContains(q) || $0.searchText.localizedStandardContains(q))
                }
            case .starred:
                predicate = #Predicate {
                    $0.isStarred
                        && ($0.title.localizedStandardContains(q) || $0.searchText.localizedStandardContains(q))
                }
            case .feed(let url):
                predicate = #Predicate {
                    $0.feedURL == url
                        && ($0.title.localizedStandardContains(q) || $0.searchText.localizedStandardContains(q))
                }
            case .folder:
                predicate = #Predicate {
                    urls.contains($0.feedURL)
                        && ($0.title.localizedStandardContains(q) || $0.searchText.localizedStandardContains(q))
                }
            }
        }
        var descriptor = FetchDescriptor<Article>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.published, order: .reverse)]
        )
        descriptor.fetchLimit = 1000
        // Pas d'animation : une mise à jour animée pendant le défilement fait sauter la liste
        _articles = Query(descriptor)
    }

    /// Hauteur fixe de chaque ligne. Toutes les lignes faisant exactement la même
    /// hauteur, la hauteur totale de la liste est connue d'avance : l'ascenseur
    /// ne peut plus « trembler » pendant le défilement.
    static let rowHeight: CGFloat = 100

    @FocusState private var isFocused: Bool
    @Environment(KeyboardRouter.self) private var keyboard
    @Environment(FeedStore.self) private var store

    /// Article seul sélectionné (nil si aucun ou plusieurs)
    private var single: Article? {
        guard selection.count == 1, let key = selection.first else { return nil }
        return articles.first { $0.key == key }
    }

    private var selectedArticles: [Article] {
        articles.filter { selection.contains($0.key) }
    }

    // Une ScrollView + LazyVStack plutôt qu'une List : sur macOS, List estime la
    // hauteur des lignes jamais affichées avec une valeur par défaut, puis la
    // corrige au défilement, ce qui faisait sauter la liste en bas.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(articles) { article in
                        row(for: article)
                    }
                }
                .padding(.vertical, 6)
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in
                moveSelection(by: 1, extend: press.modifiers.contains(.shift), proxy: proxy)
                return .handled
            }
            .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in
                moveSelection(by: -1, extend: press.modifiers.contains(.shift), proxy: proxy)
                return .handled
            }
            .onChange(of: keyboard.event) { _, event in
                if let event { perform(event.command, proxy: proxy) }
            }
        }
        .overlay {
            if articles.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: isSearching ? "magnifyingglass" : "tray")
            }
        }
    }

    private func row(for article: Article) -> some View {
        let isSelected = selection.contains(article.key)
        return ArticleRow(article: article)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.rowHeight)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(isFocused ? 0.22 : 0.12))
                }
            }
            .overlay(alignment: .bottom) {
                if !isSelected {
                    Divider().padding(.leading, 114).padding(.trailing, 10)
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture { click(article) }
            .contextMenu { menu(for: article) }
            .id(article.key)
    }

    // MARK: - Sélection

    /// Clic : sélection simple ; ⌘-clic : ajoute / retire ; ⇧-clic : plage depuis l'ancre
    private func click(_ article: Article) {
        let key = article.key
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor, let range = indexRange(anchor, key) {
            selection = Set(articles[range].map(\.key))
        } else if modifiers.contains(.command) {
            if selection.contains(key) { selection.remove(key) } else { selection.insert(key) }
            anchor = key
        } else {
            selection = [key]
            anchor = key
        }
        cursor = key
        isFocused = true
    }

    private func indexRange(_ a: String, _ b: String) -> ClosedRange<Int>? {
        guard let i = articles.firstIndex(where: { $0.key == a }),
              let j = articles.firstIndex(where: { $0.key == b }) else { return nil }
        return min(i, j)...max(i, j)
    }

    /// ↑ / ↓ (et j / k) : article précédent / suivant ; avec ⇧, étend la sélection
    private func moveSelection(by delta: Int, extend: Bool = false, proxy: ScrollViewProxy) {
        guard !articles.isEmpty else { return }
        let from = cursor.flatMap { c in articles.firstIndex { $0.key == c } }
            ?? articles.firstIndex { selection.contains($0.key) }
        let next = from.map { min(max($0 + delta, 0), articles.count - 1) } ?? 0
        let key = articles[next].key

        if extend, let anchor, let range = indexRange(anchor, key) {
            selection = Set(articles[range].map(\.key))
        } else {
            selection = [key]
            anchor = key
        }
        cursor = key
        proxy.scrollTo(key)   // sans ancre : défile juste assez pour rendre la ligne visible
    }

    private func selectAll() {
        selection = Set(articles.map(\.key))
        anchor = articles.first?.key
        cursor = articles.last?.key
    }

    // MARK: - Raccourcis

    /// Raccourcis façon Reeder (voir KeyboardRouter)
    private func perform(_ command: KeyCommand, proxy: ScrollViewProxy) {
        switch command {
        case .next:
            moveSelection(by: 1, proxy: proxy)
        case .previous:
            moveSelection(by: -1, proxy: proxy)
        case .pageDown:
            guard single != nil else {
                if selection.isEmpty { moveSelection(by: 1, proxy: proxy) }
                return
            }
            Task {
                // Une fois en bas de l'article, espace passe au suivant
                if await keyboard.scrollReader(down: true) {
                    moveSelection(by: 1, proxy: proxy)
                }
            }
        case .pageUp:
            Task { _ = await keyboard.scrollReader(down: false) }
        case .toggleRead:
            // Si tout est lu, on repasse en non lu ; sinon tout devient lu
            let targets = selectedArticles
            store.setRead(!targets.allSatisfy(\.isRead), targets)
        case .toggleStar:
            let targets = selectedArticles
            store.setStarred(!targets.allSatisfy(\.isStarred), targets)
        case .openInBrowser:
            if let link = single?.link, let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        case .selectAll:
            selectAll()
        }
    }

    private var emptyTitle: String {
        if isSearching { return String(localized: "Aucun résultat") }
        switch filter {
        case .unread: return String(localized: "Tout est lu")
        case .starred: return String(localized: "Aucun favori")
        default: return String(localized: "Aucun article")
        }
    }

    // MARK: - Menu contextuel

    /// S'applique à toute la sélection si on fait un clic droit sur un article sélectionné
    @ViewBuilder
    private func menu(for article: Article) -> some View {
        let targets = selection.contains(article.key) ? selectedArticles : [article]
        let allRead = targets.allSatisfy(\.isRead)
        let allStarred = targets.allSatisfy(\.isStarred)

        Button(allRead ? String(localized: "Marquer comme non lu") : String(localized: "Marquer comme lu")) {
            store.setRead(!allRead, targets)
        }
        Button(allStarred ? String(localized: "Retirer des favoris") : String(localized: "Ajouter aux favoris")) {
            store.setStarred(!allStarred, targets)
        }
        if targets.count == 1, let link = article.link, let url = URL(string: link) {
            Divider()
            Button("Ouvrir dans le navigateur") { NSWorkspace.shared.open(url) }
            Button("Copier le lien") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
            }
        }
    }
}

struct ArticleRow: View {
    let article: Article

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Thumbnail(url: article.imageURL.flatMap { URL(string: $0) })

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !article.isRead {
                        Circle().fill(.tint).frame(width: 7, height: 7)
                    }
                    Text(article.feed?.title ?? "")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if article.isStarred {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    Text(article.published.formatted(.relative(presentation: .named).locale(.app)))
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Hauteur réservée même si le texte est plus court
                Text(article.title)
                    .font(.system(size: 14, weight: article.isRead ? .regular : .semibold))
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2, reservesSpace: true)

                Text(article.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
        }
    }
}

struct Thumbnail: View {
    let url: URL?
    var width: CGFloat = 92
    var height: CGFloat = 69

    var body: some View {
        // Le cadre est fixé AVANT l'image : l'overlay ne peut pas agrandir la vue,
        // et le clipShape recadre l'image en scaledToFill à la bonne taille.
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.quaternary)
            .frame(width: width, height: height)
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "newspaper")
            .font(.title3)
            .foregroundStyle(.tertiary)
    }
}
