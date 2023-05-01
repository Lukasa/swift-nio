//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIOCore

/// A channel used with tun/tap file descriptors in Linux
final class TunTapChannel: BaseSocketChannel<TunTapSocket> {
    private let pendingWrites: PendingTunTapWritesManager

    // This is `Channel` API so must be thread-safe.
    override public var isWritable: Bool {
        return pendingWrites.isWritable
    }

    override var isOpen: Bool {
        self.eventLoop.assertInEventLoop()
        assert(super.isOpen == self.pendingWrites.isOpen)
        return super.isOpen
    }

    init(eventLoop: SelectableEventLoop, handle: NIOFileHandle) throws {
        let socket = try TunTapSocket(tunTapSocket: handle)
        self.pendingWrites = PendingTunTapWritesManager()

        try super.init(socket: socket,
                       parent: nil,
                       eventLoop: eventLoop,
                       recvAllocator: FixedSizeRecvByteBufferAllocator(capacity: 2048),
                       supportReconnect: false)
    }

    // MARK: TunTapChannel overrides required by BaseSocketChannel

    override func setOption0<Option: ChannelOption>(_ option: Option, value: Option.Value) throws {
        self.eventLoop.assertInEventLoop()

        guard isOpen else {
            throw ChannelError.ioOnClosedChannel
        }

        switch option {
        case _ as ChannelOptions.Types.WriteSpinOption:
            pendingWrites.writeSpinCount = value as! UInt
        case _ as ChannelOptions.Types.WriteBufferWaterMarkOption:
            pendingWrites.waterMark = value as! ChannelOptions.Types.WriteBufferWaterMark
        default:
            try super.setOption0(option, value: value)
        }
    }

    override func getOption0<Option: ChannelOption>(_ option: Option) throws -> Option.Value {
        self.eventLoop.assertInEventLoop()

        guard isOpen else {
            throw ChannelError.ioOnClosedChannel
        }

        switch option {
        case _ as ChannelOptions.Types.WriteSpinOption:
            return pendingWrites.writeSpinCount as! Option.Value
        case _ as ChannelOptions.Types.WriteBufferWaterMarkOption:
            return pendingWrites.waterMark as! Option.Value
        default:
            return try super.getOption0(option)
        }
    }

    override func connectSocket(to address: SocketAddress) throws -> Bool {
        // For now we don't support operating in connected mode for datagram channels.
        throw ChannelError.operationUnsupported
    }

    override func finishConnectSocket() throws {
        // For now we don't support operating in connected mode for datagram channels.
        throw ChannelError.operationUnsupported
    }

    override func readFromSocket() throws -> ReadResult {
        var result = ReadResult.none

        for _ in 1...self.maxMessagesPerRead {
            guard self.isOpen else {
                throw ChannelError.eof
            }

            let (buffer, readResult) = try self.recvBufferPool.buffer(allocator: self.allocator) { buffer in
                try buffer.withMutableWritePointer { pointer in
                    try self.socket.read(pointer: pointer)
                }
            }
            
            switch readResult {
            case .processed(let bytesRead):
                assert(bytesRead > 0)
                assert(self.isOpen)
                self.recvBufferPool.record(actualReadBytes: bytesRead)
                readPending = false

                assert(self.isActive)
                pipeline.fireChannelRead(NIOAny(buffer))
                result = .some
            case .wouldBlock(let bytesRead):
                assert(bytesRead == 0)
                return result
            }
        }
        return result
    }

    override func shouldCloseOnReadError(_ err: Error) -> Bool {
        guard let err = err as? IOError else { return true }

        switch err.errnoCode {
        // ECONNREFUSED can happen on linux if the previous sendto(...) failed.
        // See also:
        // -    https://bugzilla.redhat.com/show_bug.cgi?id=1375
        // -    https://lists.gt.net/linux/kernel/39575
        case ECONNREFUSED,
             ENOMEM:
            // These are errors we may be able to recover from.
            return false
        default:
            return true
        }
    }
    /// Buffer a write in preparation for a flush.
    override func bufferPendingWrite(data: NIOAny, promise: EventLoopPromise<Void>?) {
        let data = self.unwrapData(data, as: ByteBuffer.self)

        // TODO: This isn't in terms of addressedenvelope anymore.
        if !self.pendingWrites.add(message: data, promise: promise) {
            assert(self.isActive)
            pipeline.fireChannelWritabilityChanged()
        }
    }

    override final func hasFlushedPendingWrites() -> Bool {
        return self.pendingWrites.isFlushPending
    }

    /// Mark a flush point. This is called when flush is received, and instructs
    /// the implementation to record the flush.
    override func markFlushPoint() {
        // Even if writable() will be called later by the EventLoop we still need to mark the flush checkpoint so we are sure all the flushed messages
        // are actually written once writable() is called.
        self.pendingWrites.markFlushCheckpoint()
    }

    /// Called when closing, to instruct the specific implementation to discard all pending
    /// writes.
    override func cancelWritesOnClose(error: Error) {
        self.pendingWrites.failAll(error: error, close: true)
    }

    override func writeToSocket() throws -> OverallWriteResult {
        let result = try self.pendingWrites.triggerAppropriateWriteOperations(
            scalarWriteOperation: { ptr in
                guard ptr.count > 0 else {
                    // No need to call write if the buffer is empty.
                    return .processed(0)
                }
                // normal write
                return try self.socket.write(pointer: ptr)

            }
        )
        return result
    }


    // MARK: TunTap Channel overrides not required by BaseSocketChannel

    override func bind0(to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        promise?.fail(ChannelError.operationUnsupported)
    }

    func registrationFor(interested: SelectorEventSet, registrationID: SelectorRegistrationID) -> NIORegistration {
        return NIORegistration(channel: .tunTapChannel(self),
                               interested: interested,
                               registrationID: registrationID)
    }

    override func register(selector: Selector<NIORegistration>, interested: SelectorEventSet) throws {
        try selector.register(selectable: self.socket.fd, interested: interested, makeRegistration: self.registrationFor(interested:registrationID:))
    }

    override func deregister(selector: Selector<NIORegistration>, mode: CloseMode) throws {
        assert(mode == .all)
        try selector.deregister(selectable: self.socket.fd)
    }

    override func reregister(selector: Selector<NIORegistration>, interested: SelectorEventSet) throws {
        try selector.reregister(selectable: self.socket.fd, interested: interested)
    }
}

extension TunTapChannel: CustomStringConvertible {
    var description: String {
        return "TunTapChannel { \(self.socketDescription), active = \(self.isActive) }"
    }
}
