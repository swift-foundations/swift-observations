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

extension Observation {
    /// The tracking namespace.
    ///
    /// Hosts the per-thread tracking context that records which
    /// ``Observation/Property/ID``s are read across the body of a
    /// ``withObservationTracking(_:onChange:)`` invocation, plus the
    /// static `access(_:_:)` entry point that the macro-generated
    /// `_read` accessors call to record a single read.
    ///
    /// ## Threading model
    ///
    /// The current ``Observation/Tracking/Frame`` lives in a
    /// `Kernel.Thread.Local` slot. Synchronous access from the same
    /// thread (e.g., a SwiftUI body evaluation, a render pass, a
    /// computed-property fan-out) sees the active frame; async hops
    /// across threads do NOT propagate it — the tracking primitive
    /// is intended for synchronous code paths where `TaskLocal`
    /// would not propagate either.
    ///
    /// Frames stack via `Frame.parent` for nested
    /// `withObservationTracking` calls — only the innermost frame
    /// records accesses (matching Apple's framework semantics).
    public enum Tracking {}
}
