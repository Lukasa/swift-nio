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
// HTTPHeadersTest+XCTest.swift
//
import XCTest

///
/// NOTE: This file was generated by generate_linux_tests.rb
///
/// Do NOT edit this file directly as it will be regenerated automatically when needed.
///

extension HTTPHeadersTest {

   @available(*, deprecated, message: "not actually deprecated. Just deprecated to allow deprecated tests (which test deprecated functionality) without warnings")
   static var allTests : [(String, (HTTPHeadersTest) -> () throws -> Void)] {
      return [
                ("testCasePreservedButInsensitiveLookup", testCasePreservedButInsensitiveLookup),
                ("testDictionaryLiteralAlternative", testDictionaryLiteralAlternative),
                ("testWriteHeadersSeparately", testWriteHeadersSeparately),
                ("testRevealHeadersSeparately", testRevealHeadersSeparately),
                ("testSubscriptDoesntSplitHeaders", testSubscriptDoesntSplitHeaders),
                ("testCanonicalisationDoesntHappenForSetCookie", testCanonicalisationDoesntHappenForSetCookie),
                ("testTrimWhitespaceWorksOnEmptyString", testTrimWhitespaceWorksOnEmptyString),
                ("testTrimWhitespaceWorksOnOnlyWhitespace", testTrimWhitespaceWorksOnOnlyWhitespace),
                ("testTrimWorksWithCharactersInTheMiddleAndWhitespaceAround", testTrimWorksWithCharactersInTheMiddleAndWhitespaceAround),
                ("testContains", testContains),
                ("testKeepAliveStateStartsWithClose", testKeepAliveStateStartsWithClose),
                ("testKeepAliveStateStartsWithKeepAlive", testKeepAliveStateStartsWithKeepAlive),
                ("testKeepAliveStateHasKeepAlive", testKeepAliveStateHasKeepAlive),
                ("testKeepAliveStateHasClose", testKeepAliveStateHasClose),
                ("testRandomAccess", testRandomAccess),
                ("testCanBeSeededWithKeepAliveState", testCanBeSeededWithKeepAliveState),
                ("testSeedDominatesActualValue", testSeedDominatesActualValue),
                ("testSeedDominatesEvenAfterMutation", testSeedDominatesEvenAfterMutation),
                ("testSeedGetsUpdatedToDefaultOnConnectionHeaderModification", testSeedGetsUpdatedToDefaultOnConnectionHeaderModification),
                ("testSeedGetsUpdatedToWhateverTheHeaderSaysIfPresent", testSeedGetsUpdatedToWhateverTheHeaderSaysIfPresent),
                ("testWeDefaultToCloseIfDoesNotMakeSense", testWeDefaultToCloseIfDoesNotMakeSense),
                ("testAddingSequenceOfPairs", testAddingSequenceOfPairs),
                ("testAddingOtherHTTPHeader", testAddingOtherHTTPHeader),
           ]
   }
}

