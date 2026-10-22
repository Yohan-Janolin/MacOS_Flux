import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.modelContext) private var context

    @State private var filter: SidebarSelection? = .all
    @State private var selectedKey: String?
    @State private var showAddFeed = false
    @State private var showNewFolder = false

    /// Observé pour que la liste se mette à jour quand on déplace un flux de dossier
    @Query private var feeds: [Feed]

    private var folderFeedURLs: [String] {
        guard case .folder(let uid) = filter ?? .all else { return [] }
        return feeds.filter { $0.folder?.uid == uid }.map(\.url)
    }

    /// Dossier pré-sélectionné dans la fenêtre d'ajout
    private var currentFolderUID: String? {
        switch filter ?? .all {
        case .folder(let uid): uid
        case .feed(let url): feeds.first { $0.url == url }?.folder?.uid
        default: nil
        }
    }

    private var selectedArticle: Article? {
        guard let key = selectedKey else { return nil }
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $filter, showNewFolder: $showNewFolder)
        } content: {
            ArticleListView(filter: filter ?? .all, selection: $selectedKey, folderFeedURLs: folderFeedURLs)
                .navigationSplitViewColumnWidth(min: 320, ideal: 400)
        } detail: {
            if let article = selectedArticle {
                ArticleDetailView(article: article)
                    .id(article.key)
            } else {
                ContentUnavailableView("Aucun article sélectionné", systemImage: "newspaper")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    showAddFeed = true
                } label: {
                    Label("Ajouter un flux", systemImage: "plus")
                }
                .keyboardShortcut("n")
                .help("Ajouter un flux (⌘N)")

                Button {
                    showNewFolder = true
                } label: {
                    Label("Nouveau dossier", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Nouveau dossier (⇧⌘N)")

                Button {
                    Task { await store.refreshAll() }
                } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                    }
                }
                .keyboardShortcut("r")
                .disabled(store.isRefreshing)
                .help("Actualiser tous les flux (⌘R)")

                Button {
                    store.markAllRead(filter ?? .all)
                } label: {
                    Label("Tout marquer comme lu", systemImage: "checkmark.circle")
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .help("Tout marquer comme lu (⇧⌘K)")
            }
        }
        .sheet(isPresented: $showAddFeed) {
            AddFeedSheet(initialFolderUID: currentFolderUID)
        }
        .onChange(of: filter) {
            selectedKey = nil
        }
        .onChange(of: selectedKey) {
            if let article = selectedArticle, !article.isRead {
                article.isRead = true
            }
        }
        .task {
            // Actualisation au lancement, puis toutes les 30 minutes
            await store.refreshAll()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30 * 60))
                guard !Task.isCancelled else { break }
                await store.refreshAll()
            }
        }
    }
}
