import SwiftData
import SwiftUI

@main
struct FluxApp: App {
    private let container: ModelContainer
    @State private var store: FeedStore
    @State private var ui = UIState()
    @State private var keyboard = KeyboardRouter()

    init() {
        Prefs.register()
        AppAppearance.apply()

        // Cache disque généreux pour les miniatures (AsyncImage passe par URLCache.shared)
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)

        // Base dans ~/Library/Application Support/Flux/ (l'app n'est pas sandboxée,
        // on évite le "default.store" partagé avec d'autres apps)
        let directory = URL.applicationSupportDirectory.appending(path: "Flux", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: directory.appending(path: "Flux.store"))

        let modelContainer: ModelContainer
        do {
            modelContainer = try ModelContainer(for: Feed.self, Article.self, Folder.self, FilterRule.self, configurations: configuration)
        } catch {
            fatalError("Impossible d'ouvrir la base : \(error)")
        }
        container = modelContainer
        _store = State(initialValue: FeedStore(context: modelContainer.mainContext))
    }

    var body: some Scene {
        Window("Flux", id: "main") {
            ContentView()
                .environment(store)
                .environment(ui)
                .environment(keyboard)
                .frame(minWidth: 1000, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 820)
        .modelContainer(container)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutMenuItem()
            }
            CommandGroup(after: .toolbar) {
                Divider()
                ReaderTextSizeCommands()
                Divider()
                StatsMenuItem()
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Importer des abonnements (OPML)…") { ui.showOPMLImport = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Exporter les abonnements (OPML)…") { ui.showOPMLExport = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        Window("Statistiques de lecture", id: "stats") {
            StatsView()
        }
        .modelContainer(container)
        .defaultSize(width: 760, height: 680)

        Window("À propos de Flux", id: "about") {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(store)
                .modelContainer(container)
        }
    }
}
