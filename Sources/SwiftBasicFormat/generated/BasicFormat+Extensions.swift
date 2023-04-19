//// Automatically generated by generate-swiftsyntax
//// Do not edit directly!
//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSyntax

public extension SyntaxProtocol {
  var requiresIndent: Bool {
    guard let keyPath = keyPathInParent else {
      return false
    }
    return keyPath.requiresIndent
  }
}

public extension TokenSyntax {
  var requiresLeadingNewline: Bool {
    if let keyPath = keyPathInParent, keyPath.requiresLeadingNewline {
      return true
    }
    return false
  }
  
  var requiresLeadingSpace: Bool {
    if let keyPath = keyPathInParent, let requiresLeadingSpace = keyPath.requiresLeadingSpace {
      return requiresLeadingSpace
    }
    switch tokenKind {
    case .arrow:
      return true
    case .binaryOperator:
      return true
    case .equal:
      return true
    case .leftBrace:
      return true
    case .keyword(.`catch`):
      return true
    case .keyword(.`else`):
      return true
    case .keyword(.`in`):
      return true
    case .keyword(.`where`):
      return true
    default:
      return false
    }
  }
  
  var requiresTrailingSpace: Bool {
    if let keyPath = keyPathInParent, let requiresTrailingSpace = keyPath.requiresTrailingSpace {
      return requiresTrailingSpace
    }
    switch tokenKind {
    case .arrow:
      return true
    case .binaryOperator:
      return true
    case .colon:
      return true
    case .comma:
      return true
    case .equal:
      return true
    case .poundAvailableKeyword:
      return true
    case .poundElseKeyword:
      return true
    case .poundElseifKeyword:
      return true
    case .poundEndifKeyword:
      return true
    case .poundIfKeyword:
      return true
    case .poundSourceLocationKeyword:
      return true
    case .poundUnavailableKeyword:
      return true
    case .keyword(.`Any`):
      return true
    case .keyword(.`as`):
      return true
    case .keyword(.`associatedtype`):
      return true
    case .keyword(.async):
      return true
    case .keyword(.await):
      return true
    case .keyword(.`break`):
      return true
    case .keyword(.`case`):
      return true
    case .keyword(.`class`):
      return true
    case .keyword(.`continue`):
      return true
    case .keyword(.`defer`):
      return true
    case .keyword(.`else`):
      return true
    case .keyword(.`enum`):
      return true
    case .keyword(.`extension`):
      return true
    case .keyword(.`fallthrough`):
      return true
    case .keyword(.`fileprivate`):
      return true
    case .keyword(.`for`):
      return true
    case .keyword(.`func`):
      return true
    case .keyword(.`guard`):
      return true
    case .keyword(.`if`):
      return true
    case .keyword(.`import`):
      return true
    case .keyword(.`in`):
      return true
    case .keyword(.`inout`):
      return true
    case .keyword(.`internal`):
      return true
    case .keyword(.`is`):
      return true
    case .keyword(.`let`):
      return true
    case .keyword(.`operator`):
      return true
    case .keyword(.`precedencegroup`):
      return true
    case .keyword(.`private`):
      return true
    case .keyword(.`protocol`):
      return true
    case .keyword(.`public`):
      return true
    case .keyword(.`repeat`):
      return true
    case .keyword(.`rethrows`):
      return true
    case .keyword(.`return`):
      return true
    case .keyword(.`static`):
      return true
    case .keyword(.`struct`):
      return true
    case .keyword(.`subscript`):
      return true
    case .keyword(.`switch`):
      return true
    case .keyword(.`throw`):
      return true
    case .keyword(.`throws`):
      return true
    case .keyword(.`try`):
      return true
    case .keyword(.`typealias`):
      return true
    case .keyword(.`var`):
      return true
    case .keyword(.`where`):
      return true
    case .keyword(.`while`):
      return true
    default:
      return false
    }
  }
}

fileprivate extension AnyKeyPath {
  var requiresIndent: Bool {
    switch self {
    case \AccessorBlockSyntax.accessors:
      return true
    case \ArrayExprSyntax.elements:
      return true
    case \ClosureExprSyntax.statements:
      return true
    case \ClosureParameterClauseSyntax.parameterList:
      return true
    case \CodeBlockSyntax.statements:
      return true
    case \DictionaryElementSyntax.valueExpression:
      return true
    case \DictionaryExprSyntax.content:
      return true
    case \EnumCaseParameterClauseSyntax.parameterList:
      return true
    case \FunctionCallExprSyntax.argumentList:
      return true
    case \FunctionTypeSyntax.arguments:
      return true
    case \MemberDeclBlockSyntax.members:
      return true
    case \ParameterClauseSyntax.parameterList:
      return true
    case \SwitchCaseSyntax.statements:
      return true
    case \TupleExprSyntax.elementList:
      return true
    case \TupleTypeSyntax.elements:
      return true
    default:
      return false
    }
  }
  
  var requiresLeadingNewline: Bool {
    switch self {
    case \AccessorBlockSyntax.rightBrace:
      return true
    case \ClosureExprSyntax.rightBrace:
      return true
    case \CodeBlockSyntax.rightBrace:
      return true
    case \IfConfigClauseSyntax.poundKeyword:
      return true
    case \IfConfigDeclSyntax.poundEndif:
      return true
    case \MemberDeclBlockSyntax.rightBrace:
      return true
    case \SwitchExprSyntax.rightBrace:
      return true
    default:
      return false
    }
  }
  
  var requiresLeadingSpace: Bool? {
    switch self {
    case \AvailabilityArgumentSyntax.entry:
      return false
    case \FunctionParameterSyntax.secondName:
      return true
    case \MissingExprSyntax.placeholder:
      return false
    case \MissingPatternSyntax.placeholder:
      return false
    case \MissingStmtSyntax.placeholder:
      return false
    case \MissingTypeSyntax.placeholder:
      return false
    default:
      return nil
    }
  }
  
  var requiresTrailingSpace: Bool? {
    switch self {
    case \AvailabilityArgumentSyntax.entry:
      return false
    case \BreakStmtSyntax.breakKeyword:
      return false
    case \DeclNameArgumentSyntax.colon:
      return false
    case \DictionaryExprSyntax.content:
      return false
    case \DynamicReplacementArgumentsSyntax.forLabel:
      return false
    case \MissingExprSyntax.placeholder:
      return false
    case \MissingPatternSyntax.placeholder:
      return false
    case \MissingStmtSyntax.placeholder:
      return false
    case \MissingTypeSyntax.placeholder:
      return false
    case \SwitchCaseLabelSyntax.colon:
      return false
    case \SwitchDefaultLabelSyntax.colon:
      return false
    case \TryExprSyntax.questionOrExclamationMark:
      return true
    default:
      return nil
    }
  }
}
