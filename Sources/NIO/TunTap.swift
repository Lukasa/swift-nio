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
import CNIOLinux

public struct TunTapError: Error, Hashable, CustomStringConvertible {
    private var rawValue: RawValue

    private init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    private enum RawValue {
        case unsupportedOperatingSystem
        case deviceNameTooLong
    }

    public static let deviceNameTooLong = TunTapError(rawValue: .deviceNameTooLong)

    public static let unsupportedOperatingSystem = TunTapError(rawValue: .unsupportedOperatingSystem)

    public var description: String {
        return "TunTapError.\(String(describing: self.rawValue))"
    }
}

/// A variety of helpers for working with tun/tap interfaces.
///
/// These interfaces only work on a small number of platforms. For that reason, the vast majority of
/// the interface code in this file is only compiled on those platforms. For all others, these methods will
/// throw.
internal enum TunTap {
    fileprivate static let cloneDevice = "/dev/net/tun"

    /// Create a named tun device.
    ///
    /// Creating a named tun device will first attempt to locate a tun device of that name. If one is present,
    /// what will actually happen is that we'll try to open that interface, encountering system errors if we
    /// fail. If one is not present, we will create that tun device directly.
    static func createTunDevice(named name: String) throws -> CInt {
        #if os(Linux)
        let fd = try Posix.open(file: TunTap.cloneDevice, oFlag: O_RDWR)

        do {
            var ifr = ifreq()
            CNIOLinux_set_ifr_flags(&ifr, IFF_TUN | IFF_NO_PI)

            try name.withCString { ptr in
                CNIOLinux_ifr_setName(&ifr, ptr)
                try Posix.ioctl(descriptor: fd, request: CNIOLinux_get_tunsetiff(), argument: &ifr)
            }

            return fd
        } catch {
            // Whoops, errored out. Clean up the fd. Ignore errors on cleanup.
            try? Posix.close(descriptor: fd)
            throw error
        }
        #else
        throw TunTapError.unsupportedOperatingSystem
        #endif
    }
}
