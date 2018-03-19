//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
//
// EventLoopFutureTest+XCTest.swift
//
import XCTest

///
/// NOTE: This file was generated by generate_linux_tests.rb
///
/// Do NOT edit this file directly as it will be regenerated automatically when needed.
///

extension EventLoopFutureTest {

   static var allTests : [(String, (EventLoopFutureTest) -> () throws -> Void)] {
      return [
                ("testFutureFulfilledIfHasResult", testFutureFulfilledIfHasResult),
                ("testFutureFulfilledIfHasError", testFutureFulfilledIfHasError),
                ("testAndAllWithAllSuccesses", testAndAllWithAllSuccesses),
                ("testAndAllWithAllFailures", testAndAllWithAllFailures),
                ("testAndAllWithOneFailure", testAndAllWithOneFailure),
                ("testThenThrowingWhichDoesNotThrow", testThenThrowingWhichDoesNotThrow),
                ("testThenThrowingWhichDoesThrow", testThenThrowingWhichDoesThrow),
                ("testThenIfErrorThrowingWhichDoesNotThrow", testThenIfErrorThrowingWhichDoesNotThrow),
                ("testThenIfErrorThrowingWhichDoesThrow", testThenIfErrorThrowingWhichDoesThrow),
                ("testOrderOfFutureCompletion", testOrderOfFutureCompletion),
                ("testEventLoopHoppingInThen", testEventLoopHoppingInThen),
                ("testEventLoopHoppingInThenWithFailures", testEventLoopHoppingInThenWithFailures),
                ("testEventLoopHoppingAndAll", testEventLoopHoppingAndAll),
                ("testEventLoopHoppingAndAllWithFailures", testEventLoopHoppingAndAllWithFailures),
                ("testFutureInVariousScenarios", testFutureInVariousScenarios),
                ("testLoopHoppingHelperSuccess", testLoopHoppingHelperSuccess),
                ("testLoopHoppingHelperFailure", testLoopHoppingHelperFailure),
                ("testLoopHoppingHelperNoHopping", testLoopHoppingHelperNoHopping),
           ]
   }
}

