import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// What a command printed, and how it ended.
public struct SSHCommandResult: Sendable {
    public var output: String
    public var errorOutput: String
    /// `nil` when the server closed the channel without reporting one.
    public var exitStatus: Int?
}

/// One signed-in SSH connection to a server. Runs commands and opens terminals over it, then closes.
public final class SSHConnection: Sendable {
    private let channel: Channel

    private init(channel: Channel) {
        self.channel = channel
    }

    /// Connects, checks the host key, and signs in with `identity`.
    ///
    /// With no `trusted` key, every host key fails with `SSHConnectionError.hostKeyUnknown`, which carries the
    /// presented key so the caller can ask whether to trust it and connect again.
    public static func open(
        host: String,
        port: Int,
        user: String,
        identity: SSHIdentity,
        trusting trusted: SSHHostKey?,
        timeout: Duration = .seconds(15)
    ) async throws -> SSHConnection {
        let group = MultiThreadedEventLoopGroup.singleton
        let ready = group.next().makePromise(of: Void.self)
        let privateKey = identity.privateKey
        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(TimeAmount(timeout))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let configuration = SSHClientConfiguration(
                        userAuthDelegate: KeyOffer(user: user, key: privateKey),
                        serverAuthDelegate: HostKeyCheck(trusted: trusted)
                    )
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSHHandler(
                            role: .client(configuration),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        )
                    )
                    try channel.pipeline.syncOperations.addHandler(ReadinessHandler(ready: ready))
                }
            }

        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            ready.fail(SSHConnectionError.closed)
            throw Self.reason(error)
        }

        let deadline = channel.eventLoop.scheduleTask(in: TimeAmount(timeout)) {
            ready.fail(SSHConnectionError.timedOut)
        }
        defer { deadline.cancel() }
        do {
            try await ready.futureResult.get()
        } catch {
            try? await channel.close()
            throw Self.reason(error)
        }
        return SSHConnection(channel: channel)
    }

    /// Runs a command without a terminal and collects what it prints.
    public func run(_ command: String) async throws -> SSHCommandResult {
        let (session, events) = try await openSession()
        try await session.triggerUserOutboundEvent(
            SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
        )
        .get()
        var output: [UInt8] = []
        var errorOutput: [UInt8] = []
        var exitStatus: Int?
        for await event in events {
            switch event {
            case .output(let bytes, let isError):
                if isError {
                    errorOutput += bytes
                } else {
                    output += bytes
                }
            case .exit(let status):
                exitStatus = status
            case .rejected:
                throw SSHConnectionError.channelRejected
            }
        }
        return SSHCommandResult(
            output: String(decoding: output, as: UTF8.self),
            errorOutput: String(decoding: errorOutput, as: UTF8.self),
            exitStatus: exitStatus
        )
    }

    /// Runs a command in a terminal of the given size, such as a shell in a container.
    public func openTerminal(_ command: String, columns: Int, rows: Int) async throws -> SSHTerminal {
        let (session, events) = try await openSession()
        let terminal = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: false,
            term: "xterm-256color",
            terminalCharacterWidth: max(columns, 1),
            terminalRowHeight: max(rows, 1),
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: SSHTerminalModes([:])
        )
        try await session.triggerUserOutboundEvent(terminal).get()
        try await session.triggerUserOutboundEvent(
            SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true)
        )
        .get()
        return SSHTerminal(channel: session, events: events)
    }

    public func close() async {
        try? await channel.close()
    }

    /// Ends when the connection drops, for whatever reason.
    public func waitUntilClosed() async {
        try? await channel.closeFuture.get()
    }

    private func openSession() async throws -> (Channel, AsyncStream<SessionEvent>) {
        let (events, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        let channel = self.channel
        let session = try await channel.eventLoop.flatSubmit { () -> EventLoopFuture<Channel> in
            let promise = channel.eventLoop.makePromise(of: Channel.self)
            do {
                let ssh = try channel.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
                ssh.createChannel(promise, channelType: .session) { child, type in
                    guard case .session = type else {
                        return child.eventLoop.makeFailedFuture(SSHConnectionError.channelRejected)
                    }
                    return child.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).flatMapThrowing {
                        try child.pipeline.syncOperations.addHandler(SessionHandler(continuation: continuation))
                    }
                }
            } catch {
                promise.fail(error)
            }
            return promise.futureResult
        }.get()
        return (session, events)
    }

    /// Keeps the connection's own errors, and turns NIO's into the cases a caller can act on.
    private static func reason(_ error: Error) -> SSHConnectionError {
        if let error = error as? SSHConnectionError {
            return error
        }
        if error is ChannelError, case .connectTimeout = error as? ChannelError {
            return .timedOut
        }
        if let error = error as? NIOSSHError, error.type == .channelSetupRejected {
            return .channelRejected
        }
        return .unreachable(String(describing: error))
    }
}

extension TimeAmount {
    fileprivate init(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        self = .nanoseconds(seconds * 1_000_000_000 + attoseconds / 1_000_000_000)
    }
}
