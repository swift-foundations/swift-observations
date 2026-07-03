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

/// Implementation of the `@Observable` type-level attached macro.
///
/// `@Observable` is applied to a `struct`, `class`, `actor`, or
/// `~Copyable struct` Subject. Three protocols fire in one pass:
///
/// - `MemberMacro` synthesizes the stored `_$registrar` field.
/// - `ExtensionMacro` synthesizes the `Observable` conformance.
/// - `MemberAttributeMacro` reattaches `@_ObservationTracked(N)` to
///   each stored `var` in declaration order, with a sequential
///   `UInt32` index argument. The companion `ObservationTrackedMacro`
///   then synthesizes the per-property accessor block and the
///   underscore-prefixed storage peer.
///
/// The `_ObservationTracked` helper is `_`-prefixed to flag it as an
/// implementation detail not intended for direct user invocation.
/// Apple's `@Observable` macro uses the same two-macro split for the
/// same reason — Swift validates every `@attached(...)` form against
/// the attachment site, so a single macro cannot host both type-level
/// and property-level forms.
public struct ObservableMacro {}

// MARK: - Helpers

extension VariableDeclSyntax {
  /// Whether this `var` is a stored, non-static, non-computed
  /// property eligible for observation tracking.
  fileprivate var isObservableStored: Bool {
    guard bindingSpecifier.tokenKind == .keyword(.var) else { return false }
    for modifier in modifiers {
      switch modifier.name.tokenKind {
      case .keyword(.static), .keyword(.class), .keyword(.lazy):
        return false

      default:
        continue
      }
    }
    for binding in bindings {
      if binding.accessorBlock != nil { return false }
      if let id = binding.pattern.as(IdentifierPatternSyntax.self),
        id.identifier.text.hasPrefix("_")
      {
        return false
      }
    }
    return true
  }

  /// The first binding's identifier text.
  fileprivate var firstBindingName: String? {
    guard let binding = bindings.first,
      let id = binding.pattern.as(IdentifierPatternSyntax.self)
    else { return nil }
    return id.identifier.text
  }
}

// MARK: - MemberMacro

extension ObservableMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws(Never) -> [DeclSyntax] {
    // `conformingTo` reports the conformances requested via
    // `@attached(extension, conformances: …)`. The member
    // synthesis is the same regardless — we always emit
    // `_$registrar`; the `Observable` conformance itself is added
    // by the `ExtensionMacro` form below.
    _ = protocols

    for member in declaration.memberBlock.members {
      if let varDecl = member.decl.as(VariableDeclSyntax.self),
        varDecl.bindings.contains(where: { binding in
          binding.pattern.as(IdentifierPatternSyntax.self)?
            .identifier.text == "_$registrar"
        })
      {
        return []
      }
    }
    return [
      "let _$registrar: Observation.Registrar = Observation.Registrar()"
    ]
  }
}

// MARK: - ExtensionMacro

extension ObservableMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws(Never) -> [ExtensionDeclSyntax] {
    if let inherits = declaration.inheritanceClause {
      for entry in inherits.inheritedTypes {
        let token = entry.type.trimmedDescription
        if token == "Observable" || token == "Observation.Observable"
          || token == "Observation.Protocol" || token == "Observation.`Protocol`"
        {
          return []
        }
      }
    }
    let extensionDecl: DeclSyntax = """
      extension \(type.trimmed): Observable {}
      """
    return [extensionDecl.cast(ExtensionDeclSyntax.self)]
  }
}

// MARK: - MemberAttributeMacro

extension ObservableMacro: MemberAttributeMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingAttributesFor member: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws(Never) -> [AttributeSyntax] {
    guard let varDecl = member.as(VariableDeclSyntax.self),
      varDecl.isObservableStored,
      let varName = varDecl.firstBindingName
    else {
      return []
    }
    for attr in varDecl.attributes {
      if let attribute = attr.as(AttributeSyntax.self),
        let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self),
        identifier.name.text == "_ObservationTracked"
      {
        return []
      }
    }
    var index: UInt32 = 0
    for memberItem in declaration.memberBlock.members {
      guard let candidate = memberItem.decl.as(VariableDeclSyntax.self) else { continue }
      if candidate.firstBindingName == varName {
        break
      }
      if candidate.isObservableStored {
        index += 1
      }
    }
    return ["@_ObservationTracked(\(raw: index))"]
  }
}
