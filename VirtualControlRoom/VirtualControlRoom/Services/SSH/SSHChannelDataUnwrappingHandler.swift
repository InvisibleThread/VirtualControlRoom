import Foundation
import NIOCore
import NIOSSH

/// Handler that converts between SSHChannelData and ByteBuffer for DirectTCP/IP channels
/// This allows the SSH channel to work with standard ByteBuffer-based channel handlers
final class SSHChannelDataUnwrappingHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        
        switch channelData.type {
        case .channel:
            // Extract ByteBuffer from SSHChannelData
            switch channelData.data {
            case .byteBuffer(let buffer):
                context.fireChannelRead(wrapInboundOut(buffer))
            case .fileRegion(_):
                // Handle file region if needed, or skip for now
                break
            }
        case .stdErr:
            // Handle standard error data (for session channels)
            switch channelData.data {
            case .byteBuffer(let buffer):
                // For stderr, you might want to handle this differently
                // For now, we'll pass it through as regular data
                context.fireChannelRead(wrapInboundOut(buffer))
            case .fileRegion(_):
                break
            }
        default:
            // Handle any unknown or future data types
            break
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        
        // Wrap ByteBuffer in SSHChannelData
        let channelData = SSHChannelData(
            type: .channel,
            data: .byteBuffer(buffer)
        )
        
        context.write(wrapOutboundOut(channelData), promise: promise)
    }
}