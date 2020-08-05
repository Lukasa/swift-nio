//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIO

class ReadHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let data = self.unwrapInboundIn(data)

        // We want to render out the data as hex.
        let rendering = data.readableBytesView.map { String($0, radix: 16) }.joined()
        print(rendering)
    }
}

class ErrorCatcher: ChannelInboundHandler {
    typealias InboundIn = Any

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error encountered: \(error)")
        context.close(promise: nil)
    }
}

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
var bootstrap = NIOTunTapBootstrap(group: group)
    // Set the handlers that are applied to the bound channel
    .channelInitializer { channel in
        channel.pipeline.addHandlers([ReadHandler(), ErrorCatcher()])
    }

defer {
    try! group.syncShutdownGracefully()
}

let arg1 = CommandLine.arguments.dropFirst().first
let interfaceName = arg1 ?? "tun0"

let channel = try bootstrap.withNamedTunDevice(interfaceName).wait()

print("Server started. You may need to bring up the device \(interfaceName) and set up appropriate routing.")

// This will never unblock as we don't close the channel
try channel.closeFuture.wait()

print("Server closed")

