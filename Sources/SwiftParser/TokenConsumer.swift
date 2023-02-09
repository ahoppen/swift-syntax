//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_spi(RawSyntax) import SwiftSyntax

/// A type that consumes  instances of `TokenSyntax`.
@_spi(RawSyntax)
public protocol TokenConsumer {
  associatedtype Token
  /// The current token syntax being examined by the consumer
  var currentToken: Lexer.Lexeme { get }
  /// Whether the current token matches the given kind.
  mutating func consumeAnyToken() -> Token

  /// Consume the current token and change its token kind to `remappedTokenKind`.
  mutating func consumeAnyToken(remapping remappedTokenKind: RawTokenKind) -> Token

  /// Synthesize a missing token with `kind`.
  /// If `text` is not `nil`, use it for the token's text, otherwise use the token's default text.
  mutating func missingToken(_ kind: RawTokenKind, text: SyntaxText?) -> Token

  /// Return the lexeme that will be parsed next.
  func peek() -> Lexer.Lexeme

  func lookahead() -> Parser.Lookahead

  #if ENABLE_FUZZING_INTERSPECTION
  /// When we are compiling the parser to be used with libFuzzer, we can record
  /// alternative tokens that the parser was looking for at specific offsets.
  ///
  /// I.e. if at offset 33, we issue an `at(.leftParen)` call, this will record
  /// that `.leftParen` is an interesting token at offset 33. This allows the
  /// fuzzing mutator to prefer replacing the current token at offset 33 by a
  /// left paren, because apparently this would be a code path that the parser
  /// is interested in.
  mutating func recordAlternativeTokenChoice(for lexeme: Lexer.Lexeme, choices: [RawTokenKind])
  #endif
}

// MARK: Checking if we are at one specific token (`at`)

/// After calling `consume(ifAnyFrom:)` we know which token we are positioned
/// at based on that function's return type. This handle allows consuming that
/// token.
struct TokenConsumptionHandle {
  /// The kind that is expected to be consumed if the handle is eaten.
  var tokenKind: RawTokenKind
  /// When not `nil`, the token's kind will be remapped to this kind when consumed.
  var remappedKind: RawTokenKind?
  /// If `true`, the token we should consume should be synthesized as a missing token
  /// and no tokens should be consumed.
  var missing: Bool = false
}

extension TokenConsumer {
  /// Returns whether the the current token is one of the specified kinds, and,
  /// in case `allowTokenAtStartOfLine` is false, whether the current token is
  /// not on a newline.
  public mutating func at(
    _ kind: RawTokenKind,
    allowTokenAtStartOfLine: Bool = true
  ) -> Bool {
    #if ENABLE_FUZZING_INTERSPECTION
    recordAlternativeTokenChoice(for: self.currentToken, choices: [kind])
    #endif
    if !allowTokenAtStartOfLine && self.currentToken.isAtStartOfLine {
      return false
    }
    return RawTokenKindMatch(kind) ~= self.currentToken
  }

  /// Returns whether the the current token is one of the specified kinds, and,
  /// in case `allowTokenAtStartOfLine` is false, whether the current token is
  /// not on a newline.
  public mutating func at(
    _ kind1: RawTokenKind,
    _ kind2: RawTokenKind,
    allowTokenAtStartOfLine: Bool = true
  ) -> Bool {
    if !allowTokenAtStartOfLine && self.currentToken.isAtStartOfLine {
      return false
    }
    #if ENABLE_FUZZING_INTERSPECTION
    recordAlternativeTokenChoice(for: self.currentToken, choices: [kind1, kind2])
    #endif
    switch self.currentToken {
    case RawTokenKindMatch(kind1): return true
    case RawTokenKindMatch(kind2): return true
    default: return false
    }
  }

  /// Returns whether the the current token is one of the specified kinds, and,
  /// in case `allowTokenAtStartOfLine` is false, whether the current token is
  /// not on a newline.
  public mutating func at(
    _ kind1: RawTokenKind,
    _ kind2: RawTokenKind,
    _ kind3: RawTokenKind,
    allowTokenAtStartOfLine: Bool = true
  ) -> Bool {
    if !allowTokenAtStartOfLine && self.currentToken.isAtStartOfLine {
      return false
    }
    #if ENABLE_FUZZING_INTERSPECTION
    recordAlternativeTokenChoice(for: self.currentToken, choices: [kind1, kind2, kind3])
    #endif
    switch self.currentToken {
    case RawTokenKindMatch(kind1): return true
    case RawTokenKindMatch(kind2): return true
    case RawTokenKindMatch(kind3): return true
    default: return false
    }
  }

