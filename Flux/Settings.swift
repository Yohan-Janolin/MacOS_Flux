import AppKit
import Foundation

/// Clés des réglages (UserDefaults / @AppStorage) et leurs valeurs par défaut.
enum Prefs {
    static let autoMarkReadEnabled = "autoMarkReadEnabled"
    static let autoMarkReadDays = "autoMarkReadDays"
    static let refreshMinutes = "refreshMinutes"
    static let retentionDays = "retentionDays"
    static let appearance = "appearance"
    /// Délai avant de marquer comme lu l'article ouvert, en secondes (0 = immédiatement, -1 = jamais)
    static let markReadDelay = "markReadDelay"
    /// Présentation de la liste d'articles : "list" ou "grid"
    static let articleLayout = "articleLayout"

    static let defaults: [String: Any] = [
        autoMarkReadEnabled: false,
        autoMarkReadDays: 7,
        refreshMinutes: 30,
        retentionDays: 60,
        appearance: AppAppearance.system,
        markReadDelay: 0,
    ]

    static func register() {
        UserDefaults.standard.register(defaults: defaults)
    }

    /// Date avant laquelle un article est automatiquement marqué comme lu (nil = option désactivée)
    static var autoMarkReadCutoff: Date? {
        let d = UserDefaults.standard
        guard d.bool(forKey: autoMarkReadEnabled) else { return nil }
        let days = max(d.integer(forKey: autoMarkReadDays), 1)
        return Date.now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// Les articles lus (et non favoris) plus vieux que ça sont supprimés
    static var retentionCutoff: Date {
        let days = max(UserDefaults.standard.integer(forKey: retentionDays), 7)
        return Date.now.addingTimeInterval(-Double(days) * 86_400)
    }
}

/// Apparence de l'app : celle de macOS, ou forcée en clair / sombre.
/// Appliquée à toute l'app (fenêtres, réglages et vue de lecture, dont le CSS
/// suit `prefers-color-scheme`).
enum AppAppearance {
    static let system = "system"
    static let light = "light"
    static let dark = "dark"

    @MainActor
    static func apply(_ value: String? = nil) {
        let v = value ?? UserDefaults.standard.string(forKey: Prefs.appearance) ?? system
        switch v {
        case light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        default: NSApplication.shared.appearance = nil   // suit macOS
        }
    }
}

/// Langue de l'interface. Par défaut, celle de macOS ; on peut la forcer
/// (équivaut au réglage par app de Réglages Système › Langue et région).
enum AppLanguage {
    static let system = "system"
    private static let key = "AppleLanguages"

    /// "system", "fr" ou "en"
    static var current: String {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        guard let first = (domain[key] as? [String])?.first else { return system }
        return first.hasPrefix("fr") ? "fr" : first.hasPrefix("en") ? "en" : system
    }

    static func set(_ code: String) {
        if code == system {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set([code], forKey: key)
        }
    }

    /// Relance l'app pour appliquer la nouvelle langue
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
