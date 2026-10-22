import SwiftUI

struct AddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedStore.self) private var store

    @State private var address = ""
    @State private var working = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty && !working
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ajouter un flux")
                .font(.title2.bold())
            Text("Colle l'adresse du flux RSS ou Atom, ou simplement celle du site : le flux sera détecté automatiquement.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("https://exemple.com/feed.xml", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canSubmit { add() } }
                .disabled(working)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    add()
                } label: {
                    if working {
                        ProgressView().controlSize(.small).frame(width: 50)
                    } else {
                        Text("Ajouter").frame(width: 50)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func add() {
        Task {
            working = true
            errorMessage = nil
            do {
                try await store.addFeed(urlString: address)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            working = false
        }
    }
}
