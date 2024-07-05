//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import SwiftDiagnostics
import SwiftIfConfig
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacrosGenericTestSupport
import XCTest

public class ActiveRegionTests: XCTestCase {
  let linuxBuildConfig = TestingBuildConfiguration(
    customConditions: ["DEBUG", "ASSERTS"],
    features: ["ParameterPacks"],
    attributes: ["available"]
  )

  func testActiveRegions() throws {
    try assertActiveCode(
      """
      #if DEBUG
      0️⃣func f()
      #elseif ASSERTS
      1️⃣func g()

      #if compiler(>=8.0)
      2️⃣func h()
      #else
      3️⃣var i
      #endif
      #endif
      """,
      configuration: linuxBuildConfig,
      states: [
        "0️⃣": .active,
        "1️⃣": .inactive,
        "2️⃣": .unparsed,
        "3️⃣": .inactive,
      ]
    )
  }
}
