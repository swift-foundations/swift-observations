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

extension Observation.Tracking {
    /// Records a read of `propertyID` on `registrar` against the
    /// current tracking frame on this thread.
    ///
    /// If no `withObservationTracking` body is active on the calling
    /// thread, this is a no-op. If a frame is active, the
    /// `(registrar, propertyID)` pair is recorded for one-shot
    /// onChange dispatch when the body returns.
    ///
    /// Hand-authored `_read` accessors call this directly:
    /// ```swift
    /// var raw: Int {
    ///     _read {
    ///         Observation.Tracking.access(_$registrar, .init(0))
    ///         yield _raw
    ///     }
    /// }
    /// ```
    ///
    /// The forthcoming `@Observable` macro will generate equivalent
    /// calls automatically.
    public static func access(
        _ registrar: Observation.Registrar,
        _ propertyID: Observation.Property.ID
    ) {
        guard let frame = currentFrame() else { return }
        frame.record(registrar, propertyID)
    }
}
