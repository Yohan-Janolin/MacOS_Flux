import AppKit
import SwiftUI

struct ArticleDetailView: View {
    let article: Article

    @State private var showFull = false
    @State private var loading = false
    @State private var errorMessage: String?

    private var articleURL: URL? { article.link.flatMap { URL(string: $0) } }

    private var bodyHTML: String {
        if showFull, let full = article.fullHTML { return full }
        if let content = article.contentHTML, !content.isEmpty { return content }
        return "<p>\(HTMLUtils.escape(article.summary))</p>"
    }

    var body: some View {
        ArticleWebView(html: ReaderTemplate.render(article, body: bodyHTML), baseURL: articleURL)
            .overlay(alignment: .top) {
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Récupération de l'article complet…")
                    }
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 12)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 16)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: loading)
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        toggleFull()
                    } label: {
                        Label(showFull ? String(localized: "Version du flux") : String(localized: "Article complet"),
                              systemImage: showFull ? "doc.plaintext" : "doc.richtext")
                    }
                    .help(showFull ? String(localized: "Afficher le contenu fourni par le flux") : String(localized: "Récupérer l'article complet depuis le site"))
                    .disabled(articleURL == nil || loading)

                    Button {
                        article.isStarred.toggle()
                    } label: {
                        Label("Favori", systemImage: article.isStarred ? "star.fill" : "star")
                    }
                    .help(article.isStarred ? String(localized: "Retirer des favoris") : String(localized: "Ajouter aux favoris"))

                    if let url = articleURL {
                        ShareLink(item: url)
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Ouvrir dans le navigateur", systemImage: "safari")
                        }
                        .help("Ouvrir dans le navigateur")
                    }
                }
            }
            .task { await prepare() }
    }

    /// Si le flux ne fournit qu'un extrait, on va chercher l'article complet.
    private func prepare() async {
        if article.fullHTML != nil {
            showFull = true
            return
        }
        let feedTextLength = HTMLUtils.plainText(article.contentHTML ?? "").count
        if feedTextLength < 700, articleURL != nil {
            await loadFull()
        }
    }

    private func toggleFull() {
        if showFull {
            showFull = false
        } else if article.fullHTML != nil {
            showFull = true
        } else {
            Task { await loadFull() }
        }
    }

    private func loadFull() async {
        guard let url = articleURL else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            let content = try await FullTextLoader.load(url)
            guard !Task.isCancelled else { return }
            if let content {
                article.fullHTML = content
                if article.imageURL == nil {
                    article.imageURL = HTMLUtils.firstImage(in: content)
                }
                showFull = true
            } else {
                errorMessage = String(localized: "Impossible d'extraire le contenu de cette page.")
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = String(localized: "Échec du téléchargement : \(error.localizedDescription)")
        }
    }
}
