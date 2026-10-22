import AppKit
import SwiftData
import SwiftUI

enum SidebarSelection: Hashable {
    case all
    case unread
    case starred
    case feed(String)
}

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Environment(FeedStore.self) private var store

    @Query(sort: \Feed.title) private var feeds: [Feed]
    @Query(filter: #Predicate<Article> { !$0.isRead }) private var unread: [Article]

    private var unreadByFeed: [String: Int] {
        Dictionary(grouping: unread, by: \.feedURL).mapValues(\.count)
    }

    var body: some View {
        let counts = unreadByFeed
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

            Section("Flux") {
                if feeds.isEmpty {
                    Text("Ajoute un flux avec le bouton +")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(feeds) { feed in
                    FeedRow(feed: feed)
                        .badge(counts[feed.url] ?? 0)
                        .tag(SidebarSelection.feed(feed.url))
                        .contextMenu {
                            Button("Tout marquer comme lu") { store.markAllRead(.feed(feed.url)) }
                            Button("Actualiser") { Task { await store.refresh(feed) } }
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
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 230)
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
