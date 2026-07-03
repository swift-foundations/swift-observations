// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-observations open source project
//
// Copyright (c) 2024-2026 Coen ten Thije Boonkkamp and the swift-observations
// project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import SwiftSyntax
import SwiftSyntaxMacros

/// Implementation of `@_ObservationTracked` — the property-level
/// helper synthesized by `@Observable`'s `MemberAttributeMacro`.
///
/// `_ObservationTracked` is not intended for direct user invocation.
/// `@Observable` reattaches it to each tracked `var` with the
/// per-property index, then this macro fires:
///
/// - `AccessorMacro` synthesizes `init`/`_read`/`_modify` accessors,
///   routing through `_$registrar` and recording reads against the
///   active ``withObservationTracking(_:onChange:)`` frame.
/// - `PeerMacro` synthesizes the underscore-prefixed storage peer.
///
/// The `init` accessor uses `@storageRestrictions(initializes:_x)` so
/// the user's `var x: Int = 0` initializer flows into the `_x` peer
/// at construction time, preserving the user-facing memberwise init.
public struct ObservationTrackedMacro {}

// MARK: - Helpers

extension VariableDeclSyntax {
  /// Returns the binding's identifier and trimmed type, when the
  /// declaration carries a single typed binding.
  fileprivate var trackedBinding: (name: TokenSyntax, type: TypeSyntax)? {
    guard bindings.count == 1, let binding = bindings.first,
      let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
      let typeAnnotation = binding.typeAnnotation
    else { return nil }
    return (identifier.identifier.trimmed, typeAnnotation.type.trimmed)
  }
}

private func extractID(from node: AttributeSyntax) -> UInt32 {
  guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
    let firstArg = arguments.first,
    let intExpr = firstArg.expression.as(IntegerLiteralExprSyntax.self),
    let value = UInt32(intExpr.literal.text)
  else { return 0 }
  return value
}

// MARK: - AccessorMacro

extension ObservationTrackedMacro: AccessorMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws(Never) -> [AccessorDeclSyntax] {
    guard let varDecl = declaration.as(VariableDeclSyntax.self),
      let (name, _) = varDecl.trackedBinding
    else {
      return []
    }
    let storage: TokenSyntax = .identifier("_\(name.text)")
    let id = extractID(from: node)

    let initAcc: AccessorDeclSyntax = """
      @storageRestrictions(initializes: \(storage))
      init(initialValue) {
          \(storage) = initialValue
      }
      """
    let readAcc: AccessorDeclSyntax = """
      _read {
          Observation.Tracking.access(_$registrar, .init(\(raw: id)))
          yield \(storage)
      }
      """
    let modifyAcc: AccessorDeclSyntax = """
      _modify {
          _$registrar.willSet(.init(\(raw: id)))
          yield &\(storage)
          _$registrar.didSet(.init(\(raw: id)))
      }
      """
    return [initAcc, readAcc, modifyAcc]
  }
}

// MARK: - PeerMacro

extension ObservationTrackedMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws(Never) -> [DeclSyntax] {
    guard let varDecl = declaration.as(VariableDeclSyntax.self),
      let (name, type) = varDecl.trackedBinding
    else {
      return []
    }
    let storage: TokenSyntax = .identifier("_\(name.text)")
    return ["var \(storage): \(type)"]
  }
}
