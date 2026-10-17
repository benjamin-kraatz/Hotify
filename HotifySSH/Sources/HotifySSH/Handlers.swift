import Foundation
import NIOCore
import NIOSSH

/// Offers the one key, once. A second call means the server turned it down.
final class KeyOffer: NIOSSHClientUserAuthenticationDelegate {
    private let user: String
    private let key: NIOSSHPrivateKey
    private var offered = false

    init(user: String, key: NIOSSHPrivateKey) {
        self.user = user
        self.key = key
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !offered, availableMethods.contains(.publicKey) else {
            nextChallengePromise.fail(SSHConnectionError.authenticationFailed)
            return
        }
        offered = true
        nextChallengePromise.succeed(
            NIOSSHUserAuthenticationOffer(username: user, serviceName: "", offer: .privateKey(.init(privateKey: key)))
        )
    }
}

/// Accepts only the key trusted before. With none, it reports the presented key so a person can decide.
final class HostKeyCheck: NIOSSHClientServerAuthenticationDelegate {
    private let trusted: SSHHostKey?

    init(trusted: SSHHostKey?) {
        self.trusted = trusted
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = SSHHostKey(hostKey)
        switch trusted {
        case presented?:
            validationCompletePromise.succeed(())
        case let trusted?:
            validationCompletePromise.fail(SSHConnectionError.hostKeyChanged(presented: presented, trusted: trusted))
        case nil:
            validationCompletePromise.fail(SSHConnectionError.hostKeyUnknown(presented))
        }
    }
}

/// Sits after the SSH handler and settles `ready` once: when sign-in succeeds, or with the first error.
final class ReadinessHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    private let ready: EventLoopPromise<Void>
    private var isSettled = false

    init(ready: EventLoopPromise<Void>) {
        self.ready = ready
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is UserAuthSuccessEvent {
            settle(.success(()))
        }
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        settle(.failure(error))
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        settle(.failure(SSHConnectionError.closed))
        context.fireChannelInactive()
    }

    private func settle(_ result: Result<Void, Error>) {
        guard !isSettled else { return }
        isSettled = true
        ready.completeWith(result)
    }
}

/// What a session channel reports, in order.
enum SessionEvent: Sendable {
    case output([UInt8], isError: Bool)
    case exit(Int)
    /// The server refused the request.
    case rejected
}

/// Turns one session channel's data and requests into `SessionEvent`s, and ends the stream when the channel closes.
final class SessionHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let continuation: AsyncStream<SessionEvent>.Continuation

    init(continuation: AsyncStream<SessionEvent>.Continuation) {
        self.continuation = continuation
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = message.data else { return }
        continuation.yield(.output(Array(buffer.readableBytesView), isError: message.type == .stdErr))
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let status as SSHChannelRequestEvent.ExitStatus:
            continuation.yield(.exit(status.exitStatus))
        case is ChannelFailureEvent:
            continuation.yield(.rejected)
            context.close(promise: nil)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        continuation.finish()
        context.fireChannelInactive()
    }
}
