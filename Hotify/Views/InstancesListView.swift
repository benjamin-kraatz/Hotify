//
//  InstancesListView.swift
//  Hotify
//
//  Created by Benjamin Kraatz on 29.09.26.
//

import CoolifyAPI
import Foundation
import SwiftUI

struct InstancesListView: View {
    @SwiftUI.Environment(InstanceStore.self) private var store
    @Binding var isAdding: Bool
    @Binding var editing: CoolifyInstance?

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedID) {
            ForEach(store.instances) { instance in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instance.name)
                            #if os(macOS)
                        .font(.body)
                            #else
                        .font(.headline)
                            #endif
                        Text(instance.baseURL.absoluteString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    #if os(iOS)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    #endif
                }
                .tag(instance.id)
                .contextMenu {
                    Button("Edit", systemImage: "pencil.line") {
                        editing = instance
                    }
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        store.remove(instance)
                    }
                }
                #if os(iOS)
                .swipeActions(edge: .leading) {
                    Button("Edit", systemImage: "pencil") {
                        editing = instance
                    }
                    .tint(.blue)
                }
                .swipeActions {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        store.remove(instance)
                    }
                }
                #endif
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #endif
        .navigationTitle("Instances")
        .toolbar {
            if let selected = store.selected {
                Button("Edit", systemImage: "pencil.line") { editing = selected }
            }
            Button("Add", systemImage: "plus") { isAdding = true }
        }
    }
}

#Preview {
    let namesAndURLs = [
        ("Production", "https://coolify.example.com"),
        ("Staging", "https://staging.example.com"),
        ("Development", "https://dev.example.com"),
    ]
    let instances = namesAndURLs.compactMap { name, address in
        URL(string: address).map { CoolifyInstance(name: name, baseURL: $0) }
    }

    InstancesListView(isAdding: .constant(false), editing: .constant(nil))
        .environment(InstanceStore(instances: instances))
}
