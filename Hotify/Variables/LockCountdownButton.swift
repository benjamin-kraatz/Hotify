import SwiftUI

/// Counts down to when values lock again, and locks them now on a click. Shows nothing while they are locked,
/// or when the lock is switched off.
struct LockCountdownButton: View {
    var lock: VariableLock

    var body: some View {
        if lock.isRequired, lock.isOpen, let until = lock.unlockedUntil {
            Button {
                lock.lock()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "lock.open.fill")
                        .foregroundStyle(.ember)
                    Text(timerInterval: Date.now...max(until, .now), countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Values lock again at \(until.formatted(date: .omitted, time: .shortened)). Click to lock now.")
            .accessibilityLabel("Lock values")
            .transition(.opacity)
        }
    }
}

#Preview {
    LockCountdownButton(lock: VariableLock(isRequired: true))
        .padding()
}
