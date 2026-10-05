import CoolifyAPI
import SwiftUI

/// The tags on this resource: the ones it has, a pick from the team's tags, and a new name of at least 2 characters.
struct TagsSection: View {
    @Bindable var model: ResourceTagsModel

    @SwiftUI.Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: [Tag] {
        model.assigned.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Section {
            if model.isLoading, model.assigned.isEmpty, model.team.isEmpty, model.error == nil {
                ProgressView("Loading tags")
            } else if shown.isEmpty {
                Text("No tags yet.")
                    .foregroundStyle(.secondary)
            }
            assignedTags
            if !model.available.isEmpty {
                Menu("Add an existing tag", systemImage: "tag") {
                    ForEach(model.available) { tag in
                        Button(tag.name) {
                            Task { await model.add(name: tag.name) }
                        }
                    }
                }
                .disabled(model.isBusy)
            }
            SettingField(title: "New tag", text: $model.draft, prompt: "At least 2 characters")
            Button("Add Tag") {
                Task { await model.addDraft() }
            }
            .disabled(!model.canAddDraft)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.glow)
                    .font(.callout)
                Button("Try Again") {
                    Task { await model.load() }
                }
                .disabled(model.isBusy)
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("A tag is shared by the team. A new name needs 2 characters and is created, then added here.")
        }
    }

    /// Each tag is its own form row. The confirmation stays on this list so the other rows remain rows.
    private var assignedTags: some View {
        ForEach(shown) { tag in
            HStack(spacing: 8) {
                Label(tag.name, systemImage: "tag")
                Spacer(minLength: 8)
                Button("Remove", systemImage: "minus.circle.fill") {
                    model.pendingRemoval = tag
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.isBusy || tag.uuid.isEmpty)
                .help("Remove \(tag.name)")
                .accessibilityLabel("Remove \(tag.name)")
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: shown.map(\.id))
        .confirmationDialog(
            model.pendingRemoval.map { "Remove \($0.name)?" } ?? "",
            isPresented: Binding(
                get: { model.pendingRemoval != nil },
                set: { isPresented in
                    if !isPresented { model.pendingRemoval = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: model.pendingRemoval
        ) { tag in
            Button("Remove", role: .destructive) {
                Task { await model.remove(tag) }
            }
        } message: { tag in
            Text("This takes \(tag.name) off this resource. The team keeps the tag.")
        }
    }
}

#Preview("Tags") {
    Form {
        TagsSection(
            model: ResourceTagsModel(
                assigned: [
                    Tag(uuid: "1", name: "prod"),
                    Tag(uuid: "2", name: "web"),
                ],
                team: [
                    Tag(uuid: "1", name: "prod"),
                    Tag(uuid: "2", name: "web"),
                    Tag(uuid: "3", name: "staging"),
                ]
            )
        )
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 420)
}

#Preview("No tags") {
    Form {
        TagsSection(model: ResourceTagsModel())
    }
    .formStyle(.grouped)
    .frame(width: 480, height: 320)
}