  /// Returns whether the current token is an operator with the given `name`.
  @_spi(RawSyntax)
  public mutating func atContextualPunctuator(_ name: SyntaxText) -> Bool {
    return self.currentToken.isContextualPunctuator(name)
  }

  /// Returns whether the kind of the current token is any of the given
  /// kinds and additionally satisfies `condition`.
  ///
  /// - Parameter kinds: The kinds to test for.
  /// - Parameter condition: An additional condition that must be satisfied for
  ///                        this function to return `true`.
  /// - Returns: `true` if the current token's kind is in `kinds`.
  @_spi(RawSyntax)
  public mutating func at(
    any kinds: [RawTokenKind],
    allowTokenAtStartOfLine: Bool = true
  ) -> Bool {
    if !allowTokenAtStartOfLine && self.currentToken.isAtStartOfLine {
      return false
    }
    return kinds.contains(where: { RawTokenKindMatch($0) ~= self.currentToken })
  }

  /// Checks whether the parser is currently positioned at any token in `Subset`.
  /// If this is the case, return the `Subset` case that the parser is positioned in
  /// as well as a handle to consume that token.
  mutating func at<Subset: RawTokenKindSubset>(anyIn subset: Subset.Type) -> (Subset, TokenConsumptionHandle)? {
    #if ENABLE_FUZZING_INTERSPECTION
    recordAlternativeTokenChoice(for: self.currentToken, choices: subset.allCases.map(\.rawTokenKind))
    #endif
    if let matchedKind = Subset(lexeme: self.currentToken) {
      return (
        matchedKind,
        TokenConsumptionHandle(
          tokenKind: matchedKind.rawTokenKind,
          remappedKind: matchedKind.remappedKind
        )
      )
    }
    return nil
  }

  /// Eat a token that we know we are currently positioned at, based on `at(anyIn:)`.
  mutating func eat(_ handle: TokenConsumptionHandle) -> Token {
    if handle.missing {
      return missingToken(handle.remappedKind ?? handle.tokenKind, text: nil)
    } else if let remappedKind = handle.remappedKind {
      assert(self.at(handle.tokenKind))
      return consumeAnyToken(remapping: remappedKind)
    } else if handle.tokenKind.base == .keyword {
      // We support remapping identifiers to contextual keywords
      assert(self.currentToken.rawTokenKind == .identifier || self.currentToken.rawTokenKind == handle.tokenKind)
      return consumeAnyToken(remapping: handle.tokenKind)
    } else {
      assert(self.at(handle.tokenKind))
      return consumeAnyToken()
    }
  }

  public func withLookahead<T>(_ body: (_: inout Parser.Lookahead) -> T) -> T {
    var lookahead = lookahead()
    return body(&lookahead)
  }
}

// MARK: Consuming tokens (`consume`)

extension TokenConsumer {
  /// If the current token is of the given kind and, if `allowTokenAtStartOfLine`
  /// is `false`, if the token is not at the start of a line, consume the token
  /// and return it. Otherwise return `nil`. If `remapping` is not `nil`, the
  /// returned token's kind will be changed to `remapping`.
  @_spi(RawSyntax)
  public mutating func consume(
    if kind: RawTokenKind,
    remapping: RawTokenKind? = nil,
    allowTokenAtStartOfLine: Bool = true
  ) -> Token? {
    if self.at(kind, allowTokenAtStartOfLine: allowTokenAtStartOfLine) {
      if case RawTokenKindMatch(kind) = self.currentToken {
        if let remapping = remapping {
          return self.consumeAnyToken(remapping: remapping)
        } else if kind.base == .keyword {
          return self.consumeAnyToken(remapping: kind)
        } else {
          return self.consumeAnyToken()
        }
      }
    }
    return nil
  }

  /// If the current token is of the given kind and, if `allowTokenAtStartOfLine`
  /// is `false`, if the token is not at the start of a line, consume the token
  /// and return it. Otherwise return `nil`. If `remapping` is not `nil`, the
  /// returned token's kind will be changed to `remapping`.
  @_spi(RawSyntax)
  public mutating func consume(
    if kind1: RawTokenKind,
    _ kind2: RawTokenKind,
    remapping: RawTokenKind? = nil,
    allowTokenAtStartOfLine: Bool = true
  ) -> Token? {
    if let token = consume(if: kind1, remapping: remapping, allowTokenAtStartOfLine: allowTokenAtStartOfLine) {
      return token
    } else if let token = consume(if: kind2, remapping: remapping, allowTokenAtStartOfLine: allowTokenAtStartOfLine) {
      return token
    } else {
      return nil
    }
  }

