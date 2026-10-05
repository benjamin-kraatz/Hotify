import CoolifyAPI
import SwiftUI

/// A server's Docker networks: the name and network of each, and adding, renaming, or deleting one.
struct DestinationSection: View {
    var serverID: String
    var client: CoolifyClient?

    @State private var model: DestinationModel
    @State private var name = ""
    @State private var network = ""
    @State private var renaming: Destination?
    @State private var deleting: Destination?
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(serverID: String, client: CoolifyClient? = nil, destinations: [Destination] = []) {
        self.serverID = serverID
        self.client = client
        _model = State(
            initialValue: DestinationModel(destinations: destinations, hasLoaded: !destinations.isEmpty)
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNetwork: String {
        network.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var networkProblem: String? {
        guard !trimmedNetwork.isEmpty else { return nil }
        return DestinationNetworkRule.problem(trimmedNetwork)
    }

    private var canAdd: Bool {
        client != nil && !model.isSaving && networkProblem == nil && DestinationNetworkRule.isValid(trimmedNetwork)
            && trimmedName.count <= 255
    }

    var body: some View {
        Section {
            destinations
            if let notice = model.notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.ember)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
                    .textSelection(.enabled)
                if client != nil, !model.hasLoaded {
                    Button("Try Again") {
                        Task { await reload() }
                    }
                    .disabled(model.isLoading || model.isSaving)
                }
            }
            TextField("Name", text: $name, prompt: Text("Optional"))
                .autocorrectionDisabled()
                .disabled(client == nil || model.isSaving)
            TextField("Network", text: $network, prompt: Text("coolify"))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .disabled(client == nil || model.isSaving)
            if let networkProblem {
                Label(networkProblem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.glow)
            }
            Button {
                Task { await add() }
            } label: {
                Label(model.isAdding ? "Adding…" : "Add Destination", systemImage: "plus")
            }
            .glassButton(prominent: canAdd)
            .disabled(!canAdd)
            .help("Creates a Docker network resources can deploy into.")
        } header: {
            Text("Destinations")
        } footer: {
            Text(
                "Resources deploy into this Docker network. The network cannot be changed. "
                    + "Coolify refuses to delete a destination a resource still uses."
            )
        }
        .animation(reduceMotion ? nil : .snappy, value: model.destinations.map(\.id))
        .animation(reduceMotion ? nil : .snappy, value: model.error)
        .animation(reduceMotion ? nil : .snappy, value: model.notice)
        .onChange(of: name) { _, _ in model.error = nil }
        .onChange(of: network) { _, _ in model.error = nil }
        .task(id: serverID) { await reload() }
        .sheet(item: $renaming) { destination in
            DestinationRenameSheet(destination: destination) { newName in
                guard let client else { return }
                try await model.rename(destination, to: newName, client: client, serverID: serverID)
            }
        }
        .confirmationDialog(
            deleting.map { "Delete \(displayName($0))?" } ?? "",
            isPresented: Binding(
                get: { deleting != nil },
                set: { isPresented in
                    if !isPresented { deleting = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: deleting
        ) { destination in
            Button("Delete", role: .destructive) {
                Task { await remove(destination) }
            }
        } message: { _ in
            Text("Coolify refuses to delete a destination a resource still uses.")
        }
    }

    @ViewBuilder
    private var destinations: some View {
        if client != nil, !model.hasLoaded, model.error == nil {
            HStack {
                Spacer()
                ProgressView("Loading destinations")
                Spacer()
            }
        } else if !model.destinations.isEmpty {
            ForEach(model.destinations) { destination in
                destinationRow(destination)
            }
        } else if model.error == nil || model.hasLoaded {
            Text("No destinations on this server.")
                .foregroundStyle(.secondary)
        }
    }

    private func destinationRow(_ destination: Destination) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.between.dots")
                .foregroundStyle(.ember)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(destination))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                if let network = destination.network, !network.isEmpty {
                    Text(network)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.core)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            Button("Rename", systemImage: "pencil") {
                renaming = destination
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.ember)
            .disabled(client == nil || model.isSaving)
            .help("Rename \(displayName(destination)). The network cannot be changed.")
            .accessibilityLabel("Rename \(displayName(destination))")
            Button("Delete", systemImage: "trash") {
                deleting = destination
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(client == nil || model.isSaving)
            .help("Delete \(displayName(destination))")
            .accessibilityLabel("Delete \(displayName(destination))")
        }
    }

    private func displayName(_ destination: Destination) -> String {
        let trimmed = destination.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return destination.network ?? "Destination"
    }

    private func reload() async {
        guard let client, !model.isSaving else { return }
        await model.load(client: client, serverID: serverID)
    }

    private func add() async {
        guard let client, canAdd else { return }
        do {
            try await model.create(
                DestinationDraft(name: trimmedName.isEmpty ? nil : trimmedName, network: trimmedNetwork),
                client: client,
                serverID: serverID
            )
            name = ""
            network = ""
        } catch is CancellationError {
            return
        } catch {
            model.error = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    private func remove(_ destination: Destination) async {
        guard let client else { return }
        await model.delete(destination, client: client, serverID: serverID)
    }
}

/// What this section has loaded, and the write it is waiting on.
@MainActor
@Observable
private final class DestinationModel {
    var destinations: [Destination]
    var error: String?
    var notice: String?
    var hasLoaded: Bool
    var isLoading = false
    var isAdding = false
    var isSaving = false
    /// A newer load wins when two overlap, so a refresh after a write is not replaced by the one already in flight.
    private var loadGeneration = 0

    init(destinations: [Destination] = [], hasLoaded: Bool = false) {
        self.destinations = destinations
        self.hasLoaded = hasLoaded
    }

    func load(client: CoolifyClient, serverID: String) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration { isLoading = false }
        }
        do {
            let loaded = try await client.destinations(onServer: serverID)
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            destinations = loaded.sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order == .orderedSame { return lhs.uuid < rhs.uuid }
                return order == .orderedAscending
            }
            hasLoaded = true
            error = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            self.error = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }

    func create(_ draft: DestinationDraft, client: CoolifyClient, serverID: String) async throws {
        isAdding = true
        isSaving = true
        defer {
            isAdding = false
            isSaving = false
        }
        _ = try await client.createDestination(draft, onServer: serverID)
        notice = "Destination added."
        error = nil
        await load(client: client, serverID: serverID)
    }

    func rename(_ destination: Destination, to name: String, client: CoolifyClient, serverID: String) async throws {
        isSaving = true
        defer { isSaving = false }
        _ = try await client.renameDestination(destination.uuid, name: name)
        notice = "Destination renamed."
        error = nil
        await load(client: client, serverID: serverID)
    }

    func delete(_ destination: Destination, client: CoolifyClient, serverID: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await client.deleteDestination(destination.uuid)
            notice = "Destination deleted."
            error = nil
            await load(client: client, serverID: serverID)
        } catch is CancellationError {
            return
        } catch {
            self.error = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }
}

/// Coolify's rule for a destination network. A value outside it is a 422.
private enum DestinationNetworkRule {
    static let pattern = #"^[a-zA-Z0-9][a-zA-Z0-9._-]*$"#

    static func isValid(_ value: String) -> Bool {
        problem(value) == nil && !value.isEmpty
    }

    static func problem(_ value: String) -> String? {
        if value.count > 255 {
            return "A network name can be 255 characters."
        }
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            return "Use letters, numbers, and . _ -, starting with a letter or number."
        }
        return nil
    }
}

/// Renames a destination. The network is shown and cannot be edited.
private struct DestinationRenameSheet: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss

    var destination: Destination
    var onSave: (String) async throws -> Void

    @State private var name: String
    @State private var isSaving = false
    @State private var saveError: String?
    @FocusState private var isNameFocused: Bool
    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(destination: Destination, onSave: @escaping (String) async throws -> Void) {
        self.destination = destination
        self.onSave = onSave
        _name = State(initialValue: destination.name)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 255 && trimmedName != destination.name && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Name"))
                        .autocorrectionDisabled()
                        .focused($isNameFocused)
                    LabeledContent("Network") {
                        Text(destination.network ?? "Unknown")
                            .font(.body.monospaced())
                            .foregroundStyle(.core)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("The network cannot be changed.")
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.glow)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Rename Destination")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .onAppear { isNameFocused = true }
            .onChange(of: name) { _, _ in saveError = nil }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 440, minHeight: 240)
        #endif
        .interactiveDismissDisabled(isSaving)
        .animation(reduceMotion ? nil : .snappy, value: saveError)
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(trimmedName)
            dismiss()
        } catch is CancellationError {
            return
        } catch {
            saveError = (error as? CoolifyError)?.summary ?? error.localizedDescription
        }
    }
}

#Preview("Destinations") {
    NavigationStack {
        Form {
            DestinationSection(
                serverID: "localhost",
                destinations: [
                    Destination(uuid: "d1", name: "coolify", network: "coolify"),
                    Destination(uuid: "d2", name: "apps", network: "hotify"),
                ]
            )
        }
    }
    .frame(width: 560, height: 480)
}

#Preview("Rename") {
    DestinationRenameSheet(
        destination: Destination(uuid: "d1", name: "coolify", network: "coolify"),
        onSave: { _ in }
    )
}
