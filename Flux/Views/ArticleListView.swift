import AppKit
import SwiftData
import SwiftUI

struct ArticleListView: View {
    @Query private var articles: [Article]
    @Binding var selection: String?
    private let filter: SidebarSelection

    private let isSearching: Bool

    /// `folderFeedURLs` : adresses des flux du dossier quand `filter` est `.folder`
    /// `searchText` : recherche dans le titre et le résumé (vide = pas de recherche)
    init(filter: SidebarSelection, selection: Binding<String?>, folderFeedURLs: [String] = [], searchText: String = "") {
        self.filter = filter
        self._selection = selection
        self.isSearching = !searchText.isEmpty

        // L'article sélectionné reste visible dans "Non lus" même une fois marqué comme lu
        let sticky = selection.wrappedValue ?? ""
        let urls = folderFeedURLs
        let q = searchText
        let predicate: Predicate<Article>?

        if q.isEmpty {
            switch filter {
            case .all:
                predicate = nil
            case .unread:
                predicate = #Predicate { !$0.isRead || $0.key == sticky }
            case .starred:
                predicate = #Predicate { $0.isStarred }
            case .feed(let url):
                predicate = #Predicate { $0.feedURL == url }
            case .folder:
                predicate = #Predicate { urls.contains($0.feedURL) }
            }
        } else {
            // Même filtres, restreints aux articles dont le titre ou le résumé contient la recherche
            switch filter {
            case .all:
                predicate = #Predicate {
                    $0.title.localizedStandardContains(q) || $0.summary.localizedStandardContains(q)
                }
            case .unread:
                predicate = #Predicate {
                    (!$0.isRead || $0.key == sticky)
                        && ($0.title.localizedStandardContains(q) || $0.summary.localizedStandardContains(q))
                }
            case .starred:
                predicate = #Predicate {
                    $0.isStarred
                        && ($0.title.localizedStandardContains(q) || $0.summary.localizedStandardContains(q))
                }
            case .feed(let url):
                predicate = #Predicate {
                    $0.feedURL == url
                        && ($0.title.localizedStandardContains(q) || $0.summary.localizedStandardContains(q))
                }
            case .folder:
                predicate = #Predicate {
                    urls.contains($0.feedURL)
                        && ($0.title.localizedStandardContains(q) || $0.summary.localizedStandardContains(q))
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
            .onKeyPress(.downArrow) {
                moveSelection(by: 1, proxy: proxy)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveSelection(by: -1, proxy: proxy)
                return .handled
            }
        }
        .overlay {
            if articles.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: isSearching ? "magnifyingglass" : "tray")
            }
        }
    }

    private func row(for article: Article) -> some View {
        let isSelected = selection == article.key
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
            .onTapGesture {
                selection = article.key
                isFocused = true
            }
            .contextMenu { menu(for: article) }
            .id(article.key)
    }

    /// Flèches ↑ / ↓ : article précédent / suivant
    private func moveSelection(by delta: Int, proxy: ScrollViewProxy) {
        guard !articles.isEmpty else { return }
        let next: Int
        if let current = articles.firstIndex(where: { $0.key == selection }) {
            next = min(max(current + delta, 0), articles.count - 1)
        } else {
            next = 0
        }
        let key = articles[next].key
        selection = key
        proxy.scrollTo(key)   // sans ancre : défile juste assez pour rendre la ligne visible
    }

    private var emptyTitle: String {
        if isSearching { return String(localized: "Aucun résultat") }
        switch filter {
        case .unread: return String(localized: "Tout est lu")
        case .starred: return String(localized: "Aucun favori")
        default: return String(localized: "Aucun article")
        }
    }

    @ViewBuilder
    private func menu(for article: Article) -> some View {
        Button(article.isRead ? String(localized: "Marquer comme non lu") : String(localized: "Marquer comme lu")) {
            article.isRead.toggle()
        }
        Button(article.isStarred ? String(localized: "Retirer des favoris") : String(localized: "Ajouter aux favoris")) {
            article.isStarred.toggle()
        }
        if let link = article.link, let url = URL(string: link) {
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
