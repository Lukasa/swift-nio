//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019-2023 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import NIOCore

class TunTapSocket: SocketProtocol {
    typealias SelectableType = SelectableFileHandle

    let fd: SelectableFileHandle

    init(tunTapSocket: NIOFileHandle) throws {
        self.fd = SelectableFileHandle(tunTapSocket)
        try self.ignoreSIGPIPE()
        try tunTapSocket.withUnsafeFileDescriptor {
            try NIOFileHandle.setNonBlocking(fileDescriptor: $0)
        }
    }

    func ignoreSIGPIPE() throws {
        try self.fd.withUnsafeHandle {
            try PipePair.ignoreSIGPIPE(descriptor: $0)
        }
    }

    var description: String {
        return "TunTapSocket { fd=\(self.fd) }"
    }

    func connect(to address: SocketAddress) throws -> Bool {
        throw ChannelError.operationUnsupported
    }

    func finishConnect() throws {
        throw ChannelError.operationUnsupported
    }

    func write(pointer: UnsafeRawBufferPointer) throws -> IOResult<Int> {
        return try self.fd.withUnsafeHandle {
            try Posix.write(descriptor: $0, pointer: pointer.baseAddress!, size: pointer.count)
        }
    }

    func writev(iovecs: UnsafeBufferPointer<IOVector>) throws -> IOResult<Int> {
        return try self.fd.withUnsafeHandle {
            try Posix.writev(descriptor: $0, iovecs: iovecs)
        }
    }

    func read(pointer: UnsafeMutableRawBufferPointer) throws -> IOResult<Int> {
        return try self.fd.withUnsafeHandle {
            try Posix.read(descriptor: $0, pointer: pointer.baseAddress!, size: pointer.count)
        }
    }

    func readv(iovecs: UnsafeBufferPointer<IOVector>) throws -> IOResult<Int> {
        return try self.fd.withUnsafeHandle {
            try Posix.readv(descriptor: $0, iovecs: iovecs)
        }
    }

    func recvmsg(pointer: UnsafeMutableRawBufferPointer,
                 storage: inout sockaddr_storage,
                 storageLen: inout socklen_t,
                 controlBytes: inout UnsafeReceivedControlBytes) throws -> IOResult<Int> {
        throw ChannelError.operationUnsupported
    }
    
    func sendmsg(pointer: UnsafeRawBufferPointer,
                 destinationPtr: UnsafePointer<sockaddr>?,
                 destinationSize: socklen_t,
                 controlBytes: UnsafeMutableRawBufferPointer) throws -> IOResult<Int> {
        throw ChannelError.operationUnsupported
    }

    func sendFile(fd: CInt, offset: Int, count: Int) throws -> IOResult<Int> {
        throw ChannelError.operationUnsupported
    }

    func recvmmsg(msgs: UnsafeMutableBufferPointer<MMsgHdr>) throws -> IOResult<Int> {
        throw ChannelError.operationUnsupported
    }

    func sendmmsg(msgs: UnsafeMutableBufferPointer<MMsgHdr>) throws -> IOResult<Int> {
        throw ChannelError.operationUnsupported
    }

    func shutdown(how: Shutdown) throws {
        throw ChannelError.operationUnsupported
    }

    var isOpen: Bool {
        return self.fd.isOpen
    }

    func close() throws {
        guard self.fd.isOpen else {
            throw ChannelError.alreadyClosed
        }
        try self.fd.close()
    }

    func bind(to address: SocketAddress) throws {
        throw ChannelError.operationUnsupported
    }

    func localAddress() throws -> SocketAddress {
        throw ChannelError.operationUnsupported
    }

    func remoteAddress() throws -> SocketAddress {
        throw ChannelError.operationUnsupported
    }

    func setOption<T>(level: NIOBSDSocket.OptionLevel, name: NIOBSDSocket.Option, value: T) throws {
        throw ChannelError.operationUnsupported
    }

    func getOption<T>(level: NIOBSDSocket.OptionLevel, name: NIOBSDSocket.Option) throws -> T {
        throw ChannelError.operationUnsupported
    }
}
