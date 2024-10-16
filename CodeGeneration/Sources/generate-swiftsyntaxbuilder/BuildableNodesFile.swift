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

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SyntaxSupport
import Utils

let buildableNodesFile = SourceFile {
  ImportDecl(
    leadingTrivia: .docLineComment(copyrightHeader),
    path: [AccessPathComponent(name: "SwiftSyntax")]
  )

  for node in SYNTAX_NODES where node.isBuildable {
    let type = node.type
    let hasTrailingComma = node.traits.contains("WithTrailingComma")

    // Generate node struct
    ExtensionDecl(
      leadingTrivia: node.documentation.isEmpty
        ? []
        : .docLineComment("/// \(node.documentation)") + .newline,
      extendedType: Type(type.shorthandName),
      inheritanceClause: hasTrailingComma ? TypeInheritanceClause { InheritedType(typeName: Type("HasTrailingComma")) } : nil
    ) {
      // Generate initializers
      createDefaultInitializer(node: node)
      if let convenienceInit = createConvenienceInitializer(node: node) {
        convenienceInit
      }

      if hasTrailingComma {
        VariableDecl(
          """
          var hasTrailingComma: Bool {
            return trailingComma != nil
          }
          """
        )

        FunctionDecl(
          """
          /// Conformance to `HasTrailingComma`.
          public func withTrailingComma(_ withComma: Bool) -> Self {
            return withTrailingComma(withComma ? .commaToken() : nil)
          }
          """
        )
      }
    }
  }
}

private func convertFromSyntaxProtocolToSyntaxType(child: Child) -> Expr {
  if child.type.isBaseType && child.nodeChoices.isEmpty {
    return Expr(FunctionCallExpr("\(child.type.syntaxBaseName)(fromProtocol: \(child.swiftName))"))
  } else {
    return Expr(IdentifierExpr(child.swiftName))
  }
}

/// Create the default initializer for the given node.
private func createDefaultInitializer(node: Node) -> InitializerDecl {
  let type = node.type
  return InitializerDecl(
    leadingTrivia: ([
      "/// Creates a `\(type.shorthandName)` using the provided parameters.",
      "/// - Parameters:",
    ] + node.children.map { child in
      "///   - \(child.swiftName): \(child.documentation)"
    }).map { .docLineComment($0) + .newline }.reduce([], +),
    // FIXME: If all parameters are specified, the SwiftSyntaxBuilder initializer is ambigious
    // with the memberwise initializer in SwiftSyntax.
    // Hot-fix this by preferring the overload in SwiftSyntax. In the long term, consider sinking
    // this initializer to SwiftSyntax.
    attributes: AttributeList { CustomAttribute("_disfavoredOverload").withTrailingTrivia(.space) },
    modifiers: [DeclModifier(name: .public)],
    signature: FunctionSignature(
      input: ParameterClause {
        for trivia in ["leadingTrivia", "trailingTrivia"] {
          FunctionParameter(
            firstName: .identifier(trivia),
            colon: .colon,
            type: Type("Trivia"),
            defaultArgument: InitializerClause(value: ArrayExpr())
          )
        }
        for child in node.children {
          FunctionParameter(
            firstName: .identifier(child.swiftName),
            colon: .colon,
            type: child.parameterType,
            defaultArgument: child.type.defaultInitialization.map { InitializerClause(value: $0) }
          )
        }
      }
    )
  ) {
    for child in node.children {
      if let assertStmt = child.generateAssertStmtTextChoices(varName: child.swiftName) {
        assertStmt
      }
    }
    let nodeConstructorCall = FunctionCallExpr(calledExpression: Expr(type.syntaxBaseName)) {
      for child in node.children {
        TupleExprElement(
          label: child.isUnexpectedNodes ? nil : child.swiftName,
          expression: convertFromSyntaxProtocolToSyntaxType(child: child)
        )
      }
    }
    SequenceExpr("self = \(nodeConstructorCall)")
    SequenceExpr("self.leadingTrivia = leadingTrivia + (self.leadingTrivia ?? [])")
    SequenceExpr("self.trailingTrivia = trailingTrivia + (self.trailingTrivia ?? [])")
  }
}

