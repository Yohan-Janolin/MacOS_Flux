import SwiftUI

struct SettingsView: View {
    @Environment(FeedStore.self) private var store

    @AppStorage(Prefs.autoMarkReadEnabled) private var autoMarkReadEnabled = false
    @AppStorage(Prefs.autoMarkReadDays) private var autoMarkReadDays = 7
    @AppStorage(Prefs.refreshMinutes) private var refreshMinutes = 30
    @AppStorage(Prefs.retentionDays) private var retentionDays = 60
    @AppStorage(Prefs.appearance) private var appearance = AppAppearance.system

    @State private var language = AppLanguage.current
    @State private var languageChanged = false
    @State private var askRelaunch = false

    var body: some View {
        Form {
            Section {
                Picker("Apparence", selection: $appearance) {
                    Text("Automatique").tag(AppAppearance.system)
                    Text("Clair").tag(AppAppearance.light)
                    Text("Sombre").tag(AppAppearance.dark)
                }
                Picker("Langue", selection: $language) {
                    Text("Langue du système").tag(AppLanguage.system)
                    Text(verbatim: "Français").tag("fr")
                    Text(verbatim: "English").tag("en")
                }
                if languageChanged {
                    HStack {
                        Text("La nouvelle langue s'appliquera au prochain lancement.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Relancer Flux") { AppLanguage.relaunch() }
                    }
                }
            } header: {
                Text("Général")
            }

            Section {
                Toggle("Marquer automatiquement comme lus les anciens articles", isOn: $autoMarkReadEnabled)
                Picker("Articles publiés il y a plus de", selection: $autoMarkReadDays) {
                    Text("1 jour").tag(1)
                    Text("2 jours").tag(2)
                    Text("3 jours").tag(3)
                    Text("1 semaine").tag(7)
                    Text("2 semaines").tag(14)
                    Text("1 mois").tag(30)
                }
                .disabled(!autoMarkReadEnabled)
            } header: {
                Text("Lecture")
            } footer: {
                Text("S'applique aux articles existants et à ceux qui arrivent. Les favoris ne sont jamais marqués automatiquement.")
                    .foregroundStyle(.secondary)
            }

            Section("Actualisation") {
                Picker("Actualiser les flux", selection: $refreshMinutes) {
                    Text("Toutes les 15 minutes").tag(15)
                    Text("Toutes les 30 minutes").tag(30)
                    Text("Toutes les heures").tag(60)
                    Text("Toutes les 2 heures").tag(120)
                    Text("Toutes les 6 heures").tag(360)
                }
            }

            Section {
                Picker("Supprimer les articles lus après", selection: $retentionDays) {
                    Text("2 semaines").tag(14)
                    Text("1 mois").tag(30)
                    Text("2 mois").tag(60)
                    Text("3 mois").tag(90)
                    Text("6 mois").tag(180)
                    Text("1 an").tag(365)
                }
            } header: {
                Text("Stockage")
            } footer: {
                Text("Les articles non lus et les favoris sont toujours conservés.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: appearance) {
            AppAppearance.apply(appearance)
        }
        .onChange(of: language) {
            AppLanguage.set(language)
            languageChanged = true
            askRelaunch = true
        }
        .alert("Relancer Flux maintenant ?", isPresented: $askRelaunch) {
            Button("Relancer") { AppLanguage.relaunch() }
                .keyboardShortcut(.defaultAction)
            Button("Plus tard", role: .cancel) {}
        } message: {
            Text("La nouvelle langue sera appliquée au redémarrage de l'app.")
        }
        .onChange(of: autoMarkReadEnabled) { store.applyAutoMarkRead() }
        .onChange(of: autoMarkReadDays) { store.applyAutoMarkRead() }
    }
}
