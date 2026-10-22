import AppKit
import SwiftData
import SwiftUI

struct ArticleListView: View {
    @Query private var articles: [Article]
    @Binding var selection: String?
    private let filter: SidebarSelection

    /// `folderFeedURLs` : adresses des flux du dossier quand `filter` est `.folder`
    init(filter: SidebarSelection, selection: Binding<String?>, folderFeedURLs: [String] = []) {
        self.filter = filter
        self._selection = selection

        // L'article sélectionné reste visible dans "Non lus" même une fois marqué comme lu
        let sticky = selection.wrappedValue ?? ""
        let predicate: Predicate<Article>?
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
            let urls = folderFeedURLs
            predicate = #Predicate { urls.contains($0.feedURL) }
        }
        var descriptor = FetchDescriptor<Article>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.published, order: .reverse)]
        )
        descriptor.fetchLimit = 1000
        // Pas d'animation : une mise à jour animée pendant le défilement fait sauter la liste
        _articles = Query(descriptor)
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(articles) { article in
                ArticleRow(article: article)
                    .tag(article.key)
                    .contextMenu { menu(for: article) }
            }
        }
        .listStyle(.inset)
        .overlay {
            if articles.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "tray")
            }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .unread: "Tout est lu"
        case .starred: "Aucun favori"
        default: "Aucun article"
        }
    }

    @ViewBuilder
    private func menu(for article: Article) -> some View {
        Button(article.isRead ? "Marquer comme non lu" : "Marquer comme lu") {
            article.isRead.toggle()
        }
        Button(article.isStarred ? "Retirer des favoris" : "Ajouter aux favoris") {
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
                    Text(article.published.formatted(.relative(presentation: .named).locale(.fr)))
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Hauteur réservée même si le texte est plus court : toutes les lignes
                // de la liste ont la même hauteur, ce qui évite que la liste « tremble »
                // quand macOS corrige la hauteur estimée des lignes pas encore affichées.
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
        .padding(.vertical, 6)
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
