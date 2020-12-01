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

@usableFromInline
struct UnsafeNonnullRawBufferPointer {
    @usableFromInline
    var baseAddress: UnsafeRawPointer

    @usableFromInline
    var count: Int

    @inlinable
    init(start: UnsafeRawPointer, count: Int) {
        precondition(count >= 0)
        self.baseAddress = start
        self.count = count
    }

    @inlinable
    init(baseAddress: UnsafeRawPointer, unsafeUncheckedCount: Int) {
        self.baseAddress = baseAddress
        self.count = unsafeUncheckedCount
    }

    @inlinable
    init(_ original: UnsafeNonnullMutableRawBufferPointer) {
        self.baseAddress = UnsafeRawPointer(original.baseAddress)
        self.count = original.count
    }

    @inlinable
    func dropFirst(_ n: Int) -> UnsafeNonnullRawBufferPointer {
        if n > self.count {
            return UnsafeNonnullRawBufferPointer(baseAddress: self.baseAddress, unsafeUncheckedCount: 0)
        } else {
            let baseAddress = self.baseAddress.advanced(by: n)
            let count = self.count &- n
            return UnsafeNonnullRawBufferPointer(baseAddress: baseAddress, unsafeUncheckedCount: count)
        }
    }

    @inlinable
    subscript(range: Range<Int>) -> UnsafeNonnullRawBufferPointer {
        precondition(range.upperBound <= self.count)
        precondition(range.lowerBound >= 0)

        let newBaseAddress = self.baseAddress.advanced(by: range.lowerBound)
        let count = range.upperBound &- range.lowerBound
        return UnsafeNonnullRawBufferPointer(baseAddress: newBaseAddress, unsafeUncheckedCount: count)
    }

    @inlinable
    subscript(offset: Int) -> UInt8 {
        // That's right, bounds-checking!
        precondition(offset >= 0 && offset < self.count)
        return self.baseAddress.load(fromByteOffset: offset, as: UInt8.self)
    }
}

@usableFromInline
struct UnsafeNonnullMutableRawBufferPointer {
    @usableFromInline
    var baseAddress: UnsafeMutableRawPointer

    @usableFromInline
    var count: Int

    @inlinable
    init(start: UnsafeMutableRawPointer, count: Int) {
        precondition(count >= 0)
        self.baseAddress = start
        self.count = count
    }

    @inlinable
    init(baseAddress: UnsafeMutableRawPointer, unsafeUncheckedCount: Int) {
        self.baseAddress = baseAddress
        self.count = unsafeUncheckedCount
    }

    @inlinable
    func dropFirst(_ n: Int) -> UnsafeNonnullMutableRawBufferPointer {
        let n = min(self.count, n)
        let baseAddress = self.baseAddress.advanced(by: n)
        let count = self.count &- n
        return UnsafeNonnullMutableRawBufferPointer(baseAddress: baseAddress, unsafeUncheckedCount: count)
    }

    @inlinable
    subscript(range: Range<Int>) -> UnsafeNonnullMutableRawBufferPointer {
        precondition(range.upperBound <= self.count)
        precondition(range.lowerBound >= 0)

        let newBaseAddress = self.baseAddress.advanced(by: range.lowerBound)
        let count = range.upperBound &- range.lowerBound
        return UnsafeNonnullMutableRawBufferPointer(baseAddress: newBaseAddress, unsafeUncheckedCount: count)
    }

    @inlinable
    subscript(offset: Int) -> UInt8 {
        // That's right, bounds-checking!
        precondition(offset >= 0 && offset < self.count)
        return self.baseAddress.load(fromByteOffset: offset, as: UInt8.self)
    }

    @inlinable
    func copyMemory(from source: UnsafeRawBufferPointer) {
        precondition(source.count <= self.count)
        source.baseAddress.map { self.baseAddress.copyMemory(from: $0, byteCount: source.count) }
    }
}

extension UnsafeRawBufferPointer {
    @inlinable
    init(_ pointer: UnsafeNonnullRawBufferPointer) {
        self.init(start: pointer.baseAddress, count: pointer.count)
    }

    @inlinable
    init(_ pointer: UnsafeNonnullMutableRawBufferPointer) {
        self.init(start: pointer.baseAddress, count: pointer.count)
    }
}

extension UnsafeMutableRawBufferPointer {
    @inlinable
    init(_ pointer: UnsafeNonnullMutableRawBufferPointer) {
        self.init(start: pointer.baseAddress, count: pointer.count)
    }
}
