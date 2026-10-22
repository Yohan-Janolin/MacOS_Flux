import AppKit
import SwiftUI
import WebKit

/// Affiche le HTML de l'article. JavaScript est désactivé ; un clic sur un lien
/// l'ouvre dans le navigateur par défaut.
struct ArticleWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    @Environment(KeyboardRouter.self) private var keyboard

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        // Images servies depuis le cache disque (lecture hors ligne)
        config.setURLSchemeHandler(context.coordinator.imageHandler, forURLScheme: ImageCache.scheme)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        keyboard.readerWebView = webView   // pour faire défiler l'article à la touche espace
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        let imageHandler = CachedImageSchemeHandler()

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else { return .allow }
            // Ancres internes (notes de bas de page…) : on reste dans la vue
            if url.fragment != nil, let current = webView.url,
               url.absoluteString.components(separatedBy: "#").first == current.absoluteString.components(separatedBy: "#").first {
                return .allow
            }
            NSWorkspace.shared.open(url)
            return .cancel
        }
    }
}

enum ReaderTemplate {
    static func render(_ article: Article, body: String) -> String {
        var meta = [article.feed?.displayTitle, article.author]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .map(HTMLUtils.escape)
        meta.append(article.published.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: .app)))

        var hero = ""
        if let image = article.imageURL, let imageURL = URL(string: image) {
            let fileName = imageURL.lastPathComponent
            let alreadyInBody = fileName.count > 4 && body.contains(fileName)
            if !alreadyInBody {
                hero = "<img class=\"hero\" src=\"\(HTMLUtils.escape(ImageCache.proxyURL(for: imageURL)))\" alt=\"\">"
            }
        }
        // Toutes les images passent par le cache disque (disponibles hors ligne)
        let body = HTMLUtils.rewriteImagesForCache(body, base: article.link.flatMap { URL(string: $0) })

        return """
        <!doctype html>
        <html lang="\(Locale.app.language.languageCode?.identifier ?? "en")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        </head>
        <body>
        <article>
          <div class="meta">\(meta.joined(separator: " · "))</div>
          <h1 class="title">\(HTMLUtils.escape(article.title))</h1>
          \(hero)
          <div class="content">\(body)</div>
        </article>
        </body>
        </html>
        """
    }

    private static let css = """
    :root { color-scheme: light dark; --text: #1d1d1f; --muted: #6e6e73; --link: #0a66d8; --rule: rgba(0,0,0,.1); --code: rgba(0,0,0,.05); }
    @media (prefers-color-scheme: dark) {
      :root { --text: #e8e8ed; --muted: #98989f; --link: #5eaaff; --rule: rgba(255,255,255,.14); --code: rgba(255,255,255,.07); }
    }
    html { -webkit-text-size-adjust: 100%; }
    body {
      margin: 0; padding: 44px 48px 96px;
      font: 17px/1.68 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      color: var(--text); background: transparent;
      -webkit-font-smoothing: antialiased;
    }
    article { max-width: 680px; margin: 0 auto; }
    .meta { color: var(--muted); font-size: 12px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; }
    h1.title { font: 700 32px/1.18 "New York", ui-serif, Georgia, serif; letter-spacing: -.01em; margin: 10px 0 22px; }
    .hero { display: block; width: 100%; max-height: 440px; object-fit: cover; border-radius: 14px; margin: 0 0 28px; }
    .content h1, .content h2, .content h3 { line-height: 1.3; margin: 1.6em 0 .5em; }
    .content h1 { font-size: 1.5em; } .content h2 { font-size: 1.3em; } .content h3 { font-size: 1.1em; }
    .content p { margin: 0 0 1.1em; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    img, video, iframe, svg { max-width: 100%; height: auto; border-radius: 10px; }
    figure { margin: 1.8em 0; }
    figcaption { color: var(--muted); font-size: 13px; line-height: 1.45; margin-top: 8px; text-align: center; }
    blockquote { margin: 1.4em 0; padding: 2px 0 2px 18px; border-left: 3px solid var(--rule); color: var(--muted); font-style: italic; }
    hr { border: 0; border-top: 1px solid var(--rule); margin: 2em 0; }
    pre, code { font: 14px/1.5 ui-monospace, "SF Mono", Menlo, monospace; }
    code { background: var(--code); padding: .1em .35em; border-radius: 5px; }
    pre { background: var(--code); padding: 14px 16px; border-radius: 10px; overflow-x: auto; }
    pre code { background: none; padding: 0; }
    table { border-collapse: collapse; width: 100%; font-size: 15px; }
    td, th { border-bottom: 1px solid var(--rule); padding: 6px 8px; text-align: left; }
    ul, ol { padding-left: 1.4em; }
    """
}
