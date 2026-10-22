import AppKit
import UniformTypeIdentifiers
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.modelContext) private var context
    @Environment(UIState.self) private var ui
    @Environment(KeyboardRouter.self) private var keyboard

    @State private var filter: SidebarSelection? = .all
    @State private var selectedKey: String?
    @State private var showAddFeed = false
    @State private var showNewFolder = false
    @State private var searchText = ""
    @State private var importMessage: String?

    /// Largeur de la liste d'articles, mémorisée d'un lancement à l'autre
    @AppStorage("articleListWidth") private var listWidth: Double = 400
    static let listWidthRange: ClosedRange<Double> = 300...700
    @AppStorage(Prefs.refreshMinutes) private var refreshMinutes = 30

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
        // Deux colonnes seulement pour NavigationSplitView (barre latérale | reste) :
        // en trois colonnes, macOS ignore la largeur voulue de la liste au lancement
        // et ne la mémorise pas. La liste et l'article sont donc côte à côte dans la
        // colonne de détail, avec une largeur de liste enregistrée dans les réglages.
        NavigationSplitView {
            SidebarView(selection: $filter, showNewFolder: $showNewFolder)
        } detail: {
            HStack(spacing: 0) {
                ArticleListView(
                    filter: filter ?? .all,
                    selection: $selectedKey,
                    folderFeedURLs: folderFeedURLs,
                    searchText: searchText.trimmingCharacters(in: .whitespaces)
                )
                .frame(width: listWidth)

                ColumnResizer(width: $listWidth, range: Self.listWidthRange)

                Group {
                    if let article = selectedArticle {
                        ArticleDetailView(article: article)
                            .id(article.key)
                    } else {
                        ContentUnavailableView("Aucun article sélectionné", systemImage: "newspaper")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: Text("Rechercher"))
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

            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Label("Réglages", systemImage: "gearshape")
                }
                .help("Réglages (⌘,)")
            }
        }
        .fileImporter(
            isPresented: Binding(get: { ui.showOPMLImport }, set: { ui.showOPMLImport = $0 }),
            allowedContentTypes: [.opml, .xml]
        ) { result in
            guard case .success(let url) = result else { return }
            Task { await importOPML(from: url) }
        }
        .fileExporter(
            isPresented: Binding(get: { ui.showOPMLExport }, set: { ui.showOPMLExport = $0 }),
            document: ui.showOPMLExport ? OPMLDocument(text: store.exportOPML()) : nil,
            contentType: .opml,
            defaultFilename: "Flux.opml"
        ) { _ in }
        .alert(
            "Import OPML",
            isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(importMessage ?? "")
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
        .background(WindowReader { keyboard.mainWindow = $0 })
        .onAppear { keyboard.start() }
        .task {
            // Actualisation au lancement
            await store.refreshAll()
        }
        .task(id: refreshMinutes) {
            // Puis à intervalle régulier ; la boucle redémarre si le réglage change
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(max(refreshMinutes, 5)) * 60))
                guard !Task.isCancelled else { break }
                await store.refreshAll()
            }
        }
    }

    private func importOPML(from url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importMessage = String(localized: "Impossible de lire ce fichier.")
            return
        }
        let result = await store.importOPML(data)
        if result.added == 0 && result.skipped == 0 {
            importMessage = String(localized: "Aucun abonnement trouvé dans ce fichier.")
        } else {
            importMessage = String(localized: "\(result.added) flux importés, \(result.skipped) ignorés (déjà présents ou invalides).")
        }
    }
}

/// Séparateur vertical qu'on peut faire glisser pour redimensionner la colonne de gauche.
struct ColumnResizer: View {
    @Binding var width: Double
    let range: ClosedRange<Double>

    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                // Zone de prise plus large que le trait, sans prendre de place dans la mise en page
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = startWidth ?? width
                                startWidth = start
                                width = min(max(start + value.translation.width, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in startWidth = nil }
                    )
            }
            .onAppear {
                // Au cas où une valeur enregistrée sortirait des bornes
                width = min(max(width, range.lowerBound), range.upperBound)
            }
    }
}

