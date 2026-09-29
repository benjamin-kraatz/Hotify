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
                    VStack(alignment: .leading) {
                        Text(instance.name)
                            .font(.headline)
                        Text(instance.baseURL.absoluteString)
                            .font(.subheadline)
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
                .swipeActions(edge: .leading) {
                    Button("Edit") {
                        editing = instance
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        store.remove(instance)
                    }
                }
            }
        }
        .navigationTitle("Instances")
        .toolbar {
            if let selected = store.selected {
                Button("Edit") { editing = selected }
            }
            Button("Add") { isAdding = true }
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
