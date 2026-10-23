import SwiftUI

/// Onglet Réglages › Synchronisation (iCloud Drive)
struct SyncSettingsView: View {
    @Environment(SyncEngine.self) private var sync
    @AppStorage(Prefs.syncEnabled) private var enabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Synchroniser avec mes autres Mac via iCloud Drive", isOn: $enabled)
                    .disabled(!SyncEngine.isICloudDriveAvailable && !enabled)

                if !SyncEngine.isICloudDriveAvailable {
                    Label("iCloud Drive n'est pas activé sur ce Mac (Réglages Système › Identifiant Apple › iCloud › iCloud Drive).",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if enabled {
                    HStack {
                        if sync.isSyncing {
                            ProgressView().controlSize(.small)
                            Text("Synchronisation…").foregroundStyle(.secondary)
                        } else if let error = sync.lastError {
                            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        } else if let last = sync.lastSync {
                            Label {
                                Text("Synchronisé \(last.formatted(.relative(presentation: .named).locale(.app)))")
                            } icon: {
                                Image(systemName: "checkmark.icloud")
                            }
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Synchroniser maintenant") {
                            Task { await sync.sync() }
                        }
                        .disabled(sync.isSyncing)
                    }
                }
            } header: {
                Text("iCloud Drive")
            } footer: {
                Text("Synchronisés : flux, dossiers, noms personnalisés, règles de filtrage, articles lus et favoris. Non synchronisés : réglages, historique, statistiques et images (chaque Mac télécharge les siennes). Active l'option sur chaque Mac, avec le même compte iCloud. La première fois, macOS peut demander l'autorisation d'accéder à iCloud Drive.")
                    .foregroundStyle(.secondary)
            }

            if enabled {
                Section("Autres Mac") {
                    if sync.otherDevices.isEmpty {
                        Text("Aucun autre Mac pour l'instant. Active la synchronisation sur ton autre Mac : il apparaîtra ici.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sync.otherDevices.indices, id: \.self) { index in
                        let device = sync.otherDevices[index]
                        LabeledContent {
                            Text(device.updated.formatted(.relative(presentation: .named).locale(.app)))
                                .foregroundStyle(.secondary)
                        } label: {
                            Label(device.name, systemImage: "laptopcomputer")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: enabled) {
            if enabled {
                Task { await sync.sync() }
            } else {
                sync.disable()
            }
        }
    }
}
