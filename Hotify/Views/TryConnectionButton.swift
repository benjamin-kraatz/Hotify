//
//  TryConnectionButon.swift
//  Hotify
//
//  Created by Benjamin Kraatz on 29.09.26.
//

import SwiftUI

struct TryConnectionButton: View {
    /// Bumps when the URL or token changes, which cancels an attempt in progress.
    var resetID: Int = 0
    var action: () async -> Void = {}

    @State private var isLoading = false
    @State private var loadID = 0
    @State private var attempt: Task<Void, Never>?

    var body: some View {
        styledContent
            .onChange(of: resetID) { _, _ in
                cancelAttempt()
            }
    }

    @ViewBuilder
    private var styledContent: some View {
        if #available(iOS 26, *) {
            content
                .buttonStyle(.glassProminent)
        } else {
            content
        }
    }

    private var content: some View {
        Button {
            guard !isLoading else { return }
            isLoading = true
            loadID += 1
            let current = loadID
            attempt?.cancel()
            attempt = Task {
                await action()
                guard current == loadID else { return }
                isLoading = false
                attempt = nil
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
        .accessibilityLabel(isLoading ? "Connecting" : "Try connection")
    }

    private func cancelAttempt() {
        loadID += 1
        attempt?.cancel()
        attempt = nil
        isLoading = false
    }
}

#Preview {
    TryConnectionButton {
        try? await Task.sleep(for: .seconds(2))
    }
}