  /// If the current token is of the given kind and, if `allowTokenAtStartOfLine`
  /// is `false`, if the token is not at the start of a line, consume the token
  /// and return it. Otherwise return `nil`. If `remapping` is not `nil`, the
  /// returned token's kind will be changed to `remapping`.
  @_spi(RawSyntax)
  public mutating func consume(
    if kind1: RawTokenKind,
    _ kind2: RawTokenKind,
    _ kind3: RawTokenKind,
    remapping: RawTokenKind? = nil,
    allowTokenAtStartOfLine: Bool = true
  ) -> Token? {
    if let token = consume(if: kind1, remapping: remapping, allowTokenAtStartOfLine: allowTokenAtStartOfLine) {
      return token
    } else if let token = consume(if: kind2, remapping: remapping, allowTokenAtStartOfLine: allowTokenAtStartOfLine) {
      return token
    } else if let token = consume(if: kind3, remapping: remapping, allowTokenAtStartOfLine: allowTokenAtStartOfLine) {
      return token
    } else {
      return nil
    }
  }

  /// Consumes and returns the current token is an operator with the given `name`.
  @_spi(RawSyntax)
  public mutating func consumeIfContextualPunctuator(_ name: SyntaxText, remapping: RawTokenKind? = nil) -> Token? {
    if self.atContextualPunctuator(name) {
      if let remapping = remapping {
        return self.consumeAnyToken(remapping: remapping)
      } else {
        return self.consumeAnyToken()
      }
    }
    return nil
  }

  /// If the current token has `kind1` and is followed by `kind2` consume both
  /// tokens and return them. Otherwise, return `nil`.
  @_spi(RawSyntax)
  public mutating func consume(if kind1: RawTokenKind, followedBy kind2: RawTokenKind) -> (Token, Token)? {
    if self.at(kind1) && self.peek().rawTokenKind == kind2 {
      return (consumeAnyToken(), consumeAnyToken())
    } else {
      return nil
    }
  }

  /// If the current token satisfies `condition1` and the next token satisfies
  /// `condition2` consume both tokens and return them.
  /// Otherwise, return `nil`.
  @_spi(RawSyntax)
  public mutating func consume(
    if condition1: (Lexer.Lexeme) -> Bool,
    followedBy condition2: (Lexer.Lexeme) -> Bool
  ) -> (Token, Token)? {
    if condition1(self.currentToken) && condition2(self.peek()) {
      return (consumeAnyToken(), consumeAnyToken())
    } else {
      return nil
    }
  }

  mutating func consume<Subset: RawTokenKindSubset>(ifAnyIn subset: Subset.Type) -> Self.Token? {
    if let (_, handle) = self.at(anyIn: subset) {
      return self.eat(handle)
    } else {
      return nil
    }
  }
}

// MARK: Expecting Tokens (`expect`)

extension TokenConsumer {
  /// If the current token matches the given `kind` and additionally satisfies
  /// `condition`, consume it. Othwerise, synthesize a missing token of the
  /// given `kind`.
  ///
  /// This method does not try to eat unexpected until it finds the token of the specified `kind`.
  /// In the parser, `expect` should be preferred.
  ///
  /// - Parameter kind: The kind of token to consume.
  /// - Parameter condition: An additional condition that must be satisfied for
  ///                        the token to be consumed.
  /// - Returns: A token of the given kind.
  public mutating func expectWithoutRecovery(_ kind: RawTokenKind) -> Token {
    if let token = self.consume(if: kind) {
      return token
    } else {
      return missingToken(kind, text: nil)
    }
  }
}

// MARK: Convenience functions

extension TokenConsumer {
  mutating func expectIdentifierWithoutRecovery() -> Token {
    if let (_, handle) = self.at(anyIn: IdentifierTokens.self) {
      return self.eat(handle)
    }
    return missingToken(.identifier, text: nil)
  }

  mutating func expectIdentifierOrRethrowsWithoutRecovery() -> Token {
    if let (_, handle) = self.at(anyIn: IdentifierOrRethrowsTokens.self) {
      return self.eat(handle)
    }
    return missingToken(.identifier, text: nil)
  }
}
