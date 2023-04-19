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

open class BasicFormat: SyntaxRewriter {
  /// How much indentation should be added at a new indentation level.
  public let indentationIncrement: Trivia

  /// As we reach a new indendation level, its indentation will be added to the
  /// stack. As we exit that indentation level, the indendation will be popped.
  /// `isUserDefined` is `true` if the indentation was inferred from something
  /// the user provided manually instead of being inferred from the nesting
  /// level.
  public var indentationStack: [(indentation: Trivia, isUserDefined: Bool)]

  /// The trivia by which tokens should currently be indented.
  public var currentIndentationLevel: Trivia {
    return indentationStack.last!.indentation
  }

  /// For every token that is being put on a new line but did not have
  /// user-specified indentation, the generated indentation.
  ///
  /// This is used as a reference-point to indent user-indented code.
  var anchorPoints: [TokenSyntax: Trivia] = [:]

  public let viewMode: SyntaxTreeViewMode

  public init(
    indentationIncrement: Trivia = .spaces(4),
    initialIndentation: Trivia = [],
    viewMode: SyntaxTreeViewMode = .sourceAccurate
  ) {
    self.indentationIncrement = indentationIncrement
    self.indentationStack = [(indentation: initialIndentation, isUserDefined: false)]
    self.viewMode = viewMode
  }

  // MARK: - Updating indentation level

  public func increaseIndentationLevel() {
    indentationStack.append((currentIndentationLevel + indentationIncrement, false))
  }

  public func decreaseIndentationLevel() {
    indentationStack.removeLast()
  }

  open override func visitPre(_ node: Syntax) {
    if requiresIndent(node) {
      if let firstToken = node.firstToken(viewMode: viewMode),
        let tokenIndentation = firstToken.leadingTrivia.indentation(isOnNewline: false),
        !tokenIndentation.isEmpty
      {
        // If the first token in this block is indented, infer the indentation level from it.
        let lastNonUserDefinedIndentation = indentationStack.last(where: { !$0.isUserDefined })!.indentation
        indentationStack.append((indentation: lastNonUserDefinedIndentation + tokenIndentation, isUserDefined: true))
      } else {
        increaseIndentationLevel()
      }
    }
  }

  open override func visitPost(_ node: Syntax) {
    if requiresIndent(node) {
      decreaseIndentationLevel()
    }
  }

  // MARK: - Customization points

  /// Whether a leading newline on `token` should be added.
  open func requiresIndent<T: SyntaxProtocol>(_ node: T) -> Bool {
    return node.requiresIndent
  }

  private func isInsideStringInterpolation(_ token: TokenSyntax) -> Bool {
    var ancestor: Syntax = Syntax(token)
    while let parent = ancestor.parent {
      ancestor = parent
      if ancestor.is(ExpressionSegmentSyntax.self) {
        return true
      }
    }
    return false
  }

  /// Whether a leading newline on `token` should be added.
  open func requiresLeadingNewline(_ token: TokenSyntax) -> Bool {
    // We don't want to add newlines inside string interpolation
    if isInsideStringInterpolation(token) {
      return false
    }

    var ancestor: Syntax = Syntax(token)
    while let parent = ancestor.parent {
      ancestor = parent
      if ancestor.firstToken(viewMode: viewMode) != token {
        break
      }
      if let ancestorsParent = ancestor.parent, childrenSeparatedByNewline(ancestorsParent) {
        return true
      }
    }

    return token.requiresLeadingNewline
  }

  open func childrenSeparatedByNewline(_ node: Syntax) -> Bool {
    switch node.as(SyntaxEnum.self) {
    case .accessorList:
      return true
    case .codeBlockItemList:
      return true
    case .memberDeclList:
      return true
    case .switchCaseList:
      return true
    default:
      return false
    }
  }

