import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// Handles SSH port forwarding using SwiftNIO SSH DirectTCP/IP channels
final class SSHPortForwardingHandler {
    private let sshHandler: NIOSSHHandler
    private let eventLoop: EventLoop
    private let localPort: Int
    private let remoteHost: String
    private let remotePort: Int
    
    private var tcpServerChannel: Channel?
    private var isActive = false
    
    init(sshHandler: NIOSSHHandler, eventLoop: EventLoop, localPort: Int, remoteHost: String, remotePort: Int) {
        self.sshHandler = sshHandler
        self.eventLoop = eventLoop
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        print("🚇 SSHPortForwardingHandler initialized for localhost:\(localPort) → \(remoteHost):\(remotePort)")
    }
    
    /// Start the port forwarding by creating a local TCP server
    func start() -> EventLoopFuture<Void> {
        print("🚇 Starting port forwarding on localhost:\(localPort)")
        
        let bootstrap = ServerBootstrap(group: eventLoop)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                print("👋 New local connection on port \(self.localPort)")
                return self.handleNewLocalConnection(channel)
            }
        
        return bootstrap.bind(host: "127.0.0.1", port: localPort)
            .flatMap { serverChannel in
                self.tcpServerChannel = serverChannel
                self.isActive = true
                print("✅ TCP server listening on localhost:\(self.localPort)")
                return self.eventLoop.makeSucceededVoidFuture()
            }
            .flatMapError { error in
                print("❌ Failed to bind to localhost:\(self.localPort): \(error)")
                return self.eventLoop.makeFailedFuture(error)
            }
    }
    
    /// Handle a new local TCP connection by creating SSH DirectTCP/IP channel
    private func handleNewLocalConnection(_ localChannel: Channel) -> EventLoopFuture<Void> {
        print("🔗 Creating DirectTCP/IP channel for new connection")
        
        let promise = localChannel.eventLoop.makePromise(of: Channel.self)
        
        // Get originator address for the DirectTCP/IP request
        let originatorAddress: SocketAddress
        if let localAddr = localChannel.localAddress {
            originatorAddress = localAddr
        } else {
            do {
                originatorAddress = try SocketAddress(ipAddress: "127.0.0.1", port: 0)
            } catch {
                print("⚠️ Failed to create default address: \(error)")
                return localChannel.close()
            }
        }
        
        // Create DirectTCP/IP channel
        let channelType = SSHChannelType.directTCPIP(
            SSHChannelType.DirectTCPIP(
                targetHost: remoteHost,
                targetPort: remotePort,
                originatorAddress: originatorAddress
            )
        )
        
        // Create the SSH channel with proper child channel initialization
        sshHandler.createChannel(promise, channelType: channelType) { sshChannel, channelType in
            print("✅ DirectTCP/IP channel created")
            
            // Verify this is a DirectTCP/IP channel
            guard case .directTCPIP = channelType else {
                print("❌ Expected DirectTCP/IP channel but got \(channelType)")
                return sshChannel.eventLoop.makeFailedFuture(SSHTunnelError.invalidChannelType)
            }
            
            // Add the SSH data unwrapping handler to the channel pipeline
            return sshChannel.pipeline.addHandler(SSHChannelDataUnwrappingHandler())
                .flatMap {
                    // Enable half-closure support for SSH channels (required for proper operation)
                    return sshChannel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true)
                }
                .flatMap {
                    // Use standard NIO channel proxying
                    return self.setupStandardChannelProxy(localChannel: localChannel, sshChannel: sshChannel)
                }
        }
        
        return promise.futureResult.map { _ in
            print("✅ Port forwarding established for connection")
        }.flatMapError { error in
            print("❌ Failed to create DirectTCP/IP channel: \(error)")
            return localChannel.close()
        }
    }
    
    /// Set up standard channel proxying between local TCP and SSH channels
    private func setupStandardChannelProxy(localChannel: Channel, sshChannel: Channel) -> EventLoopFuture<Void> {
        print("🔄 Setting up standard ByteBuffer channel proxy")
        
        // With the SSHChannelDataUnwrappingHandler in place, the SSH channel now handles ByteBuffer
        // Local TCP → SSH: ByteBuffer → ByteBuffer (via SSHChannelDataUnwrappingHandler)
        // SSH → Local TCP: ByteBuffer → ByteBuffer (via SSHChannelDataUnwrappingHandler)
        return localChannel.pipeline.addHandler(ByteBufferProxy(target: sshChannel))
            .and(sshChannel.pipeline.addHandler(ByteBufferProxy(target: localChannel)))
            .map { _ in
                // Handle channel closure
                localChannel.closeFuture.whenComplete { _ in
                    print("📪 Local channel closed, closing SSH channel")
                    _ = sshChannel.close()
                }
                
                sshChannel.closeFuture.whenComplete { _ in
                    print("📪 SSH channel closed, closing local channel")
                    _ = localChannel.close()
                }
            }
    }
    
    /// Stop the port forwarding
    func stop() -> EventLoopFuture<Void> {
        print("🛑 Stopping port forwarding on localhost:\(localPort)")
        isActive = false
        
        guard let serverChannel = tcpServerChannel else {
            return eventLoop.makeSucceededVoidFuture()
        }
        
        return serverChannel.close().map {
            self.tcpServerChannel = nil
            print("✅ Port forwarding stopped")
        }
    }
}

/// Simple proxy handler for ByteBuffer data forwarding
private final class ByteBufferProxy: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    
    weak var target: Channel?
    
    init(target: Channel) {
        self.target = target
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        
        guard let target = self.target else {
            print("⚠️ No target channel for ByteBuffer proxy")
            context.close(promise: nil)
            return
        }
        
        // Forward ByteBuffer directly to target channel
        target.writeAndFlush(buffer, promise: nil)
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        target?.close(promise: nil)
        target = nil
        context.fireChannelInactive()
    }
}