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
  public var indentationStack: [Trivia]

  /// The trivia by which tokens should currently be indented.
  public var currentIndentationLevel: Trivia {
    return indentationStack.last!
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
    viewMode: SyntaxTreeViewMode = .sourceAccurate,
  ) {
    self.indentationIncrement = indentationIncrement
    self.indentationStack = [initialIndentation]
    self.viewMode = viewMode
  }

  // MARK: - Updating indentation level

  public func pushIndentationLevel(increasingIndentationBy: Trivia) {
    indentationStack.append(currentIndentationLevel + increasingIndentationBy)
  }

  public func popIndentationLevel() {
    indentationStack.removeLast()
  }

  open override func visitPre(_ node: Syntax) {
    if requiresIndent(node) {
      if let firstToken = node.firstToken(viewMode: viewMode),
        let tokenIndentation = firstToken.leadingTrivia.indentation(isOnNewline: false),
        !tokenIndentation.isEmpty
      {
        // If the first token in this block is indented, infer the indentation level from it.
        pushIndentationLevel(increasingIndentationBy: tokenIndentation)
      } else {
        pushIndentationLevel(increasingIndentationBy: indentationIncrement)
      }
    }
  }

  open override func visitPost(_ node: Syntax) {
    if requiresIndent(node) {
      popIndentationLevel()
    }
  }

  // MARK: - Indentation behavior customization points

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

  /// Whether a leading space on `token` should be added.
  open func requiresLeadingBlank(_ token: TokenSyntax) -> Bool {
    switch (token.previousToken(viewMode: .sourceAccurate)?.tokenKind, token.tokenKind) {
    case (.leftParen, .leftBrace):  // Ensures there is not a space in `.map({ $0.foo })`
      return false
    default:
      break
    }

    return token.requiresLeadingSpace
  }

  /// Whether a trailing space on `token` should be added.
  open func requiresTrailingBlank(_ token: TokenSyntax) -> Bool {
    switch (token.tokenKind, token.nextToken(viewMode: .sourceAccurate)?.tokenKind) {
    case (.exclamationMark, .leftParen),  // Ensures there is not a space in `myOptionalClosure!()`
      (.exclamationMark, .period),  // Ensures there is not a space in `myOptionalBar!.foo()`
      (.keyword(.as), .exclamationMark),  // Ensures there is not a space in `as!`
      (.keyword(.as), .postfixQuestionMark),  // Ensures there is not a space in `as?`
      (.keyword(.try), .exclamationMark),  // Ensures there is not a space in `try!`
      (.keyword(.try), .postfixQuestionMark),  // Ensures there is not a space in `try?`:
      (.postfixQuestionMark, .leftParen),  // Ensures there is not a space in `init?()` or `myOptionalClosure?()`s
      (.postfixQuestionMark, .rightAngle),  // Ensures there is not a space in `ContiguousArray<RawSyntax?>`
      (.postfixQuestionMark, .rightParen):  // Ensures there is not a space in `myOptionalClosure?()`
      return false
    default:
      break
    }

    return token.requiresTrailingSpace
  }

  // MARK: - Formatting a token

  open override func visit(_ token: TokenSyntax) -> TokenSyntax {
    lazy var previousTokenWillEndWithBlank: Bool = {
      guard let previousToken = token.previousToken(viewMode: viewMode) else {
        return false
      }
      return previousToken.trailingTrivia.pieces.last?.isBlank ?? false
        || requiresTrailingBlank(previousToken)
    }()

    lazy var previousTokenWillEndInNewline: Bool = {
      guard let previousToken = token.previousToken(viewMode: viewMode) else {
        // Assume that the start of the tree is equivalent to a newline so we
        // don't add a leading newline to the file.
        return true
      }
      return previousToken.trailingTrivia.pieces.last?.isNewline ?? false
    }()

    lazy var nextTokenWillStartWithBlank: Bool = {
      guard let nextToken = token.nextToken(viewMode: viewMode) else {
        return false
      }
      return nextToken.leadingTrivia.first?.isBlank ?? false
        || requiresLeadingBlank(nextToken)
        || requiresLeadingNewline(nextToken)
    }()

    lazy var nextTokenWillStartWithNewline: Bool = {
      guard let nextToken = token.nextToken(viewMode: viewMode) else {
        return false
      }
      return nextToken.leadingTrivia.first?.isNewline ?? false
        || requiresLeadingNewline(nextToken)
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

    leadingTrivia = leadingTrivia.indented(indentation: leadingTriviaIndentation, isOnNewline: false)
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
