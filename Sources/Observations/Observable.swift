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

/// Synthesizes the boilerplate `Observable` conformance for a Subject.
///
/// Apply `@Observable` to a `class`, `struct`, `~Copyable struct`, or
/// `actor` whose stored properties should participate in observation
/// tracking. The macro generates:
///
/// - A stored `_$registrar: Observation.Registrar` field.
/// - An `Observable` conformance.
/// - For each stored `var`, an init/`_read`/`_modify` accessor block
///   that records reads against the active
///   ``withObservationTracking(_:onChange:)`` frame and notifies
///   observers on writes via the registrar (synthesized by the
///   companion ``_ObservationTracked(_:)`` macro).
/// - For each stored `var`, an underscore-prefixed peer storage
///   property of the same type (e.g., `var x: Int = 0` produces a
///   peer `var _x: Int`).
///
/// Per-property identifiers are sequential `UInt32` values assigned in
/// declaration order. Stability across recompiles is guaranteed by
/// source order, not by hash.
///
/// ## Example
///
/// ```swift
/// @Observable
/// struct Counter {
///     var x: Int = 0
///     var y: Int = 0
/// }
///
/// var counter = Counter()
/// _ = withObservationTracking {
///     counter.x
/// } onChange: {
///     print("x changed")
/// }
/// counter.x = 1   // prints "x changed"
/// ```
@attached(member, names: named(_$registrar))
@attached(extension, conformances: Observable)
@attached(memberAttribute)
public macro Observable() = #externalMacro(
    module: "Observations_Macros",
    type: "ObservableMacro"
)
