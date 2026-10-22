import AppKit
import SwiftData
import SwiftUI

enum SidebarSelection: Hashable {
    case all
    case unread
    case starred
    case folder(String)   // Folder.uid
    case feed(String)     // Feed.url
}

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Binding var showNewFolder: Bool
    @Environment(FeedStore.self) private var store

    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(filter: #Predicate<Article> { !$0.isRead }) private var unread: [Article]

    @State private var newFolderName = ""
    @State private var editingFolder: Folder?

    var body: some View {
        let counts = Dictionary(grouping: unread, by: \.feedURL).mapValues(\.count)

        List(selection: $selection) {
            Section {
                Label("Tous les articles", systemImage: "tray.full")
                    .tag(SidebarSelection.all)
                Label("Non lus", systemImage: "circle.inset.filled")
                    .badge(unread.count)
                    .tag(SidebarSelection.unread)
                Label("Favoris", systemImage: "star")
                    .tag(SidebarSelection.starred)
            }

            Section {
                if feeds.isEmpty && folders.isEmpty {
                    Text("Ajoute un flux avec le bouton +")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ForEach(folders) { folder in
                    folderGroup(folder, counts: counts)
                }

                ForEach(feeds.filter { $0.folder == nil }) { feed in
                    feedRow(feed, counts: counts)
                }
            } header: {
                Text("Flux")
                    // Déposer un flux sur l'en-tête le sort de son dossier
                    .dropDestination(for: String.self) { urls, _ in
                        store.move(feedURLs: urls, to: nil)
                        return true
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 230)
        .contextMenu {
            Button("Nouveau dossier…") { showNewFolder = true }
        }
        .alert("Nouveau dossier", isPresented: $showNewFolder) {
            TextField("Nom du dossier", text: $newFolderName)
            Button("Créer") {
                store.createFolder(named: newFolderName)
                newFolderName = ""
            }
            Button("Annuler", role: .cancel) { newFolderName = "" }
        }
        .sheet(item: $editingFolder) { folder in
            FolderEditSheet(folder: folder)
        }
    }

    // MARK: - Dossier

    private func folderGroup(_ folder: Folder, counts: [String: Int]) -> some View {
        let folderFeeds = feeds.filter { $0.folder?.uid == folder.uid }
        let unreadInFolder = folderFeeds.reduce(0) { $0 + (counts[$1.url] ?? 0) }

        return DisclosureGroup(isExpanded: Binding(
            get: { folder.isExpanded },
            set: { folder.isExpanded = $0 }
        )) {
            ForEach(folderFeeds) { feed in
                feedRow(feed, counts: counts)
            }
        } label: {
            Label {
                Text(folder.name)
            } icon: {
                Image(systemName: folder.symbolName)
                    .foregroundStyle(folder.tint ?? Color.accentColor)
            }
                .badge(unreadInFolder)
                .tag(SidebarSelection.folder(folder.uid))
                .dropDestination(for: String.self) { urls, _ in
                    store.move(feedURLs: urls, to: folder)
                    folder.isExpanded = true
                    return true
                }
                .contextMenu {
                    Button("Tout marquer comme lu") { store.markAllRead(.folder(folder.uid)) }
                    Button("Actualiser") {
                        Task { for feed in folderFeeds { await store.refresh(feed) } }
                    }
                    Divider()
                    Button("Personnaliser…") { editingFolder = folder }
                    Button("Nouveau dossier…") { showNewFolder = true }
                    Divider()
                    Button("Supprimer le dossier", role: .destructive) {
                        if selection == .folder(folder.uid) { selection = .all }
                        store.delete(folder)
                    }
                }
        }
    }

    // MARK: - Flux

    private func feedRow(_ feed: Feed, counts: [String: Int]) -> some View {
        FeedRow(feed: feed)
            .badge(counts[feed.url] ?? 0)
            .tag(SidebarSelection.feed(feed.url))
            .draggable(feed.url)
            .contextMenu {
                Button("Tout marquer comme lu") { store.markAllRead(.feed(feed.url)) }
                Button("Actualiser") { Task { await store.refresh(feed) } }

                Menu("Déplacer vers") {
                    ForEach(folders) { folder in
                        Button(folder.name) { store.move(feed, to: folder) }
                            .disabled(feed.folder?.uid == folder.uid)
                    }
                    if !folders.isEmpty { Divider() }
                    Button("Hors dossier") { store.move(feed, to: nil) }
                        .disabled(feed.folder == nil)
                }

                Divider()
                if let site = feed.siteURL, let url = URL(string: site) {
                    Button("Ouvrir le site") { NSWorkspace.shared.open(url) }
                }
                Button("Copier l'adresse du flux") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(feed.url, forType: .string)
                }
                Divider()
                Button("Supprimer le flux", role: .destructive) {
                    if selection == .feed(feed.url) { selection = .all }
                    store.delete(feed)
                }
            }
    }
}

struct FeedRow: View {
    let feed: Feed

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(feed.title).lineLimit(1)
                if let error = feed.lastError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(error)
                }
            }
        } icon: {
            AsyncImage(url: feed.faviconURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image(systemName: "dot.radiowaves.up.forward")
                }
            }
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}
