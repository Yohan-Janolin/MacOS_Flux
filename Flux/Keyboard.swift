import AppKit
import Observation
import SwiftUI
import WebKit

/// Raccourcis à une touche, façon Reeder.
enum KeyCommand: Equatable {
    case next           // j
    case previous       // k
    case pageDown       // espace : fait défiler l'article, puis passe au suivant une fois en bas
    case pageUp         // ⇧ espace
    case toggleRead     // m
    case toggleStar     // s
    case openInBrowser  // b
}

/// Intercepte les touches de la fenêtre principale et les transmet à la liste
/// d'articles. Les touches sont laissées tranquilles quand on tape dans un champ
/// de texte, quand une feuille est ouverte, ou avec ⌘ / ⌃ / ⌥.
@MainActor
@Observable
final class KeyboardRouter {
    struct Event: Equatable {
        let id = UUID()
        let command: KeyCommand
    }

    /// Dernière commande reçue (la liste d'articles l'observe)
    private(set) var event: Event?

    @ObservationIgnored weak var mainWindow: NSWindow?
    @ObservationIgnored weak var readerWebView: WKWebView?
    @ObservationIgnored private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handle(event) }
            return handled ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window = event.window, window === mainWindow, window.attachedSheet == nil else { return false }
        // Champ de recherche, renommage… : la frappe doit passer
        if window.firstResponder is NSText { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }

        let shift = event.modifierFlags.contains(.shift)
        let command: KeyCommand
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "j": command = .next
        case "k": command = .previous
        case " ": command = shift ? .pageUp : .pageDown
        case "m": command = .toggleRead
        case "s": command = .toggleStar
        case "b": command = .openInBrowser
        default: return false
        }
        self.event = Event(command: command)
        return true
    }

    /// Fait défiler l'article d'environ un écran.
    /// Renvoie true si l'article était déjà tout en bas (ou tout en haut).
    func scrollReader(down: Bool) async -> Bool {
        guard let webView = readerWebView else { return false }
        let js = """
        const el = document.scrollingElement || document.documentElement;
        const page = window.innerHeight * 0.85;
        if (down) {
            if (el.scrollTop + window.innerHeight >= el.scrollHeight - 4) { return true; }
            window.scrollBy({ top: page, behavior: "smooth" });
        } else {
            if (el.scrollTop <= 0) { return true; }
            window.scrollBy({ top: -page, behavior: "smooth" });
        }
        return false;
        """
        // Monde "client" : nos scripts restent autorisés même si le JavaScript de la page est désactivé
        let result = try? await webView.callAsyncJavaScript(
            js, arguments: ["down": down], in: nil, contentWorld: .defaultClient)
        return (result as? Bool) ?? false
    }
}

/// Récupère la fenêtre AppKit qui contient une vue SwiftUI.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}
