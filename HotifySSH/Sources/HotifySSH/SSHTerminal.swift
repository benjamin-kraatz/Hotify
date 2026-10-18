import Foundation
import NIOCore
import NIOSSH

/// What a terminal session sends back.
public enum SSHTerminalOutput: Sendable {
    case bytes([UInt8])
    /// The command ended with this status. The stream finishes after it.
    case exited(Int)
}

/// A command running in a terminal on the server. Send it keystrokes, tell it the window's size, read its output.
public final class SSHTerminal: Sendable {
    private let channel: Channel
    /// Finishes when the session closes, on the server's side or ours.
    public let output: AsyncStream<SSHTerminalOutput>

    init(channel: Channel, events: AsyncStream<SessionEvent>) {
        self.channel = channel
        output = AsyncStream { continuation in
            let task = Task {
                for await event in events {
                    switch event {
                    case .output(let bytes, _):
                        continuation.yield(.bytes(bytes))
                    case .exit(let status):
                        continuation.yield(.exited(status))
                    case .rejected:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func send(_ bytes: [UInt8]) {
        var buffer = channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer)), promise: nil)
    }

    public func resize(columns: Int, rows: Int) {
        let request = SSHChannelRequestEvent.WindowChangeRequest(
            terminalCharacterWidth: max(columns, 1),
            terminalRowHeight: max(rows, 1),
            terminalPixelWidth: 0,
            terminalPixelHeight: 0
        )
        channel.triggerUserOutboundEvent(request, promise: nil)
    }

    public func close() {
        channel.close(promise: nil)
    }
}
