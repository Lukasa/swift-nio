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

private let emptyAddress = try! SocketAddress(ipAddress: "0.0.0.0", port: 0)

/// A channel used with tun/tap file descriptors in Linux
final class TunTapChannel: BaseSocketChannel<PipePair> {
    // Guard against re-entrance of flushNow() method.
    private let pendingWrites: PendingDatagramWritesManager

    /// Support for vector reads, if enabled.
    private var vectorReadManager: Optional<DatagramVectorReadManager>
    // This is `Channel` API so must be thread-safe.
    override public var isWritable: Bool {
        return pendingWrites.isWritable
    }

    override var isOpen: Bool {
        self.eventLoop.assertInEventLoop()
        assert(super.isOpen == self.pendingWrites.isOpen)
        return super.isOpen
    }

    deinit {
        if var vectorReadManager = self.vectorReadManager {
            vectorReadManager.deallocate()
        }
    }

    init(eventLoop: SelectableEventLoop, handle: NIOFileHandle) throws {
        self.vectorReadManager = nil
        let extraHandle = try handle.withUnsafeFileDescriptor {
            NIOFileHandle(descriptor: dup($0))
        }
        let pipe = try PipePair(inputFD: handle, outputFD: extraHandle)
        self.pendingWrites = PendingDatagramWritesManager(msgs: eventLoop.msgs,
                                                          iovecs: eventLoop.iovecs,
                                                          addresses: eventLoop.addresses,
                                                          storageRefs: eventLoop.storageRefs,
                                                          controlMessageStorage: eventLoop.controlMessageStorage)

        try super.init(socket: pipe,
                       parent: nil,
                       eventLoop: eventLoop,
                       recvAllocator: FixedSizeRecvByteBufferAllocator(capacity: 2048))
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
        case _ as ChannelOptions.Types.DatagramVectorReadMessageCountOption:
            // We only support vector reads on these OSes. Let us know if there's another OS with this syscall!
            #if os(Linux) || os(FreeBSD) || os(Android)
            self.vectorReadManager.updateMessageCount(value as! Int)
            #else
            break
            #endif
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
        case _ as ChannelOptions.Types.DatagramVectorReadMessageCountOption:
            return (self.vectorReadManager?.messageCount ?? 0) as! Option.Value
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
        if self.vectorReadManager != nil {
            return try self.vectorReadFromSocket()
        } else {
            return try self.singleReadFromSocket()
        }
    }

    private func singleReadFromSocket() throws -> ReadResult {
        var buffer = self.recvAllocator.buffer(allocator: self.allocator)
        var readResult = ReadResult.none

        for i in 1...self.maxMessagesPerRead {
            guard self.isOpen else {
                throw ChannelError.eof
            }
            buffer.clear()

            let result = try buffer.withMutableWritePointer {
                try self.socket.read(pointer: $0)
            }
            switch result {
            case .processed(let bytesRead):
                assert(bytesRead > 0)
                assert(self.isOpen)
                let mayGrow = recvAllocator.record(actualReadBytes: bytesRead)
                readPending = false

                let msg = AddressedEnvelope(remoteAddress: emptyAddress,
                                            data: buffer,
                                            metadata: nil)
                assert(self.isActive)
                pipeline.fireChannelRead0(NIOAny(msg))
                if mayGrow && i < maxMessagesPerRead {
                    buffer = recvAllocator.buffer(allocator: allocator)
                }
                readResult = .some
            case .wouldBlock(let bytesRead):
                assert(bytesRead == 0)
                return readResult
            }
        }
        return readResult
    }

    private func vectorReadFromSocket() throws -> ReadResult {
        var buffer = self.recvAllocator.buffer(allocator: self.allocator)
        var readResult = ReadResult.none

        readLoop: for i in 1...self.maxMessagesPerRead {
            guard self.isOpen else {
                throw ChannelError.eof
            }
            guard let vectorReadManager = self.vectorReadManager else {
                // The vector read manager went away. This happens if users unset the vector read manager
                // during channelRead. It's unlikely, but we tolerate it by aborting the read early.
                break readLoop
            }
            buffer.clear()

            // This force-unwrap is safe, as we checked whether this is nil in the caller.
            let result = try vectorReadManager.readFromSocket(
                buffer: &buffer,
                reportExplicitCongestionNotifications: false) { msgvec in
                return try self.socket.rea

            }
            switch result {
            case .some(let results, let totalRead):
                assert(self.isOpen)
                assert(self.isActive)

                let mayGrow = recvAllocator.record(actualReadBytes: totalRead)
                readPending = false

                var messageIterator = results.makeIterator()
                while self.isActive, let message = messageIterator.next() {
                    pipeline.fireChannelRead(NIOAny(message))
                }

                if mayGrow && i < maxMessagesPerRead {
                    buffer = recvAllocator.buffer(allocator: allocator)
                }
                readResult = .some
            case .none:
                break readLoop
            }
        }

        return readResult
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
        let data = data.forceAsByteEnvelope()

        if !self.pendingWrites.add(envelope: data, promise: promise) {
            assert(self.isActive)
            pipeline.fireChannelWritabilityChanged0()
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
            scalarWriteOperation: { (ptr, destinationPtr, destinationSize, metadata) in
                guard ptr.count > 0 else {
                    // No need to call write if the buffer is empty.
                    return .processed(0)
                }
                // normal write
                return try self.socket.write(pointer: ptr)

            },
            vectorWriteOperation: { msgs in
                return try self.socket.writev(iovecs: UnsafeBufferPointer(rebasing: self.selectableEventLoop.iovecs.prefix(msgs.count)))
            }
        )
        return result
    }


    // MARK: TunTap Channel overrides not required by BaseSocketChannel

    override func bind0(to address: SocketAddress, promise: EventLoopPromise<Void>?) {
        promise?.fail(ChannelError.operationUnsupported)
    }

    func registrationFor(interested: SelectorEventSet) -> NIORegistration {
        return .tupTapChannel(self, interested)
    }

    override func register(selector: Selector<NIORegistration>, interested: SelectorEventSet) throws {
        // TODO: We should probably not abuse PipePair this way.
        try selector.register(selectable: self.socket.inputFD, interested: interested, makeRegistration: self.registrationFor(interested:))
    }

    override func deregister(selector: Selector<NIORegistration>, mode: CloseMode) throws {
        assert(mode == .all)
        try selector.deregister(selectable: self.socket.inputFD)
    }

    override func reregister(selector: Selector<NIORegistration>, interested: SelectorEventSet) throws {
        try selector.reregister(selectable: self.socket.inputFD, interested: interested)
    }
}

extension TunTapChannel: CustomStringConvertible {
    var description: String {
        return "TunTapChannel { \(self.socketDescription), active = \(self.isActive) }"
    }
}
