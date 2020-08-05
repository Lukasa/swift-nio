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
import NIOConcurrencyHelpers

private struct PendingTunTapWrite {
    var data: ByteBuffer
    var promise: EventLoopPromise<Void>?
}

/// This holds the states of the currently pending tun/tap writes. The core is a `MarkedCircularBuffer` which holds all the
/// writes and a mark up until the point the data is flushed. This struct has several behavioural differences from the
/// `PendingStreamWritesState`:
///
/// 1. Writes are message-based, not stream-based. We must write an entire message in one go, or not at all.
/// 2. Vector writes are unsupported. Tun/tap interfaces treat vector writes as a gathering write to _one_ packet, which is
///     highly unlikely to be what we want.
///
/// The most important operations on this object are:
///  - `append` to add a `ByteBuffer` to the list of pending writes.
///  - `markFlushCheckpoint` which sets a flush mark on the current position of the `MarkedCircularBuffer`. All the items before the checkpoint will be written eventually.
///  - `didWrite` when a number of bytes have been written.
///  - `failAll` if for some reason all outstanding writes need to be discarded and the corresponding `EventLoopPromise` needs to be failed.
private struct PendingTunTapWritesState {
    typealias TunTapWritePromiseFiller = (EventLoopPromise<Void>, Error?)

    private var pendingWrites = MarkedCircularBuffer<PendingTunTapWrite>(initialCapacity: 16)
    private var chunks: Int = 0
    public private(set) var bytes: Int64 = 0

    public var nextWrite: PendingTunTapWrite? {
        return self.pendingWrites.first
    }

    /// Subtract `bytes` from the number of outstanding bytes to write.
    private mutating func subtractOutstanding(bytes: Int) {
        assert(self.bytes >= bytes, "allegedly written more bytes (\(bytes)) than outstanding (\(self.bytes))")
        self.bytes -= numericCast(bytes)
    }

    /// Indicates that the first outstanding write was written.
    ///
    /// - returns: The promise that the caller must fire, along with an error to fire it with if it needs one.
    private mutating func wroteFirst(error: Error? = nil) -> TunTapWritePromiseFiller? {
        let first = self.pendingWrites.removeFirst()
        self.chunks -= 1
        self.subtractOutstanding(bytes: first.data.readableBytes)
        if let promise = first.promise {
            return (promise, error)
        }
        return nil
    }

    /// Initialise a new, empty `PendingTunTapWritesState`.
    public init() { }

    /// Check if there are no outstanding writes.
    public var isEmpty: Bool {
        if self.pendingWrites.isEmpty {
            assert(self.chunks == 0)
            assert(self.bytes == 0)
            assert(!self.pendingWrites.hasMark)
            return true
        } else {
            assert(self.chunks > 0 && self.bytes >= 0)
            return false
        }
    }

    /// Add a new write and optionally the corresponding promise to the list of outstanding writes.
    public mutating func append(_ chunk: PendingTunTapWrite) {
        self.pendingWrites.append(chunk)
        self.chunks += 1
        self.bytes += numericCast(chunk.data.readableBytes)
    }

    /// Mark the flush checkpoint.
    ///
    /// All writes before this checkpoint will eventually be written to the socket.
    public mutating func markFlushCheckpoint() {
        self.pendingWrites.mark()
    }

    /// Indicate that a write has happened.
    ///
    /// - parameters:
    ///     - data: The result of the write operation: namely the number of bytes we wrote.
    /// - returns: A promise and the error that should be sent to it, if any, and a `WriteResult` which indicates if we could write everything or not.
    public mutating func didWrite(_ data: IOResult<Int>) -> (TunTapWritePromiseFiller?, OneWriteOperationResult) {
        switch data {
        case .processed(let written):
            return self.didScalarWrite(written: written)
        case .wouldBlock:
            return (nil, .wouldBlock)
        }
    }

    /// Indicates that a scalar write succeeded.
    ///
    /// - parameters:
    ///     - written: The number of bytes successfully written.
    /// - returns: All the promises that must be fired, and a `WriteResult` that indicates if we could write
    ///     everything or not.
    private mutating func didScalarWrite(written: Int) -> (TunTapWritePromiseFiller?, OneWriteOperationResult) {
        precondition(written <= self.pendingWrites.first!.data.readableBytes,
                     "Appeared to write more bytes (\(written)) than the message contained (\(self.pendingWrites.first!.data.readableBytes))")
        let writeFiller = self.wroteFirst()
        // If we no longer have a mark, we wrote everything.
        let result: OneWriteOperationResult = self.pendingWrites.hasMark ? .writtenPartially : .writtenCompletely
        return (writeFiller, result)
    }

    /// Is there a pending flush?
    public var isFlushPending: Bool {
        return self.pendingWrites.hasMark
    }

    /// Fail all the outstanding writes.
    ///
    /// - returns: Nothing
    public mutating func failAll(error: Error) {
        var promises: [EventLoopPromise<Void>] = []
        promises.reserveCapacity(self.pendingWrites.count)

        while !self.pendingWrites.isEmpty {
            let w = self.pendingWrites.removeFirst()
            self.chunks -= 1
            self.bytes -= numericCast(w.data.readableBytes)
            w.promise.map { promises.append($0) }
        }

        promises.forEach { $0.fail(error) }
    }

    /// Returns the best mechanism to write pending data at the current point in time.
    var currentBestWriteMechanism: WriteMechanism {
        switch self.pendingWrites.markedElementIndex {
        case .some:
            return .scalarBufferWrite
        default:
            return .nothingToBeWritten
        }
    }
}

// This extension contains a lazy sequence that makes other parts of the code work better.
extension PendingTunTapWritesState {
    struct FlushedTunTapWriteSequence: Sequence, IteratorProtocol {
        private let pendingWrites: PendingTunTapWritesState
        private var index: CircularBuffer<PendingTunTapWrite>.Index
        private let markedIndex: CircularBuffer<PendingTunTapWrite>.Index?

