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

extension Trivia {
  /// Removes all blanks that is trailing before a newline trivia,
  /// effectively making sure that lines don't end with a blank
  func trimingTrailingBlanksBeforeNewline(isBeforeNewline: Bool) -> Trivia {
    // Iterate through the trivia in reverse. Every time we see a newline drop
    // all blanks until we see a non-blank trivia piece.
    var isBeforeNewline = isBeforeNewline
    var trimmedReversedPieces: [TriviaPiece] = []
    for piece in pieces.reversed() {
      if piece.isNewline {
        isBeforeNewline = true
        trimmedReversedPieces.append(piece)
        continue
      }
      if isBeforeNewline && piece.isBlank {
        continue
      }
      trimmedReversedPieces.append(piece)
      isBeforeNewline = false
    }
    return Trivia(pieces: trimmedReversedPieces.reversed())
  }

  /// Returns `true` if
  ///  - the trivia contains a newline followed by a space or tab
  ///  - `isOnNewline` is `true` (indicating that previous trivia ended with a
  ///     newline) and the trivia starts with a space or tab
  func containsIndentation(isOnNewline: Bool) -> Bool {
    var afterNewline = isOnNewline
    for piece in pieces {
      if piece.isNewline {
        afterNewline = true
      } else if afterNewline && piece.isIndentationWhitespace {
        return true
      }
    }
    return false
  }

  /// Returns the first indentation level of the first non-empty line in this
  /// trivia or `nil` if there is no newline.
  /// If `isOnNewline` is `true`, then the trivia is preceeded by a newline
  /// character and any indentation at its start will be returned.
  func indentation(isOnNewline: Bool) -> Trivia? {
    var isOnNewline = isOnNewline
    var pieces = self.pieces[...]
    while pieces.first?.isNewline ?? false {
      pieces = pieces.dropFirst()
      isOnNewline = true
    }
    if !isOnNewline {
      return nil
    }
    var indentation: [TriviaPiece] = []
    while let piece = pieces.first, piece.isIndentationWhitespace {
      indentation.append(piece)
      pieces = pieces.dropFirst()
    }
    return Trivia(pieces: indentation)
  }

  /// Adds `indentation` after every newline in this
  func indented(indentation: Trivia, isOnNewline: Bool) -> Trivia {
    guard !isEmpty else {
      if isOnNewline {
        return indentation
      }
      return self
    }

    var indentedPieces: [TriviaPiece] = []
    if isOnNewline {
      indentedPieces.append(contentsOf: indentation)
    }

    for piece in pieces {
      indentedPieces.append(piece)
      if piece.isNewline {
        indentedPieces.append(contentsOf: indentation)
      }
    }

    return Trivia(pieces: indentedPieces)
  }
}