  /// Whether a `first` and `second` need to be separated by a space.
  open func requiresBlank(between first: TokenSyntax?, and second: TokenSyntax?) -> Bool {
    switch first?.tokenKind {
    case nil,
      .eof,
      .atSign,
      .backslash,
      .backtick,
      .extendedRegexDelimiter,
      .leftAngle,
      .leftBrace,
      .leftParen,
      .leftSquareBracket,
      .multilineStringQuote,
      .period,
      .pound,
      .prefixAmpersand,
      .prefixOperator,
      .rawStringDelimiter,
      .regexLiteralPattern,
      .regexSlash,
      .singleQuote,
      .stringQuote,
      .stringSegment:
      return false
    default:
      break
    }
    switch second?.tokenKind {
    case nil,
      .eof,
      .colon,
      .comma,
      .ellipsis,
      .exclamationMark,
      .postfixOperator,
      .postfixQuestionMark,
      .rightAngle,
      .rightBrace,
      .rightParen,
      .rightSquareBracket,
      .semicolon:
      return false
    default:
      break
    }

    switch (first?.tokenKind, second?.tokenKind) {
    case (.exclamationMark, .leftParen),  // myOptionalClosure!()
      (.exclamationMark, .period),  // myOptionalBar!.foo()
      (.keyword(.as), .exclamationMark),  // as!
      (.keyword(.as), .postfixQuestionMark),  // as?
      (.keyword(.try), .exclamationMark),  // try!
      (.keyword(.try), .postfixQuestionMark),  // try?`
      (.postfixQuestionMark, .leftParen),  // init?() or myOptionalClosure?()
      (.postfixQuestionMark, .rightAngle),  // ContiguousArray<RawSyntax?>
      (.postfixQuestionMark, .rightParen),  // myOptionalClosure?()
      (.identifier, .leftParen),  // foo()
      (.identifier, .period),  // a.b
      (.dollarIdentifier, .period),  // a.b
      (.keyword(.self), .period),  // self.someProperty
      (.keyword(.Self), .period),  // self.someProperty
      (.keyword(.`init`), .leftParen),  // init()
      (.rightParen, .period),  // foo().bar
      (.identifier, .leftAngle),  // MyType<Int>
      (.rightAngle, .leftParen),  // func foo<T>(x: T)
      (.keyword(.subscript), .leftParen),  // subscript(x: Int)
      (.keyword(.super), .period),  // super.someProperty
      (.poundUnavailableKeyword, .leftParen),  // #unavailable(...)
      (.identifier, .leftSquareBracket),  // myArray[1]
      (.rightSquareBracket, .period),  // myArray[1].someProperty
      (.keyword(.`init`), .leftAngle),  // init<T>()
      (.keyword(.set), .leftParen),  // var mYar: Int { set(value) {} }
      (.postfixQuestionMark, .leftAngle),  // init?<T>()
      (.rightParen, .leftParen),  // returnsClosure()()
      (.postfixQuestionMark, .period):  // someOptional?.someProperty
      return false
    default:
      break
    }

    switch first?.keyPathInParent {
    case \ExpressionSegmentSyntax.backslash,
      \ExpressionSegmentSyntax.rightParen,
      \DeclNameArgumentSyntax.colon:
      return false
    default:
      break
    }

    return true
  }

  /// Whether the formatter should consider this token as being mutable.
  /// This allows the diagnostic generator to only assume that missing nodes
  /// will be mutated. Thus, if two tokens need to be separated by a space, it
  /// will not be assumed that the space is added to an immutable previous node.
  open func isMutable(_ token: TokenSyntax) -> Bool {
    return true
  }

  // MARK: - Formatting a token

  private func requiresLeadingBlank(_ token: TokenSyntax) -> Bool {
    return requiresBlank(between: token.previousToken(viewMode: viewMode), and: token)
  }

  private func requiresTrailingBlank(_ token: TokenSyntax) -> Bool {
    return requiresBlank(between: token, and: token.nextToken(viewMode: viewMode))
  }

