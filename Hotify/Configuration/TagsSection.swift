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

    /// The tags as chips on one row of the form, wrapping when they run out of room. The confirmation stays on this
    /// row so the rest of the form keeps its rows.
    @ViewBuilder
    private var assignedTags: some View {
        if !shown.isEmpty {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(shown) { tag in
                    TagChip(name: tag.name, canRemove: !model.isBusy && !tag.uuid.isEmpty) {
                        model.pendingRemoval = tag
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.vertical, 2)
            .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.3), value: shown.map(\.id))
            .modifier(RemovalConfirmation(model: model))
        }
    }
}

/// One tag on the resource, with the button that takes it off.
private struct TagChip: View {
    var name: String
    var canRemove: Bool
    var onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "number")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.ember)
            Text(name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Button("Remove", systemImage: "xmark.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.callout)
                .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .disabled(!canRemove)
                .help("Remove \(name)")
                .accessibilityLabel("Remove \(name)")
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(.ember.opacity(isHovered ? 0.16 : 0.1), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(.ember.opacity(0.18), lineWidth: 1)
        }
        .fixedSize()
        .onHover { isHovered = $0 }
        .animation(.snappy(duration: 0.15), value: isHovered)
    }
}

/// Asks before a tag comes off. The team keeps the tag.
private struct RemovalConfirmation: ViewModifier {
    @Bindable var model: ResourceTagsModel

    func body(content: Content) -> some View {
        content
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
