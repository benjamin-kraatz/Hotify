//
//  TryConnectionButon.swift
//  Hotify
//
//  Created by Benjamin Kraatz on 29.09.26.
//

import SwiftUI

struct TryConnectionButton: View {
    var action: () async -> Void = {}

    @State private var isLoading = false

    var body: some View {
        if #available(iOS 26, *) {
            content
                .buttonStyle(.glassProminent)
        } else {
            content
        }
    }

    private var content: some View {
        Button {
            Task {
                isLoading = true
                await action()
                isLoading = false
            }
        } label: {
            HStack {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        Image(systemName: "network")
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .frame(width: 16, height: 16)

                Text("Try connection")
            }
            .animation(.easeInOut(duration: 0.2), value: isLoading)
        }
        .disabled(isLoading)
    }
}

#Preview {
    TryConnectionButton {
        try? await Task.sleep(for: .seconds(2))
    }
}
