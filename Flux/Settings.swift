import Foundation

/// Clés des réglages (UserDefaults / @AppStorage) et leurs valeurs par défaut.
enum Prefs {
    static let autoMarkReadEnabled = "autoMarkReadEnabled"
    static let autoMarkReadDays = "autoMarkReadDays"
    static let refreshMinutes = "refreshMinutes"
    static let retentionDays = "retentionDays"

    static let defaults: [String: Any] = [
        autoMarkReadEnabled: false,
        autoMarkReadDays: 7,
        refreshMinutes: 30,
        retentionDays: 60,
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