        init(_ pendingWrites: PendingTunTapWritesState) {
            self.pendingWrites = pendingWrites
            self.index = pendingWrites.pendingWrites.startIndex
            self.markedIndex = pendingWrites.pendingWrites.markedElementIndex
        }

        mutating func next() -> PendingTunTapWrite? {
            while let markedIndex = self.markedIndex, self.pendingWrites.pendingWrites.distance(from: self.index,
                                                                                                to: markedIndex) >= 0 {
                let element = self.pendingWrites.pendingWrites[index]
                index = self.pendingWrites.pendingWrites.index(after: index)
                return element
            }

            return nil
        }
    }

    var flushedWrites: FlushedTunTapWriteSequence {
        return FlushedTunTapWriteSequence(self)
    }
}

/// This class manages the writing of pending writes to tun/tap sockets. The state is held in a `PendingWritesState`
/// value. The most important purpose of this object is to call `write`.
final class PendingTunTapWritesManager: PendingWritesManager {
    private var state = PendingTunTapWritesState()

    internal var waterMark: ChannelOptions.Types.WriteBufferWaterMark = ChannelOptions.Types.WriteBufferWaterMark(low: 32 * 1024, high: 64 * 1024)
    internal let channelWritabilityFlag: NIOAtomic<Bool> = .makeAtomic(value: true)
    internal var writeSpinCount: UInt = 16
    private(set) var isOpen = true

    init() {}

    /// Mark the flush checkpoint.
    func markFlushCheckpoint() {
        self.state.markFlushCheckpoint()
    }

    /// Is there a flush pending?
    var isFlushPending: Bool {
        return self.state.isFlushPending
    }

    /// Are there any outstanding writes currently?
    var isEmpty: Bool {
        return self.state.isEmpty
    }

    /// Add a pending write.
    ///
    /// - parameters:
    ///     - message: The `ByteBuffer` to write.
    ///     - promise: Optionally an `EventLoopPromise` that will get the write operation's result
    /// - result: If the `Channel` is still writable after adding the write of `data`.
    func add(message: ByteBuffer, promise: EventLoopPromise<Void>?) -> Bool {
        assert(self.isOpen)
        self.state.append(.init(data: message, promise: promise))

        if self.state.bytes > waterMark.high && channelWritabilityFlag.compareAndExchange(expected: true, desired: false) {
            // Returns false to signal the Channel became non-writable and we need to notify the user
            return false
        }
        return true
    }

    /// Returns the best mechanism to write pending data at the current point in time.
    var currentBestWriteMechanism: WriteMechanism {
        return self.state.currentBestWriteMechanism
    }

    /// Triggers the appropriate write operation. This is a fancy way of saying trigger `write` if needed.
    ///
    /// - parameters:
    ///     - scalarWriteOperation: An operation that writes a single, contiguous array of bytes (usually `write`).
    /// - returns: The `WriteResult` and whether the `Channel` is now writable.
    func triggerAppropriateWriteOperations(scalarWriteOperation: (UnsafeRawBufferPointer) throws -> IOResult<Int>) throws -> OverallWriteResult {
        return try self.triggerWriteOperations { writeMechanism in
            switch writeMechanism {
            case .scalarBufferWrite:
                return try self.triggerScalarBufferWrite(scalarWriteOperation: { try scalarWriteOperation($0) })
            case .vectorBufferWrite:
                preconditionFailure("PendingTunTapWritesManager was handed a vector write")
            case .scalarFileWrite:
                preconditionFailure("PendingTunTapWritesManager was handed a file write")
            case .nothingToBeWritten:
                assertionFailure("called \(#function) with nothing available to be written")
                return OneWriteOperationResult.writtenCompletely
            }
        }
    }

    /// To be called after a write operation (usually selected and run by `triggerAppropriateWriteOperation`) has
    /// completed.
    ///
    /// - parameters:
    ///     - data: The result of the write operation.
    private func didWrite(_ data: IOResult<Int>) -> OneWriteOperationResult {
        let (promise, result) = self.state.didWrite(data)

        if self.state.bytes < self.waterMark.low {
            self.channelWritabilityFlag.store(true)
        }

        self.fulfillPromise(promise)
        return result
    }


    /// Trigger a write of a single object where an object must be a contiguous array of bytes.
    ///
    /// - parameters:
    ///     - scalarWriteOperation: An operation that writes a single, contiguous array of bytes (usually `write`).
    private func triggerScalarBufferWrite(scalarWriteOperation: (UnsafeRawBufferPointer) throws -> IOResult<Int>) rethrows -> OneWriteOperationResult {
        assert(self.state.isFlushPending && self.isOpen && !self.state.isEmpty,
               "illegal state for scalar tun/tap write operation: flushPending: \(self.state.isFlushPending), isOpen: \(self.isOpen), empty: \(self.state.isEmpty)")
        let pending = self.state.nextWrite!
        let writeResult = try pending.data.withUnsafeReadableBytes {
            try scalarWriteOperation($0)
        }
        return self.didWrite(writeResult)
    }

    private func fulfillPromise(_ promise: PendingTunTapWritesState.TunTapWritePromiseFiller?) {
        if let promise = promise, let error = promise.1 {
            promise.0.fail(error)
        } else if let promise = promise {
            promise.0.succeed(())
        }
    }

    /// Fail all the outstanding writes. This is useful if for example the `Channel` is closed.
    func failAll(error: Error, close: Bool) {
        if close {
            assert(self.isOpen)
            self.isOpen = false
        }

        self.state.failAll(error: error)

        assert(self.state.isEmpty)
    }
}
