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

/// The property-level helper macro synthesized by `@Observable`'s
/// `MemberAttributeMacro` — not intended for direct user invocation.
///
/// `@Observable` reattaches `@_ObservationTracked(N)` to each stored
/// `var` in a Subject's body, where `N` is the per-property
/// `Observation.Property.ID` index assigned in declaration order. The
/// macro then:
///
/// - Adds `init`/`_read`/`_modify` accessors that route through
///   `_$registrar` and record reads against the active tracking frame.
/// - Adds an underscore-prefixed peer storage property of the same
///   type (e.g., `_x` for `var x`).
///
/// The `_` prefix on the macro name flags it as an implementation
/// detail. Direct invocation works (the macro is `public` because the
/// macro engine resolves it at the user's call site) but is not part
/// of the supported surface — call sites should use `@Observable` on
/// the enclosing type and let the framework reattach this helper.
@attached(accessor, names: named(init), named(_read), named(_modify))
@attached(peer, names: prefixed(_))
public macro _ObservationTracked(_ id: UInt32 = 0) =
  #externalMacro(
    module: "Observations_Macros",
    type: "ObservationTrackedMacro"
  )
