import SwiftData
import SwiftUI

/// Onglet Réglages › Filtres : règles d'exclusion par mot-clé dans le titre
struct FiltersSettingsView: View {
    @Environment(FeedStore.self) private var store
    @Query(sort: \FilterRule.createdAt) private var rules: [FilterRule]
    @Query private var feeds: [Feed]

    @State private var editing: FilterRule?
    @State private var showNew = false
    /// Recalcul des compteurs après une modification
    @State private var refreshToken = 0

    var body: some View {
        Form {
            Section {
                if rules.isEmpty {
                    Text("Aucune règle. Ajoute un mot-clé pour masquer les articles dont le titre le contient.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    row(rule)
                }
            } header: {
                HStack {
                    Text("Règles")
                    Spacer()
                    Button {
                        showNew = true
                    } label: {
                        Label("Ajouter une règle", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text("Les règles portent sur le titre, sans tenir compte des majuscules ni des accents. Elles s'appliquent aux articles existants et à ceux qui arrivent. Les favoris ne sont jamais filtrés. Supprimer une règle fait réapparaître les articles qu'elle masquait.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Hauteur selon le nombre de règles (une ligne ≈ 52 pt)
        .settingsTab(idealHeight: 175 + CGFloat(max(rules.count, 1) - 1) * 52 + (rules.isEmpty ? 0 : 8))
        .sheet(isPresented: $showNew) {
            FilterRuleSheet(rule: nil, feeds: sortedFeeds) { keyword, wholeWord, action, feedURL in
                store.addFilter(keyword: keyword, wholeWord: wholeWord, action: action, feedURL: feedURL)
                refreshToken += 1
            }
        }
        .sheet(item: $editing) { rule in
            FilterRuleSheet(rule: rule, feeds: sortedFeeds) { keyword, wholeWord, action, feedURL in
                store.updateFilter(rule, keyword: keyword, wholeWord: wholeWord, action: action, feedURL: feedURL)
                refreshToken += 1
            }
        }
    }

    private var sortedFeeds: [Feed] {
        feeds.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    private func row(_ rule: FilterRule) -> some View {
        let count = store.matchCount(of: rule)
        let scope = rule.feedURL.flatMap { url in feeds.first { $0.url == url }?.displayTitle }
            ?? String(localized: "Tous les flux")
        var details = [scope, rule.filterAction.label]
        if rule.wholeWord { details.insert(String(localized: "Mot entier"), at: 0) }

        return HStack(spacing: 10) {
            Image(systemName: rule.filterAction == .hide ? "eye.slash" : "checkmark.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.keyword).font(.body.weight(.semibold))
                Text(details.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(count == 0 ? String(localized: "Aucun article") : String(localized: "\(count) articles"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .id(refreshToken)
            Button {
                editing = rule
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Modifier la règle")
            Button(role: .destructive) {
                store.deleteFilter(rule)
                refreshToken += 1
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Supprimer la règle")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = rule }
    }
}

/// Création ou modification d'une règle
struct FilterRuleSheet: View {
    let rule: FilterRule?
    let feeds: [Feed]
    let onSave: (String, Bool, FilterAction, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(FeedStore.self) private var store

    @State private var keyword = ""
    @State private var wholeWord = true
    @State private var action: FilterAction = .hide
    @State private var feedURL: String?

    /// Aperçu : nombre d'articles actuels dont le titre correspond
    private var previewCount: Int {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return 0 }
        return store.previewMatchCount(
            CompiledFilter(keyword: trimmed, wholeWord: wholeWord, action: action, feedURL: feedURL))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(rule == nil ? String(localized: "Nouvelle règle") : String(localized: "Modifier la règle"))
                .font(.title2.bold())

            Form {
                TextField("Mot-clé", text: $keyword, prompt: Text("ex. : Bitcoin"))
                Toggle("Mot entier uniquement", isOn: $wholeWord)
                Picker("Flux concernés", selection: $feedURL) {
                    Text("Tous les flux").tag(String?.none)
                    Divider()
                    ForEach(feeds) { feed in
                        Text(feed.displayTitle).tag(Optional(feed.url))
                    }
                }
                Picker("Action", selection: $action) {
                    ForEach(FilterAction.allCases) { a in
                        Text(a.label).tag(a)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            .formStyle(.columns)

            Text(previewCount == 0
                 ? String(localized: "Aucun article actuel ne correspond.")
                 : String(localized: "\(previewCount) articles actuels correspondent."))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(rule == nil ? String(localized: "Ajouter") : String(localized: "Enregistrer")) {
                    onSave(keyword, wholeWord, action, feedURL)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            guard let rule else { return }
            keyword = rule.keyword
            wholeWord = rule.wholeWord
            action = rule.filterAction
            feedURL = rule.feedURL
        }
    }
}