  open override func visit(_ token: TokenSyntax) -> TokenSyntax {
    lazy var previousTokenWillEndWithBlank: Bool = {
      guard let previousToken = token.previousToken(viewMode: viewMode) else {
        return false
      }
      return previousToken.trailingTrivia.pieces.last?.isBlank ?? false
        || (requiresTrailingBlank(previousToken) && isMutable(previousToken))
    }()

    lazy var previousTokenWillEndInNewline: Bool = {
      guard let previousToken = token.previousToken(viewMode: viewMode) else {
        // Assume that the start of the tree is equivalent to a newline so we
        // don't add a leading newline to the file.
        return true
      }
      if previousToken.trailingTrivia.pieces.last?.isNewline ?? false {
        return true
      }
      if case .stringSegment(let segment) = previousToken.tokenKind, segment.last?.isNewline ?? false {
        return true
      }
      return false
    }()

    lazy var previousTokenIsStringLiteralEndingInNewline: Bool = {
      guard let previousToken = token.previousToken(viewMode: viewMode) else {
        // Assume that the start of the tree is equivalent to a newline so we
        // don't add a leading newline to the file.
        return true
      }
      if case .stringSegment(let segment) = previousToken.tokenKind, segment.last?.isNewline ?? false {
        return true
      }
      return false
    }()

    lazy var nextTokenWillStartWithBlank: Bool = {
      guard let nextToken = token.nextToken(viewMode: viewMode) else {
        return false
      }
      return nextToken.leadingTrivia.first?.isBlank ?? false
        || (requiresLeadingBlank(nextToken) && isMutable(nextToken))
        || (requiresLeadingNewline(nextToken) && isMutable(nextToken))
    }()

    lazy var nextTokenWillStartWithNewline: Bool = {
      guard let nextToken = token.nextToken(viewMode: viewMode) else {
        return false
      }
      return nextToken.leadingTrivia.first?.isNewline ?? false
        || (requiresLeadingNewline(nextToken) && isMutable(nextToken))
    }()

    lazy var trailingTriviaAndNextTokensLeadingTriviaWhitespace: Trivia = {
      let nextToken = token.nextToken(viewMode: viewMode)
      let nextTokenLeadingWhitespace = nextToken?.leadingTrivia.prefix(while: { $0.isIndentationWhitespace }) ?? []
      return trailingTrivia + Trivia(pieces: nextTokenLeadingWhitespace)
    }()

    var leadingTrivia = token.leadingTrivia
    var trailingTrivia = token.trailingTrivia

    if requiresLeadingNewline(token) {
      // Add a leading newline if the token requires it unless
      //  - it already starts with a newline or
      //  - the previous token ends with a newline
      if !(leadingTrivia.first?.isNewline ?? false) && !previousTokenWillEndInNewline {
        // Add a leading newline if the token requires it and
        //  - it doesn't already start with a newline and
        //  - the previous token didn't end with a newline
        leadingTrivia = .newline + leadingTrivia
      }
    } else if requiresLeadingBlank(token) {
      // Add a leading space if the token requires it unless
      //  - it already starts with a blank or
      //  - the previous token ends with a blank after the rewrite
      if !(leadingTrivia.first?.isBlank ?? false) && !previousTokenWillEndWithBlank {
        leadingTrivia += .space
      }
    }

    if leadingTrivia.indentation(isOnNewline: previousTokenWillEndInNewline) == [] {
      // If the token starts on a new line and does not have indentation, this
      // is the last non-indented token. Store its indentation level
      anchorPoints[token] = currentIndentationLevel
    }

    // Add a trailing space to the token unless
    //  - it already ends with a blank or
    //  - the next token will start starts with a newline after the rewrite
    //    because newlines should be preferred to spaces as a blank
    if requiresTrailingBlank(token)
      && !(trailingTrivia.pieces.last?.isBlank ?? false)
      && !nextTokenWillStartWithNewline
    {
      trailingTrivia += .space
    }

    var leadingTriviaIndentation = self.currentIndentationLevel
    var trailingTriviaIndentation = self.currentIndentationLevel

    // If the trivia contain user-defined indentation, find their anchor point
    // and indent the token relative to that anchor point.
    if leadingTrivia.containsIndentation(isOnNewline: previousTokenWillEndInNewline),
      let anchorPointIndentation = self.anchorPointIndentation(for: token)
    {
      leadingTriviaIndentation = anchorPointIndentation
    }
    if trailingTriviaAndNextTokensLeadingTriviaWhitespace.containsIndentation(isOnNewline: previousTokenWillEndInNewline),
      let anchorPointIndentation = self.anchorPointIndentation(for: token)
    {
      trailingTriviaIndentation = anchorPointIndentation
    }

    leadingTrivia = leadingTrivia.indented(indentation: leadingTriviaIndentation, isOnNewline: previousTokenIsStringLiteralEndingInNewline)
    trailingTrivia = trailingTrivia.indented(indentation: trailingTriviaIndentation, isOnNewline: false)

    leadingTrivia = leadingTrivia.trimingTrailingBlanksBeforeNewline(isBeforeNewline: false)
    trailingTrivia = trailingTrivia.trimingTrailingBlanksBeforeNewline(isBeforeNewline: nextTokenWillStartWithNewline)

    return token.with(\.leadingTrivia, leadingTrivia).with(\.trailingTrivia, trailingTrivia)
  }

  /// If `token` is indented by the user, Find the anchor point to which the
  /// user-defined indentation is relative to.
  /// The anchor point to use is the innermost token that was put on a new line
  /// and starts one of the token's immediate parents.
  private func anchorPointIndentation(for token: TokenSyntax) -> Trivia? {
    var ancestor: Syntax = Syntax(token)
    while let parent = ancestor.parent {
      ancestor = parent
      if let firstToken = parent.firstToken(viewMode: viewMode),
        let anchorPointIndentation = anchorPoints[firstToken]
      {
        return anchorPointIndentation
      }
    }
    return nil
  }
}