/// Create a builder-based convenience initializer, if needed.
private func createConvenienceInitializer(node: Node) -> InitializerDecl? {
  // Only create the convenience initializer if at least one parameter
  // is different than in the default initializer generated above.
  var shouldCreateInitializer = false

  // Keep track of init parameters and result builder parameters in different
  // lists to make sure result builder params occur at the end, so that
  // they can use trailing closure syntax.
  var normalParameters: [FunctionParameter] = []
  var builderParameters: [FunctionParameter] = []
  var delegatedInitArgs: [TupleExprElement] = []

  for child in node.children {
    /// The expression that is used to call the default initializer defined above.
    let produceExpr: Expr
    if child.type.isBuilderInitializable {
      // Allow initializing certain syntax collections with result builders
      shouldCreateInitializer = true
      let builderInitializableType = child.type.builderInitializableType
      if child.type.builderInitializableType != child.type {
        let param = Node.from(type: child.type).singleNonDefaultedChild
        if child.isOptional {
          produceExpr = Expr(FunctionCallExpr("\(child.swiftName)Builder().map { \(child.type.syntaxBaseName)(\(param.swiftName): $0) }"))
        } else {
          produceExpr = Expr(FunctionCallExpr("\(child.type.syntaxBaseName)(\(param.swiftName): \(child.swiftName)Builder())"))
        }
      } else {
        produceExpr = Expr(FunctionCallExpr("\(child.swiftName)Builder()"))
      }
      builderParameters.append(FunctionParameter(
        attributes: [CustomAttribute(attributeName: Type(builderInitializableType.resultBuilderBaseName), argumentList: nil)],
        firstName: .identifier("\(child.swiftName)Builder").withLeadingTrivia(.space),
        colon: .colon,
        type: FunctionType(
          arguments: [],
          returnType: builderInitializableType.syntax
        ),
        defaultArgument: InitializerClause(value: ClosureExpr {
          if child.type.isOptional {
            NilLiteralExpr()
          } else {
            FunctionCallExpr("\(builderInitializableType.syntax)([])")
          }
        })
      ))
    } else if let token = child.type.token, token.text == nil {
      // Allow initializing identifiers and other tokens without default text with a String
      shouldCreateInitializer = true
      let paramType = child.type.optionalWrapped(type: Type("String"))
      let tokenExpr = MemberAccessExpr("Token.\(token.swiftKind.withFirstCharacterLowercased.backticked)")
      if child.type.isOptional {
        produceExpr = Expr(FunctionCallExpr("\(child.swiftName).map { \(tokenExpr)($0) }"))
      } else {
        produceExpr = Expr(FunctionCallExpr("\(tokenExpr)(\(child.swiftName))"))
      }
      normalParameters.append(FunctionParameter(
        firstName: .identifier(child.swiftName),
        colon: .colon,
        type: paramType
      ))
    } else {
      produceExpr = convertFromSyntaxProtocolToSyntaxType(child: child)
      normalParameters.append(FunctionParameter(
        firstName: .identifier(child.swiftName),
        colon: .colon,
        type: child.parameterType,
        defaultArgument: child.type.defaultInitialization.map { InitializerClause(value: $0) }
      ))
    }
    delegatedInitArgs.append(TupleExprElement(label: child.isUnexpectedNodes ? nil : child.swiftName, expression: produceExpr))
  }

  guard shouldCreateInitializer else {
    return nil
  }

  return InitializerDecl(
    leadingTrivia: [
      "/// A convenience initializer that allows:",
      "///  - Initializing syntax collections using result builders",
      "///  - Initializing tokens without default text using strings",
    ].map { .docLineComment($0) + .newline }.reduce([], +),
    // FIXME: If all parameters are specified, the SwiftSyntaxBuilder initializer is ambigious
    // with the memberwise initializer in SwiftSyntax.
    // Hot-fix this by preferring the overload in SwiftSyntax. In the long term, consider sinking
    // this initializer to SwiftSyntax.
    attributes: AttributeList { CustomAttribute("_disfavoredOverload").withTrailingTrivia(.space) },
    modifiers: [DeclModifier(name: .public)],
    signature: FunctionSignature(
      input: ParameterClause {
        FunctionParameter(
          firstName: .identifier("leadingTrivia"),
          colon: .colon,
          type: Type("Trivia"),
          defaultArgument: InitializerClause(value: ArrayExpr())
        )
        for param in normalParameters + builderParameters {
          param
        }
      }
    )
  ) {
    FunctionCallExpr(calledExpression: MemberAccessExpr("self.init")) {
      for arg in delegatedInitArgs {
        arg
      }
    }

    SequenceExpr("self.leadingTrivia = leadingTrivia + (self.leadingTrivia ?? [])")
  }
}

