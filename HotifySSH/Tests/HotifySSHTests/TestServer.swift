import CryptoKit
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

@testable import HotifySSH

/// An SSH server inside the test process. It takes any key, echoes each command back with its exit status, and
/// answers probes, or keeps quiet about them when told to.
final class TestServer: Sendable {
    let hostKey: SSHHostKey
    let port: Int
    private let channel: Channel

    /// A terminal's command echoes as `<columns>x<rows> <command>`, and a plain command as itself. Both end with
    /// exit status 7.
    static let exitStatus = 7

    private init(hostKey: SSHHostKey, port: Int, channel: Channel) {
        self.hostKey = hostKey
        self.port = port
        self.channel = channel
    }

    static func start(answersProbes: Bool = true) async throws -> TestServer {
        let key = Curve25519.Signing.PrivateKey()
        let hostKey = NIOSSHPrivateKey(ed25519Key: key)
        let probes: any GlobalRequestDelegate & Sendable = answersProbes ? AnsweringProbes() : SwallowingProbes()
        let bootstrap = ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let configuration = SSHServerConfiguration(
                        hostKeys: [hostKey],
                        userAuthDelegate: AcceptingEveryone(),
                        globalRequestDelegate: probes
                    )
                    try channel.pipeline.syncOperations.addHandler(
                        NIOSSHHandler(
                            role: .server(configuration),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: { child, _ in
                                child.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                                    .flatMapThrowing {
                                        try child.pipeline.syncOperations.addHandler(EchoSession())
                                    }
                            }
                        )
                    )
                }
            }
        let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        return TestServer(
            hostKey: SSHHostKey(hostKey.publicKey),
            port: channel.localAddress!.port!,
            channel: channel
        )
    }

    func stop() async {
        try? await channel.close()
    }
}

/// What the test server says to any forwarding request.
private struct Refused: Error {}

/// Signs anyone in with any key.
private final class AcceptingEveryone: NIOSSHServerUserAuthenticationDelegate {
    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .publicKey }

    func requestReceived(
        request: NIOSSHUserAuthenticationRequest,
        responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>
    ) {
        responsePromise.succeed(.success)
    }
}

/// Turns every forwarding request down, which is the answer `probe` expects from a real server.
private struct AnsweringProbes: GlobalRequestDelegate {
    func tcpForwardingRequest(
        _ request: GlobalRequest.TCPForwardingRequest,
        handler: NIOSSHHandler,
        promise: EventLoopPromise<GlobalRequest.TCPForwardingResponse>
    ) {
        promise.fail(Refused())
    }
}

/// Never answers, like a server whose network went away under it.
private final class SwallowingProbes: GlobalRequestDelegate, @unchecked Sendable {
    private var held: [EventLoopPromise<GlobalRequest.TCPForwardingResponse>] = []

    func tcpForwardingRequest(
        _ request: GlobalRequest.TCPForwardingRequest,
        handler: NIOSSHHandler,
        promise: EventLoopPromise<GlobalRequest.TCPForwardingResponse>
    ) {
        held.append(promise)
    }

    deinit {
        for promise in held {
            promise.fail(Refused())
        }
    }
}

/// Echoes the command it was asked to run, with the terminal size when it got one, then exits with status 7.
private final class EchoSession: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundOut = SSHChannelData

    private var size: String?

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let request as SSHChannelRequestEvent.PseudoTerminalRequest:
            size = "\(request.terminalCharacterWidth)x\(request.terminalRowHeight)"
            if request.wantReply {
                context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }
        case let request as SSHChannelRequestEvent.ExecRequest:
            if request.wantReply {
                context.triggerUserOutboundEvent(ChannelSuccessEvent(), promise: nil)
            }
            let line = (size.map { $0 + " " } ?? "") + request.command
            var buffer = context.channel.allocator.buffer(capacity: line.utf8.count)
            buffer.writeString(line)
            context.writeAndFlush(
                wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: nil)
            context.triggerUserOutboundEvent(
                SSHChannelRequestEvent.ExitStatus(exitStatus: TestServer.exitStatus), promise: nil)
            context.close(promise: nil)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {}
}
